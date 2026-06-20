;;; ps-org-db.el --- Semantic + hybrid search over org notes via org-db-v3 -*- lexical-binding: t; -*-

;;; Commentary:
;; Wires org-db-v3 (https://github.com/jkitchin/org-db-v3) into this config to
;; provide semantic, full-text, and hybrid (RRF-fused) search over the org
;; notes directory, with background indexing on save.
;;
;; Only `org-db-v3-parse', `org-db-v3-server', and `org-db-v3-client' are
;; loaded -- the transient-based UI (`org-db-v3-ui'/`-agenda'/`-ignore', which
;; require `transient' and would hit the same version-skew issue as
;; `claude-code-ide-transient') is skipped entirely. Search commands and the
;; hybrid/RRF mode are implemented directly against the FastAPI endpoints.
;;
;; Run scripts/setup-org-db.sh once to clone org-db-v3 into elpa/org-db-v3 and
;; set up its Python server (uv sync).

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'json)

(declare-function plz "plz")
(declare-function org-db-v3-index-file-async "org-db-v3-client")
(declare-function org-db-v3-start-server "org-db-v3-server")
(declare-function org-db-v3-stop-server "org-db-v3-server")
(declare-function org-db-v3-ensure-server "org-db-v3-server")
(declare-function org-db-v3--port-in-use-p "org-db-v3-server")
(declare-function org-db-v3-kill-emacs-hook "org-db-v3-server")
(defvar ps/gptel-notes-directory)
(defvar my-org-base-directory)

;;; Customization

(defcustom ps/org-db-directory
  (or (bound-and-true-p ps/gptel-notes-directory)
      (bound-and-true-p my-org-base-directory)
      "~/org/")
  "Root directory of org notes indexed by org-db-v3."
  :type 'directory
  :group 'org-db-v3)

(defcustom ps/org-db-vendor-directory
  (expand-file-name "elpa/org-db-v3" user-emacs-directory)
  "Local checkout of org-db-v3 (see scripts/setup-org-db.sh)."
  :type 'directory
  :group 'org-db-v3)

(defcustom ps/org-db-search-limit 10
  "Maximum number of results requested per search leg."
  :type 'integer
  :group 'org-db-v3)

(defcustom ps/org-db-rrf-k 60
  "Constant K in the Reciprocal Rank Fusion formula 1/(K + rank)."
  :type 'integer
  :group 'org-db-v3)

;;; Minimal org-db-v3 runtime
;;
;; org-db-v3-server.el and org-db-v3-client.el reference these
;; defcustoms/defvars/functions, which normally live in the umbrella
;; org-db-v3.el (the file that also pulls in the transient UI). We re-declare
;; them here so the three files we DO want can be loaded standalone.

(defgroup org-db-v3 nil
  "Org database v3 with semantic search."
  :group 'org
  :prefix "org-db-v3-")

(defcustom org-db-v3-server-host "127.0.0.1"
  "Host for the org-db-v3 server."
  :type 'string
  :group 'org-db-v3)

(defcustom org-db-v3-server-port 8765
  "Port for the org-db-v3 server."
  :type 'integer
  :group 'org-db-v3)

(defcustom org-db-v3-auto-start-server t
  "Whether `org-db-v3-ensure-server' may start the server if not running."
  :type 'boolean
  :group 'org-db-v3)

(defcustom org-db-v3-debug nil
  "Enable debug messages for org-db-v3."
  :type 'boolean
  :group 'org-db-v3)

(defvar org-db-v3-server-process nil
  "Process running the org-db-v3 server, if started by this Emacs instance.")

(defvar org-db-v3-server-starting nil
  "Non-nil while the org-db-v3 server is starting up.")

(defun org-db-v3-server-url ()
  "Return the base URL for the org-db-v3 server."
  (format "http://%s:%d" org-db-v3-server-host org-db-v3-server-port))

(defun org-db-v3-server-running-p ()
  "Return non-nil if the org-db-v3 server responds to a health check."
  (require 'url-http)
  (condition-case err
      (let ((url-request-method "GET"))
        (with-timeout (3 nil)
          (with-current-buffer
              (url-retrieve-synchronously (concat (org-db-v3-server-url) "/health") t nil 3)
            (goto-char (point-min))
            (let ((status-line (buffer-substring-no-properties (point) (line-end-position))))
              (prog1 (string-match-p "200 OK" status-line)
                (kill-buffer))))))
    (error
     (when org-db-v3-debug
       (message "org-db-v3: health check failed: %S" err))
     nil)))

;;; Load org-db-v3-parse/-server/-client (no transient dependency)

(let ((elisp-dir (expand-file-name "elisp" ps/org-db-vendor-directory)))
  (if (file-directory-p elisp-dir)
      (progn
        (add-to-list 'load-path elisp-dir)
        (require 'org-db-v3-parse)
        (require 'org-db-v3-server)
        (setq org-db-v3-server-directory (expand-file-name "python" ps/org-db-vendor-directory))
        (require 'org-db-v3-client)
        ;; org-db-v3-server.el adds a kill-emacs-hook that stops the server
        ;; when THIS Emacs instance exits, if it tracked the process. With
        ;; multiple Emacs instances sharing one server, that could kill it out
        ;; from under the others -- shutdown is explicit via
        ;; `ps/org-db-stop-server' instead.
        (remove-hook 'kill-emacs-hook #'org-db-v3-kill-emacs-hook))
    (message "ps-org-db: org-db-v3 not found at %s -- run scripts/setup-org-db.sh"
             ps/org-db-vendor-directory)))

;;; Server lifecycle

(defun ps/org-db-ensure-server ()
  "Ensure the org-db-v3 server is running, starting it if necessary.
Safe to call from multiple Emacs instances: if the server is already healthy
this is a no-op, and if the port is in use but not yet answering health
checks (e.g. another Emacs instance's server is still loading its embedding
model on a cold start), we wait rather than calling
`org-db-v3-ensure-server' -- which would otherwise treat that process as a
zombie and kill it out from under the other instance."
  (interactive)
  (cond
   ((org-db-v3-server-running-p) t)
   ((org-db-v3--port-in-use-p org-db-v3-server-port)
    (message "org-db: server on port %d is starting up (possibly from another Emacs instance); try again shortly"
             org-db-v3-server-port)
    nil)
   ((fboundp 'org-db-v3-ensure-server)
    (org-db-v3-ensure-server))))

(defun ps/org-db-stop-server ()
  "Stop the org-db-v3 server explicitly."
  (interactive)
  (when (fboundp 'org-db-v3-stop-server)
    (org-db-v3-stop-server)))

;;; Auto-indexing on save

(defun ps/org-db--under-directory-p (file)
  "Return non-nil if FILE is inside `ps/org-db-directory'."
  (file-in-directory-p file (expand-file-name ps/org-db-directory)))

(defun ps/org-db-after-save-hook ()
  "Re-index the current buffer's file in the background after saving."
  (when (buffer-file-name)
    (org-db-v3-index-file-async (buffer-file-name))))

(defun ps/org-db-hook-function ()
  "Add `ps/org-db-after-save-hook' for org files under `ps/org-db-directory'."
  (when (and (buffer-file-name)
             (string-suffix-p ".org" (buffer-file-name))
             (ps/org-db--under-directory-p (buffer-file-name)))
    (add-hook 'after-save-hook #'ps/org-db-after-save-hook nil t)))

(defun ps/org-db-enable ()
  "Enable background indexing of `ps/org-db-directory' on save."
  (interactive)
  (add-hook 'org-mode-hook #'ps/org-db-hook-function)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (ps/org-db-hook-function)))))

(defun ps/org-db-disable ()
  "Disable background indexing on save."
  (interactive)
  (remove-hook 'org-mode-hook #'ps/org-db-hook-function)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (remove-hook 'after-save-hook #'ps/org-db-after-save-hook t))))

;;; Sync of changes made outside Emacs

(defun ps/org-db--parse-timestamp (string)
  "Parse SQLite UTC timestamp STRING (\"YYYY-MM-DD HH:MM:SS\") to epoch seconds."
  (let ((decoded (parse-time-string string)))
    (float-time (encode-time (append (butlast decoded) (list 0))))))

(defun ps/org-db--files-needing-sync (disk-files indexed-alist)
  "Return the subset of DISK-FILES whose on-disk content is newer than indexed.
DISK-FILES is a list of (FILENAME . MTIME) pairs, MTIME in epoch seconds.
INDEXED-ALIST maps FILENAME to its last-indexed time in epoch seconds. A file
needs syncing if it is missing from INDEXED-ALIST or its MTIME is newer.
Pure (no filesystem or network access)."
  (cl-loop for (file . mtime) in disk-files
           for indexed-at = (cdr (assoc file indexed-alist))
           when (or (null indexed-at) (> mtime indexed-at))
           collect file))

(defun ps/org-db--disk-files ()
  "Return (FILENAME . MTIME) for every .org file under `ps/org-db-directory'."
  (mapcar (lambda (file)
            (cons (expand-file-name file)
                  (float-time (file-attribute-modification-time (file-attributes file)))))
          (directory-files-recursively (expand-file-name ps/org-db-directory) "\\.org\\'")))

(defun ps/org-db--indexed-alist ()
  "Fetch filename -> last-indexed-time (epoch seconds) from the server.
Returns the symbol `error' (and messages) if the server is unreachable, so
callers can distinguish \"fetch failed\" from \"index is empty\"."
  (condition-case err
      (let ((response (plz 'get (concat (org-db-v3-server-url) "/api/files") :as #'json-read :timeout 10)))
        (mapcar (lambda (entry)
                  (cons (alist-get 'filename entry)
                        (ps/org-db--parse-timestamp (alist-get 'indexed_at entry))))
                (alist-get 'files response)))
    (error
     (message "org-db: could not fetch indexed file list: %S" err)
     'error)))

(defun ps/org-db-sync-directory (&optional silent)
  "Re-index any files under `ps/org-db-directory' changed since last indexed.
This is how edits made outside Emacs (or in another Emacs instance) get
picked up. Unless SILENT, messages a summary."
  (interactive)
  (ps/org-db-ensure-server)
  (let* ((indexed-alist (ps/org-db--indexed-alist))
         (to-sync (unless (eq indexed-alist 'error)
                    (ps/org-db--files-needing-sync (ps/org-db--disk-files) indexed-alist))))
    (cond
     (to-sync
      (dolist (file to-sync) (org-db-v3-index-file-async file))
      (unless silent (message "org-db: syncing %d changed file(s)" (length to-sync))))
     ((not silent)
      (message "org-db: notes index is up to date")))
    to-sync))

;;; Search

(defun ps/org-db--post (path body)
  "POST BODY (an alist) as JSON to PATH on the org-db-v3 server. Return parsed JSON."
  (plz 'post (concat (org-db-v3-server-url) path)
    :headers '(("Content-Type" . "application/json"))
    :body (json-encode body)
    :as #'json-read
    :timeout 30))

(defun ps/org-db-semantic-results (query &optional limit)
  "Return a list of result plists for QUERY from `/api/search/semantic'.
Each plist has :filename, :score (cosine similarity), :snippet, :begin-line."
  (let ((response (ps/org-db--post "/api/search/semantic"
                                    `((query . ,query) (limit . ,(or limit ps/org-db-search-limit))))))
    (mapcar (lambda (r)
              (list :filename (alist-get 'filename r)
                    :score (alist-get 'similarity_score r)
                    :snippet (alist-get 'chunk_text r)
                    :begin-line (alist-get 'begin_line r)))
            (alist-get 'results response))))

(defun ps/org-db-fulltext-results (query &optional limit)
  "Return a list of result plists for QUERY from `/api/search/fulltext'.
Each plist has :filename, :score (BM25 rank), :snippet, :begin-line (nil)."
  (let ((response (ps/org-db--post "/api/search/fulltext"
                                    `((query . ,query) (limit . ,(or limit ps/org-db-search-limit))))))
    (mapcar (lambda (r)
              (list :filename (alist-get 'filename r)
                    :score (alist-get 'rank r)
                    :snippet (alist-get 'snippet r)
                    :begin-line nil))
            (alist-get 'results response))))

(defun ps/org-db--rrf-merge (semantic-results fulltext-results &optional k)
  "Fuse SEMANTIC-RESULTS and FULLTEXT-RESULTS via Reciprocal Rank Fusion.
Each argument is a list of plists with at least :filename, ordered best-first
(their position is their rank). K defaults to `ps/org-db-rrf-k'.

Returns a list of plists, each `(:filename F :rrf-score S :result ITEM)',
where ITEM is the first-seen result plist for F (semantic results take
precedence), sorted by :rrf-score descending. Pure."
  (let ((k (or k ps/org-db-rrf-k))
        (scores (make-hash-table :test 'equal))
        (items (make-hash-table :test 'equal))
        (order nil))
    (dolist (results (list semantic-results fulltext-results))
      (let ((rank 0))
        (dolist (item results)
          (setq rank (1+ rank))
          (let ((file (plist-get item :filename)))
            (unless (gethash file scores)
              (push file order)
              (puthash file item items))
            (puthash file (+ (gethash file scores 0.0) (/ 1.0 (+ k rank))) scores)))))
    (sort (mapcar (lambda (file)
                     (list :filename file
                           :rrf-score (gethash file scores)
                           :result (gethash file items)))
                   (nreverse order))
          (lambda (a b) (> (plist-get a :rrf-score) (plist-get b :rrf-score))))))

(defun ps/org-db--format-candidate (item)
  "Return a one-line `completing-read' label for result plist ITEM."
  (let* ((file (plist-get item :filename))
         (root (file-name-as-directory (expand-file-name ps/org-db-directory)))
         (rel (file-relative-name file root))
         (snippet (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " (or (plist-get item :snippet) ""))))
         (snippet (if (> (length snippet) 80)
                      (concat (substring snippet 0 80) "…")
                    snippet)))
    (format "%s  —  %s" rel snippet)))

(defun ps/org-db--completing-read (prompt items)
  "Prompt with PROMPT over result plists ITEMS. Return the chosen plist, or nil."
  (if (null items)
      (progn (message "org-db: no results") nil)
    (let ((table (make-hash-table :test 'equal))
          candidates)
      (dolist (item items)
        (let ((label (ps/org-db--format-candidate item)))
          (push label candidates)
          (puthash label item table)))
      (gethash (completing-read prompt (nreverse candidates) nil t) table))))

(defun ps/org-db--visit-item (item)
  "Open the file for result plist ITEM, jumping to its :begin-line if set."
  (find-file (plist-get item :filename))
  (when (plist-get item :begin-line)
    (goto-char (point-min))
    (forward-line (1- (plist-get item :begin-line)))))

(defun ps/org-db-semantic-search (query)
  "Semantic search over org notes for QUERY, jumping to the chosen result."
  (interactive "sSemantic search: ")
  (ps/org-db-ensure-server)
  (ps/org-db-sync-directory t)
  (when-let* ((item (ps/org-db--completing-read "Semantic result: " (ps/org-db-semantic-results query))))
    (ps/org-db--visit-item item)))

(defun ps/org-db-fulltext-search (query)
  "Full-text (FTS5/BM25) search over org notes for QUERY."
  (interactive "sFull-text search: ")
  (ps/org-db-ensure-server)
  (ps/org-db-sync-directory t)
  (when-let* ((item (ps/org-db--completing-read "Full-text result: " (ps/org-db-fulltext-results query))))
    (ps/org-db--visit-item item)))

(defun ps/org-db-search (query)
  "Hybrid search: fuse semantic and full-text results for QUERY via RRF."
  (interactive "sSearch notes: ")
  (ps/org-db-ensure-server)
  (ps/org-db-sync-directory t)
  (let* ((fused (ps/org-db--rrf-merge (ps/org-db-semantic-results query)
                                       (ps/org-db-fulltext-results query)))
         (items (mapcar (lambda (f) (plist-get f :result)) fused)))
    (when-let* ((item (ps/org-db--completing-read "Result: " items)))
      (ps/org-db--visit-item item))))

(provide 'ps-org-db)
;;; ps-org-db.el ends here
