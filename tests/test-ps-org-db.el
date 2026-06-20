;;; test-ps-org-db.el --- ERT tests for ps-org-db -*- lexical-binding: t; -*-

(require 'ert)
(add-to-list 'load-path "lisp")
(require 'ps-org-db)

;;; RRF fusion

(ert-deftest ps/org-db-test-rrf-merge-prefers-double-ranked ()
  "An item ranked in both lists outranks one ranked in only one list."
  (let* ((semantic (list (list :filename "a" :score 0.9 :snippet "a-sem")
                          (list :filename "b" :score 0.5 :snippet "b-sem")))
         (fulltext (list (list :filename "b" :score -1.0 :snippet "b-fts")
                          (list :filename "c" :score -0.5 :snippet "c-fts")))
         (fused (ps/org-db--rrf-merge semantic fulltext)))
    (should (equal (mapcar (lambda (f) (plist-get f :filename)) fused)
                    '("b" "a" "c")))))

(ert-deftest ps/org-db-test-rrf-merge-keeps-semantic-item-on-overlap ()
  "When a file appears in both lists, the semantic result is kept for display."
  (let* ((semantic (list (list :filename "a" :score 0.9 :snippet "a-sem")))
         (fulltext (list (list :filename "a" :score -1.0 :snippet "a-fts")))
         (fused (ps/org-db--rrf-merge semantic fulltext)))
    (should (equal (plist-get (plist-get (car fused) :result) :snippet) "a-sem"))))

(ert-deftest ps/org-db-test-rrf-merge-empty-lists ()
  "Fusing two empty lists yields no results."
  (should (null (ps/org-db--rrf-merge nil nil))))

(ert-deftest ps/org-db-test-rrf-merge-score-formula ()
  "The fused score for a single-list item is 1/(k+rank)."
  (let* ((semantic (list (list :filename "a" :score 0.9)))
         (fused (ps/org-db--rrf-merge semantic nil 60)))
    (should (= (plist-get (car fused) :rrf-score) (/ 1.0 61)))))

;;; External-change sync

(ert-deftest ps/org-db-test-files-needing-sync-new-file ()
  "A file absent from the index needs syncing."
  (should (equal (ps/org-db--files-needing-sync '(("/notes/a.org" . 100)) nil)
                  '("/notes/a.org"))))

(ert-deftest ps/org-db-test-files-needing-sync-changed-file ()
  "A file whose mtime is newer than its indexed time needs syncing."
  (should (equal (ps/org-db--files-needing-sync
                  '(("/notes/a.org" . 200))
                  '(("/notes/a.org" . 100)))
                  '("/notes/a.org"))))

(ert-deftest ps/org-db-test-files-needing-sync-unchanged-file ()
  "A file indexed after its current mtime does not need syncing."
  (should (null (ps/org-db--files-needing-sync
                 '(("/notes/a.org" . 100))
                 '(("/notes/a.org" . 200))))))

(ert-deftest ps/org-db-test-files-needing-sync-mixed ()
  "Only the changed/new files are returned, in input order."
  (should (equal (ps/org-db--files-needing-sync
                  '(("/notes/a.org" . 100) ("/notes/b.org" . 300) ("/notes/c.org" . 50))
                  '(("/notes/a.org" . 200) ("/notes/b.org" . 100)))
                  '("/notes/b.org" "/notes/c.org"))))

;;; Timestamp parsing

(ert-deftest ps/org-db-test-parse-timestamp ()
  "SQLite UTC timestamps parse to the expected epoch seconds."
  (should (= (ps/org-db--parse-timestamp "1970-01-01 00:00:00") 0.0)))

;;; Candidate formatting

(ert-deftest ps/org-db-test-format-candidate-collapses-whitespace ()
  "Multi-line snippets are collapsed to a single line for display."
  (let ((ps/org-db-directory "/notes/")
        (item (list :filename "/notes/a.org" :snippet "line one\nline two")))
    (should (equal (ps/org-db--format-candidate item) "a.org  —  line one line two"))))

(ert-deftest ps/org-db-test-format-candidate-truncates-long-snippet ()
  "Long snippets are truncated with an ellipsis."
  (let ((ps/org-db-directory "/notes/")
        (item (list :filename "/notes/a.org" :snippet (make-string 200 ?x))))
    (should (<= (length (ps/org-db--format-candidate item)) 100))))
