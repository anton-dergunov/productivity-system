;;; ps-gptel.el --- gptel + Claude via the Pro subscription (Claude Code OAuth) -*- lexical-binding: t; -*-

;;; Commentary:
;; Configures gptel to talk to Claude through the user's Claude Pro/Max
;; subscription instead of the metered API, by reusing the OAuth token that
;; Claude Code stores in the macOS Keychain.
;;
;; The Anthropic API only accepts that token when the request (a) authenticates
;; with `Authorization: Bearer', (b) sends the `anthropic-beta: oauth-2025-04-20'
;; header, and (c) puts the Claude Code identity string as its first system
;; block.  We satisfy all three around gptel's Anthropic backend: a header
;; function supplies (a) and (b); an `:around' advice on `gptel--request-data'
;; supplies (c).
;;
;; Token lifecycle is owned by Claude Code -- we only read.  Refreshing the token
;; ourselves would rotate the refresh token and break Claude Code's own auth, so
;; if the stored token has expired we surface a clear message telling the user to
;; run any `claude' command once to refresh it.

;;; Code:

(require 'subr-x)
(require 'cl-lib)

(declare-function gptel-make-anthropic "gptel-anthropic")
(declare-function gptel-make-gemini "gptel-gemini")
(declare-function gptel-make-ollama "gptel-ollama")
(declare-function gptel-context-add-file "gptel-context")
(declare-function gptel-context-remove-all "gptel-context")
(declare-function gptel-make-tool "gptel-request")
(declare-function gptel-tool-name "gptel-request")
(declare-function gptel-api-key-from-auth-source "gptel-request")
(declare-function gptel-request "gptel-request")
(declare-function auth-source-search "auth-source")
(defvar gptel-backend)
(defvar gptel-model)
(defvar gptel-tools)
(defvar my-org-base-directory)

;;; Customization

(defcustom ps/gptel-keychain-service "Claude Code-credentials"
  "macOS Keychain generic-password service holding the Claude Code OAuth token."
  :type 'string
  :group 'gptel)

(defcustom ps/gptel-default-model 'claude-opus-4-8
  "Default Claude model symbol used by gptel."
  :type 'symbol
  :group 'gptel)

(defcustom ps/gptel-models '(claude-opus-4-8 claude-sonnet-4-6 claude-haiku-4-5)
  "Claude model symbols offered in gptel's model switcher."
  :type '(repeat symbol)
  :group 'gptel)

(defcustom ps/gptel-quick-model 'claude-haiku-4-5
  "Model used by `ps/gptel-quick' for one-off questions."
  :type 'symbol
  :group 'gptel)

