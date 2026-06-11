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

(declare-function gptel-make-anthropic "gptel-anthropic")
(defvar gptel-backend)
(defvar gptel-model)

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
  ps/gptel--backend)

(provide 'ps-gptel)
;;; ps-gptel.el ends here
