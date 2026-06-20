;;; test-ps-gptel.el --- ERT tests for ps-gptel -*- lexical-binding: t; -*-

(require 'ert)
(add-to-list 'load-path "lisp")
(require 'ps-gptel)

;;; Credential parsing

(defconst ps/gptel-test--sample-json
  "{\"claudeAiOauth\":{\"accessToken\":\"sk-ant-oat01-abc\",\"refreshToken\":\"rt\",\"expiresAt\":1781193224051,\"scopes\":[\"user:inference\"]},\"organizationUuid\":\"x\"}"
  "Sample Keychain JSON matching the real Claude Code credential shape.")

(ert-deftest ps/gptel-test-parse-credentials ()
  "Parsing extracts the access token and converts expiry ms -> seconds."
  (let ((creds (ps/gptel--parse-credentials ps/gptel-test--sample-json)))
    (should (equal (plist-get creds :token) "sk-ant-oat01-abc"))
    (should (= (plist-get creds :expiry) (/ 1781193224051 1000.0)))))

(ert-deftest ps/gptel-test-parse-credentials-flat ()
  "Parsing also accepts a credential object without the claudeAiOauth wrapper."
  (let ((creds (ps/gptel--parse-credentials
                "{\"accessToken\":\"sk-ant-oat01-z\",\"expiresAt\":2000}")))
    (should (equal (plist-get creds :token) "sk-ant-oat01-z"))
    (should (= (plist-get creds :expiry) 2.0))))

(ert-deftest ps/gptel-test-parse-credentials-missing-token ()
  "Parsing errors clearly when no access token is present."
  (should-error (ps/gptel--parse-credentials "{\"claudeAiOauth\":{}}")))

;;; Expiry logic

(ert-deftest ps/gptel-test-token-valid-p ()
  "A future expiry (past the skew) is valid; a past one is not."
  (should (ps/gptel--token-valid-p (+ (float-time) 3600)))
  (should-not (ps/gptel--token-valid-p (- (float-time) 10)))
  (should-not (ps/gptel--token-valid-p (+ (float-time) 1))))

(ert-deftest ps/gptel-test-oauth-token-expired ()
  "An expired cached token triggers the actionable refresh error.
Stub `ps/gptel--read-credentials' so no Keychain/subprocess is touched."
  (let ((ps/gptel--token nil)
        (ps/gptel--token-expiry 0))
    (cl-letf (((symbol-function 'ps/gptel--read-credentials)
               (lambda () (list :token "stale" :expiry (- (float-time) 100)))))
      (should-error (ps/gptel--oauth-token) :type 'user-error))))

;;; Identity injection

(defun ps/gptel-test--first-text (data)
  "Return the :text of the first :system block in request plist DATA."
  (let ((sys (plist-get data :system)))
    (plist-get (aref sys 0) :text)))

(ert-deftest ps/gptel-test-inject-into-nil ()
  "With no system prompt, the identity becomes the sole system block."
  (let ((data (ps/gptel--inject-identity (list :model "m"))))
    (should (equal (ps/gptel-test--first-text data)
                   ps/gptel-claude-code-identity))
    (should (= (length (plist-get data :system)) 1))))

(ert-deftest ps/gptel-test-inject-before-string ()
  "A string system prompt is preserved as a block after the identity."
  (let ((data (ps/gptel--inject-identity (list :system "Be terse."))))
    (should (equal (ps/gptel-test--first-text data)
                   ps/gptel-claude-code-identity))
    (should (= (length (plist-get data :system)) 2))
    (should (equal (plist-get (aref (plist-get data :system) 1) :text)
                   "Be terse."))))

(ert-deftest ps/gptel-test-inject-before-vector ()
  "An existing vector of blocks is preserved after the identity."
  (let* ((blocks (vector (list :type "text" :text "A")
                         (list :type "text" :text "B")))
         (data (ps/gptel--inject-identity (list :system blocks))))
    (should (equal (ps/gptel-test--first-text data)
                   ps/gptel-claude-code-identity))
    (should (= (length (plist-get data :system)) 3))
    (should (equal (plist-get (aref (plist-get data :system) 2) :text) "B"))))

(ert-deftest ps/gptel-test-inject-no-duplicate ()
  "Re-injecting does not stack a second identity block."
  (let* ((once (ps/gptel--inject-identity (list :system "Hi")))
         (twice (ps/gptel--inject-identity once)))
    (should (equal (ps/gptel-test--first-text twice)
                   ps/gptel-claude-code-identity))
    (should (= (length (plist-get twice :system)) 2))))

;;; Notes path scoping

(ert-deftest ps/gptel-test-notes-resolve-path-within-root ()
  "A relative path inside the notes root resolves to its absolute path."
  (let ((root "/notes/"))
    (should (equal (ps/gptel--notes-resolve-path root "Areas/work.org")
                    "/notes/Areas/work.org"))
    (should (equal (ps/gptel--notes-resolve-path root ".") "/notes"))
    (should (equal (ps/gptel--notes-resolve-path root nil) "/notes"))))

(ert-deftest ps/gptel-test-notes-resolve-path-escape-rejected ()
  "Paths that escape the notes root via `..' or absolute paths are rejected."
  (let ((root "/notes/"))
    (should-error (ps/gptel--notes-resolve-path root "../etc/passwd")
                   :type 'user-error)
    (should-error (ps/gptel--notes-resolve-path root "/etc/passwd")
                   :type 'user-error)
    (should-error (ps/gptel--notes-resolve-path root "Areas/../../etc/passwd")
                   :type 'user-error)))

;;; Tool registration

(ert-deftest ps/gptel-test-register-tool-replaces-by-name ()
  "Re-registering a tool with the same name replaces the old one."
  (skip-unless (locate-library "gptel"))
  (require 'gptel)
  (let ((gptel-tools nil))
    (ps/gptel--register-tool (gptel-make-tool
                               :name "search_notes" :function #'ignore
                               :description "v1" :args nil :category "notes"))
    (ps/gptel--register-tool (gptel-make-tool
                               :name "search_notes" :function #'ignore
                               :description "v2" :args nil :category "notes"))
    (should (= (length gptel-tools) 1))
    (should (equal (gptel-tool-description (car gptel-tools)) "v2"))))

(provide 'test-ps-gptel)
;;; test-ps-gptel.el ends here
