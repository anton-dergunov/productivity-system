# Stage 1 — Core Client: Context, Requests & the Preview-and-Apply Harness

> Goal: build the reusable `orgllm` core that every assistant uses — primitives to extract
> context from org (subtree, region, file, ancestor breadcrumb), a request wrapper that routes
> to the right model under the privacy gate, a prompt-template registry, and the
> **preview-and-apply safety harness** (model proposes → you review a diff → you apply). After
> this stage you can issue an arbitrary prompt against the current subtree and apply the result
> safely — the skeleton on which Stage 2's commands are thin wrappers.

**Question categories touched:** infrastructure for all (A–I).
**Depends on:** Stage [00](00-foundations.md).
**Effort:** ~1 weekend.

---

## 1.1 Why a core layer

Every assistant in this project is the same shape: *gather some context → render a prompt →
call a model → present the result for review → optionally apply a change.* Building that shape
once, well-tested, means each later command is ~15 lines. It also means the safety property
("never auto-write") and the privacy property ("Tier-L never leaves the machine") are enforced
in **one** place with tests, not re-implemented per command.

---

## 1.2 Deliverables

- [ ] `orgllm-context.el` — extraction primitives + tests.
- [ ] `orgllm-request.el` — model routing, privacy gate, sync/async gptel wrappers + tests.
- [ ] `orgllm-prompts.el` — a small prompt-template registry.
- [ ] `orgllm-preview.el` — proposal buffer + ediff apply harness + tests.

---

## 1.3 Reused libraries

| Need | Library |
|---|---|
| LLM requests | **gptel** (`gptel-request`, `gptel-rewrite`) |
| Org parsing | **org-element** (built-in) |
| Diff review | **ediff** (built-in) / `diff-mode` |
| Async/queue (optional) | gptel's own callback model; `aio` if you want promises |

---

## 1.4 Context extraction (`orgllm-context.el`)

The org-aware context primitives. These are reused by *everything* (and again, in richer form,
by the Stage 6 chunker).

```elisp
(defun orgllm-context-region ()
  "Return the active region text or nil."
  (when (use-region-p)
    (buffer-substring-no-properties (region-beginning) (region-end))))

(defun orgllm-context-subtree (&optional with-breadcrumb)
  "Return current org subtree as text.
With WITH-BREADCRUMB, prepend the ancestor heading path."
  (save-excursion
    (org-back-to-heading t)
    (let* ((el (org-element-at-point))
           (body (buffer-substring-no-properties
                  (org-element-property :begin el)
                  (org-element-property :end el)))
           (crumb (when with-breadcrumb (orgllm-context--breadcrumb))))
      (if crumb (concat crumb "\n\n" body) body))))

(defun orgllm-context--breadcrumb ()
  "Return ancestor heading path like \"Plans > Health > Back\"."
  (org-with-wide-buffer
   (let (path)
     (while (org-up-heading-safe)
       (push (org-get-heading t t t t) path))
     (when path (mapconcat #'identity path " > ")))))

(defun orgllm-context-metadata ()
  "Return alist of (todo tags scheduled deadline priority id file) for current node."
  (let ((el (org-element-at-point)))
    (list (cons 'todo  (org-element-property :todo-keyword el))
          (cons 'tags  (org-get-tags))
          (cons 'sched (org-element-property :scheduled el))
          (cons 'deadline (org-element-property :deadline el))
          (cons 'priority (org-element-property :priority el))
          (cons 'id    (org-id-get))
          (cons 'file  (buffer-file-name)))))

(defun orgllm-context-file () (buffer-string))
```

**Tests** (buttercup), against `test/fixtures/`:
- breadcrumb on a depth-3 node returns the exact `A > B > C` path;
- subtree extraction includes child subtrees and the `:LOGBOOK:`/`:PROPERTIES:` drawers verbatim;
- metadata returns the right TODO keyword and tags on a tagged fixture node;
- region extraction returns nil with no active region.

---

## 1.5 Request wrapper (`orgllm-request.el`)

One entry point that all assistants call. It (1) computes the privacy tier, (2) picks the model,
(3) renders the prompt, (4) calls gptel, (5) returns the text to a callback. This is where the
**hard privacy gate** lives.

```elisp
(cl-defun orgllm-request (prompt &key context system model callback (tier 'auto) file tags)
  "Send PROMPT (+ optional CONTEXT) to a model and call CALLBACK with the text.
TIER `auto computes local/cloud from FILE/TAGS via `orgllm--tier'."
  (let* ((tier (if (eq tier 'auto) (orgllm--tier file tags) tier))
         (backend (if (eq tier 'local) "Ollama" "Claude"))
         (model (or model (if (eq tier 'local) 'qwen2.5:32b 'claude-opus-4-8)))
         (full (if context (format "%s\n\n<context>\n%s\n</context>" prompt context) prompt)))
    (when (and (eq tier 'cloud) (orgllm--looks-private-p full))
      (user-error "Refusing to send apparently-private content to cloud"))
    (gptel-request full
      :system system
      :callback (lambda (resp info)
                  (if (stringp resp) (funcall callback resp)
                    (user-error "orgllm: request failed: %S" info)))
      :backend (gptel-get-backend backend)
      :model model)))
```