(defcustom ps/gptel-notes-directory
  (or (bound-and-true-p my-org-base-directory) "~/org/")
  "Root directory of org notes exposed to gptel via context and tools."
  :type 'directory
  :group 'gptel)

(defcustom ps/gptel-gemini-models '(gemini-2.5-flash gemini-2.5-flash-lite)
  "Gemini model symbols offered when the Gemini backend is registered."
  :type '(repeat symbol)
  :group 'gptel)

(defcustom ps/gptel-ollama-host "localhost:11434"
  "Host (and port) of a local Ollama server, e.g. \"localhost:11434\"."
  :type 'string
  :group 'gptel)

(defcustom ps/gptel-ollama-models '(llama3.2:latest)
  "Ollama model symbols offered when an Ollama server is reachable."
  :type '(repeat symbol)
  :group 'gptel)

;;; Constants

(defconst ps/gptel-claude-code-identity
  "You are Claude Code, Anthropic's official CLI for Claude."
  "Identity string Anthropic requires as the first system block for OAuth tokens.")

(defconst ps/gptel--backend-name "Claude (subscription)"
  "Name of the gptel backend registered by `ps/gptel-setup'.")

(defconst ps/gptel--token-expiry-skew 60
  "Seconds before `expiresAt' at which a cached token is treated as stale.")

;;; State

(defvar ps/gptel--backend nil
  "The gptel backend object registered by `ps/gptel-setup'.")

(defvar ps/gptel--token nil
  "Cached OAuth access token string, or nil.")

(defvar ps/gptel--token-expiry 0
  "Epoch seconds at which the cached token in `ps/gptel--token' expires.")

;;; Credentials

(defun ps/gptel--parse-credentials (json-string)
  "Parse JSON-STRING from the Keychain into a plist (:token :expiry).
EXPIRY is epoch seconds.  Pure (no subprocess), so it is unit-testable."
  (let* ((obj (json-parse-string json-string :object-type 'alist))
         (oauth (or (alist-get 'claudeAiOauth obj) obj))
         (token (alist-get 'accessToken oauth))
         (expires-ms (alist-get 'expiresAt oauth)))
    (unless (stringp token)
      (error "No accessToken in Claude Code credentials"))
    (list :token token
          :expiry (if (numberp expires-ms) (/ expires-ms 1000.0) 0))))

(defun ps/gptel--read-credentials ()
  "Read and parse the Claude Code OAuth credentials from the macOS Keychain.
Return a plist (:token :expiry).  Signal a clear error if unavailable."
  (with-temp-buffer
    (let ((status (call-process "security" nil t nil
                                "find-generic-password"
                                "-s" ps/gptel-keychain-service "-w")))
      (unless (eq status 0)
        (user-error "Cannot read Claude Code credentials from Keychain (service %S); is Claude Code logged in?"
                    ps/gptel-keychain-service))
      (ps/gptel--parse-credentials (string-trim (buffer-string))))))

(defun ps/gptel--token-valid-p (expiry)
  "Return non-nil if EXPIRY (epoch seconds) is comfortably in the future."
  (> expiry (+ (float-time) ps/gptel--token-expiry-skew)))

(defun ps/gptel--oauth-token (&rest _)
  "Return a currently-valid Claude OAuth access token string.
Re-reads the Keychain when the cached token is missing or near expiry.
Signal a `user-error' if even the freshest token is expired."
  (unless (and ps/gptel--token (ps/gptel--token-valid-p ps/gptel--token-expiry))
    (let ((creds (ps/gptel--read-credentials)))
      (setq ps/gptel--token (plist-get creds :token)
            ps/gptel--token-expiry (plist-get creds :expiry))))
  (unless (ps/gptel--token-valid-p ps/gptel--token-expiry)
    (user-error "Claude OAuth token has expired; run any `claude' command once to refresh it, then retry"))
  ps/gptel--token)

;;; Request shaping

(defun ps/gptel--headers (&optional _info)
  "Return the HTTP headers for an OAuth-authenticated Anthropic request.
Used as the `:header' function of the gptel Anthropic backend."
  `(("authorization" . ,(concat "Bearer " (ps/gptel--oauth-token)))
    ("anthropic-version" . "2023-06-01")
    ("anthropic-beta" . "oauth-2025-04-20")))

(defun ps/gptel--system-block (text)
  "Return an Anthropic system content block plist holding TEXT."
  (list :type "text" :text text))

(defun ps/gptel--inject-identity (data)
  "Return request plist DATA with the Claude Code identity as first system block.
Handles `:system' being nil, a string, a single block plist, or a vector/list of
blocks, and avoids duplicating the identity if it is already first.  Pure."
  (let* ((sys (plist-get data :system))
         (identity (ps/gptel--system-block ps/gptel-claude-code-identity))
         (rest (cond
                ((null sys) nil)
                ((stringp sys) (list (ps/gptel--system-block sys)))
                ((vectorp sys) (append sys nil))
                ((and (consp sys) (keywordp (car sys))) (list sys))
                ((consp sys) sys)
                (t (list (ps/gptel--system-block (format "%s" sys))))))
         (rest (if (and rest
                        (equal (plist-get (car rest) :text)
                               ps/gptel-claude-code-identity))
                   (cdr rest)
                 rest)))
    (plist-put data :system (vconcat (list identity) rest))))

(defun ps/gptel--request-data-advice (orig backend prompts &rest args)
  "Force the Claude Code identity into the system prompt for our OAuth backend.
ORIG is `gptel--request-data'; BACKEND, PROMPTS and ARGS are its arguments."
  (let ((data (apply orig backend prompts args)))
    (if (eq backend ps/gptel--backend)
        (ps/gptel--inject-identity data)
      data)))

;;; Notes access

(defun ps/gptel--notes-root ()
  "Return `ps/gptel-notes-directory' as an absolute directory name."
  (file-name-as-directory (expand-file-name ps/gptel-notes-directory)))

(defun ps/gptel--notes-resolve-path (root relative-path)
  "Resolve RELATIVE-PATH against ROOT, returning its absolute path.
Signal a `user-error' if the resolved path would escape ROOT, e.g. via
\"..\" components or an absolute path elsewhere.  Pure (no filesystem
access)."
  (let ((resolved (expand-file-name (or relative-path ".") root)))
    (unless (or (string-prefix-p root resolved)
                (equal resolved (directory-file-name root)))
      (user-error "Path %S is outside the notes directory" relative-path))
    resolved))

(defun ps/gptel-add-notes ()
  "Add all org notes under `ps/gptel-notes-directory' to gptel's context.
Use `ps/gptel-clear-context' to remove them again."
  (interactive)
  (require 'gptel-context)
  (let* ((root (ps/gptel--notes-root))
         (files (directory-files-recursively root "\\.org\\'")))
    (dolist (file files)
      (gptel-context-add-file file))
    (message "Added %d org note(s) from %s to gptel context" (length files) root)))

(defun ps/gptel-clear-context ()
  "Remove all files and regions from gptel's context."
  (interactive)
  (require 'gptel-context)
  (gptel-context-remove-all t))

(defun ps/gptel-tool--list-notes (&optional directory)
  "Return a newline-separated list of org note paths under DIRECTORY.
DIRECTORY is relative to `ps/gptel-notes-directory' and defaults to its root.
Paths in the result are relative to the notes root."
  (let* ((root (ps/gptel--notes-root))
         (dir (ps/gptel--notes-resolve-path root directory))
         (files (directory-files-recursively dir "\\.org\\'")))
    (mapconcat (lambda (f) (file-relative-name f root)) files "\n")))

(defun ps/gptel-tool--read-note (path)
  "Return the contents of the org note at PATH (relative to the notes root)."
  (let* ((root (ps/gptel--notes-root))
         (file (ps/gptel--notes-resolve-path root path)))
    (unless (file-readable-p file)
      (user-error "No such note: %s" path))
    (with-temp-buffer
      (insert-file-contents file)
      (buffer-string))))

(defun ps/gptel-tool--search-notes (query)
  "Search org notes under `ps/gptel-notes-directory' for QUERY via ripgrep.
Return matching lines as \"path:line:text\", with paths relative to the
notes root."
  (let ((default-directory (ps/gptel--notes-root)))
    (with-temp-buffer
      (call-process "rg" nil t nil
                     "--line-number" "--no-heading" "--glob" "*.org"
                     "--" query ".")
      (buffer-string))))

(declare-function ps/org-db-ensure-server "ps-org-db")
(declare-function ps/org-db-sync-directory "ps-org-db")
(declare-function ps/org-db-semantic-results "ps-org-db")

(defun ps/gptel-tool--semantic-search-notes (query)
  "Semantically search org notes under `ps/gptel-notes-directory' for QUERY.
Uses org-db-v3 embeddings, finding conceptually related notes even without
keyword overlap. Return matches as \"path:line: snippet\", with paths
relative to the notes root."
  (require 'ps-org-db)
  (ps/org-db-ensure-server)
  (ps/org-db-sync-directory t)
  (let ((root (ps/gptel--notes-root)))
    (mapconcat
     (lambda (item)
       (format "%s:%s: %s"
               (file-relative-name (plist-get item :filename) root)
               (or (plist-get item :begin-line) "?")
               (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " (plist-get item :snippet)))))
     (ps/org-db-semantic-results query)
     "\n")))

(defun ps/gptel--register-tool (tool)
  "Add TOOL to `gptel-tools', replacing any existing tool with the same name."
  (setq gptel-tools
        (cons tool (cl-remove (gptel-tool-name tool) gptel-tools
                               :key #'gptel-tool-name :test #'equal))))

(defun ps/gptel--register-notes-tools ()
  "Register gptel tools for browsing and searching the notes directory.
These let the model pull specific notes on demand instead of requiring
everything to be added to context up front via `ps/gptel-add-notes'."
  (require 'gptel)
  (ps/gptel--register-tool
   (gptel-make-tool
    :name "list_notes"
    :function #'ps/gptel-tool--list-notes
    :description "List org note files under a directory of the user's notes, recursively. Returns paths relative to the notes root."
    :args (list '(:name "directory"
                   :type string
                   :description "Directory to list, relative to the notes root. Use \".\" or omit for the root."
                   :optional t))
    :category "notes"))
  (ps/gptel--register-tool
   (gptel-make-tool
    :name "read_note"
    :function #'ps/gptel-tool--read-note
    :description "Read the full contents of an org note file, given its path relative to the notes root (as returned by list_notes or search_notes)."
    :args (list '(:name "path"
                   :type string
                   :description "Path to the note, relative to the notes root."))
    :category "notes"))
  (ps/gptel--register-tool
   (gptel-make-tool
    :name "search_notes"
    :function #'ps/gptel-tool--search-notes
    :description "Search the user's org notes for a query string using ripgrep. Returns matching lines as \"path:line:text\"."
    :args (list '(:name "query"
                   :type string
                   :description "Text or regular expression to search for."))
    :category "notes"))
  (ps/gptel--register-tool
   (gptel-make-tool
    :name "semantic_search_notes"
    :function #'ps/gptel-tool--semantic-search-notes
    :description "Semantically search the user's org notes for a concept or question, using embeddings. Finds relevant notes even when wording doesn't overlap with the query (unlike search_notes). Returns matches as \"path:line: snippet\"."
    :args (list '(:name "query"
                   :type string
                   :description "Natural-language query or question."))
    :category "notes")))

;;; Quick ask

(defun ps/gptel-quick (prompt)
  "Ask PROMPT as a one-shot question and show the answer in a popup buffer.
Uses the active region as PROMPT when one is selected.  Runs on
`ps/gptel-quick-model' over the subscription backend; creates no chat
session or history."
  (interactive
   (list (if (use-region-p)
             (buffer-substring-no-properties (region-beginning) (region-end))
           (read-string "Ask: "))))
  (require 'gptel)
  (let ((buf (get-buffer-create "*gptel-quick*")))
    (with-current-buffer buf
      (org-mode)
      (setq-local gptel-backend ps/gptel--backend
                   gptel-model ps/gptel-quick-model
                   gptel-use-tools nil)
      (erase-buffer)
      (insert "* " prompt "\n\n** Answer\n\nThinking...\n"))
    (display-buffer buf '(display-buffer-pop-up-window))
    (gptel-request prompt
      :buffer buf
      :callback
      (lambda (response _info)
        (with-current-buffer buf
          (goto-char (point-max))
          (forward-line -1)
          (delete-region (line-beginning-position) (point-max))
          (insert (if (stringp response) response "Error: no response.") "\n"))))))

;;; Additional backends

(defun ps/gptel--auth-source-secret (host &optional user)
  "Return the secret for HOST/USER from auth-source, or nil if absent."
  (require 'auth-source)
  (when-let* ((entry (car (auth-source-search :host host :user (or user "apikey")
                                               :require '(:secret))))
              (secret (plist-get entry :secret)))
    (if (functionp secret) (funcall secret) secret)))

(defun ps/gptel--ollama-available-p (host)
  "Return non-nil if an Ollama server is reachable at HOST (\"hostname:port\")."
  (let* ((parts (split-string host ":"))
         (hostname (car parts))
         (port (string-to-number (or (cadr parts) "11434"))))
    (condition-case nil
        (let ((proc (make-network-process :name "ps-gptel-ollama-probe"
                                           :host hostname :service port
                                           :nowait nil :coding 'binary)))
          (delete-process proc)
          t)
      (error nil))))

(defun ps/gptel--register-extra-backends ()
  "Register optional gptel backends when their credentials/endpoints exist.
The Claude OAuth bridge (`ps/gptel--backend') stays the default; these are
simply added to gptel's backend menu (`gptel-menu') for switching."
  (require 'gptel)
  ;; Gemini, free tier: register only if an API key is in auth-source.
  (when (ps/gptel--auth-source-secret "generativelanguage.googleapis.com")
    (gptel-make-gemini "Gemini"
      :key (lambda () (gptel-api-key-from-auth-source
                        "generativelanguage.googleapis.com"))
      :stream t
      :models ps/gptel-gemini-models))
  ;; Local Ollama: register only if the server is reachable.
  (when (ps/gptel--ollama-available-p ps/gptel-ollama-host)
    (gptel-make-ollama "Ollama"
      :host ps/gptel-ollama-host
      :stream t
      :models ps/gptel-ollama-models))
  ;; Official Anthropic API key (paid), as a fallback if the OAuth bridge
  ;; ever breaks: register only if a key is in auth-source.
  (when (ps/gptel--auth-source-secret "api.anthropic.com")
    (gptel-make-anthropic "Claude (API key)"
      :key (lambda () (gptel-api-key-from-auth-source "api.anthropic.com"))
      :stream t
      :models ps/gptel-models)))

;;; Setup

(defun ps/gptel-setup ()
  "Register the subscription-backed Claude backend and make it gptel's default.
Idempotent: safe to call more than once."
  (require 'gptel)
  (setq ps/gptel--backend
        (gptel-make-anthropic ps/gptel--backend-name
          :stream t
          :key #'ps/gptel--oauth-token
          :header #'ps/gptel--headers
          :models ps/gptel-models))
  (setq gptel-backend ps/gptel--backend
        gptel-model ps/gptel-default-model)
  (unless (advice-member-p #'ps/gptel--request-data-advice 'gptel--request-data)
    (advice-add 'gptel--request-data :around #'ps/gptel--request-data-advice))
  (ps/gptel--register-notes-tools)
  (ps/gptel--register-extra-backends)
  ps/gptel--backend)

(provide 'ps-gptel)
;;; ps-gptel.el ends here