Design notes:
- **Privacy is fail-closed:** a Tier-L file/tag forces local; an extra `orgllm--looks-private-p`
  heuristic (regex for your name/emails/phone) is a belt-and-suspenders check on cloud calls.
  Both are unit-tested with adversarial fixtures.
- **Model routing** is centralized: default `claude-opus-4-8`; callers may pass
  `:model 'claude-haiku-4-5` for cheap high-volume tasks (Stage 5 triage).
- **Streaming vs sync:** gptel streams by default; for "fill a proposal buffer" we collect the
  final text. For long outputs prefer streaming into the buffer so you see progress.

---

## 1.6 Prompt templates (`orgllm-prompts.el`)

A tiny registry so prompts are versioned, testable, and reusable across stages (and later,
A/B-tested in Stage 9).

```elisp
(defvar orgllm-prompts (make-hash-table :test 'equal))

(defun orgllm-prompt-register (key system &optional user-template)
  (puthash key (list :system system :user user-template) orgllm-prompts))

(defun orgllm-prompt (key &rest args)
  "Return (SYSTEM . USER) for KEY, formatting USER template with ARGS."
  (let ((p (gethash key orgllm-prompts)))
    (cons (plist-get p :system)
          (when (plist-get p :user) (apply #'format (plist-get p :user) args)))))
```

Keep prompts in data, not scattered string literals — Stage 9 regression-tests them.

---

## 1.7 Preview-and-apply harness (`orgllm-preview.el`)

The keystone safety component. The model's proposed replacement is **never** written directly.
Instead:

```elisp
(defun orgllm-preview-replace (beg end new-text &optional title)
  "Show NEW-TEXT as a proposed replacement for BEG..END via ediff; apply on accept."
  (let ((orig (current-buffer))
        (proposal (generate-new-buffer (or title "*orgllm proposal*"))))
    (with-current-buffer proposal
      (insert (buffer-substring orig beg end)) ; start from original
      (erase-buffer) (insert new-text) (org-mode))
    ;; ediff the proposal against a temp copy of the original region; on quit,
    ;; if accepted, replace BEG..END in ORIG with the (possibly hand-edited) proposal.
    (orgllm-preview--ediff-region orig beg end proposal)))
```

Two UX modes (offer both; let the user pick a default):
1. **ediff hunk review** — best for edits to an existing subtree (rewrite, restructure). You can
   even hand-edit the proposal before accepting.
2. **Side proposal buffer** — best for *additive* output (a digest, a list of suggestions, a new
   note) where there is nothing to diff against; you read it and choose to insert/append.

Invariants enforced here (tested):
- applying a proposal that drops a `:PROPERTIES:`/`:ID:` line is **blocked** with a warning
  (regex check before write) — protects your node IDs and links;
- applying never touches a `:LOGBOOK:` drawer unless explicitly part of the selection;
- nothing is written if the user quits ediff without accepting.

> This single harness is what makes "support all 9 categories" safe. Every mutating command in
> Stages 2/3/5/7 routes its output through `orgllm-preview-replace` (edits) or the proposal
> buffer (additions).

---

## 1.8 Optional / alternative implementations (research branch)

- **gptel-rewrite reuse vs custom harness.** gptel ships `gptel-rewrite` with a `dispatch`
  action and ediff review. You can build category B directly on it. Building your own
  `orgllm-preview` is worth it because you need org-invariant checks (ID/LOGBOOK protection)
  that generic rewrite doesn't do — but prototype with `gptel-rewrite` first to validate UX.
- **Structured output.** For commands that should return machine-usable structure (e.g. a list of
  suggested tags, a refile target with confidence), use the model's JSON/structured-output mode
  and parse with `json-parse-string`, rather than scraping prose. Add a thin
  `orgllm-request-json` variant. (Used heavily in Stages 3/5.)
- **Async queue.** If you batch many small calls (Stage 5 triage over an inbox), wrap gptel
  callbacks with a small concurrency limiter; `aio` gives you promise-style code if preferred.

---

## 1.9 Python? — No.

Nothing here benefits from Python. gptel + org-element + ediff cover it cleanly and keep the
stack uniform.

---

## 1.10 Evaluation for this stage

- **Context primitives:** buttercup specs on fixtures (breadcrumb, subtree boundaries, metadata).
- **Privacy gate:** adversarial tests — a Tier-L file and a `:private:` node both refuse cloud;
  a redaction-trip string triggers `orgllm--looks-private-p`.
- **Harness safety:** a test that a proposal stripping an `:ID:` line is rejected; a test that a
  cancelled ediff writes nothing.
- **Golden request shape:** with a *stubbed* gptel backend (return a canned string), assert the
  rendered prompt contains the breadcrumb + context wrapper. (Stub once; reused by Stage 2 tests.)

---

## 1.11 Definition of Done

- [ ] Context, request, prompts, preview modules compile/lint/test clean.
- [ ] `orgllm-request` routes Tier-L→Ollama, Tier-C→Claude, with tests.
- [ ] `orgllm-preview-replace` round-trips a fixture edit through ediff and protects IDs/LOGBOOK.
- [ ] A throwaway command (`orgllm-ask-subtree`) proves end-to-end: prompt against current
      subtree, review, apply.

---

## 1.12 Risks / notes

- gptel's API surface evolves; pin a known version in `Eask` and wrap it behind `orgllm-request`
  so upgrades touch one file.
- Keep the privacy gate **fail-closed**: if tier can't be determined, treat as local.
