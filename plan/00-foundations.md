# Stage 0 — Foundations, Environment & Baseline (non-AI)

> Goal: stand up the project skeleton, the development/test workflow, the privacy and model
> configuration, a deterministic fixture corpus, the conventions document (`AGENTS.md`), and a
> zero-AI baseline search layer. After this stage you have a tested, lintable elisp package and
> instant keyword/structured search — before a single LLM call.

**Question categories touched:** E (partial — exact/structured search baseline).
**Depends on:** nothing.
**Effort:** ~1 weekend.

---

## 0.1 Why start here

Two reasons. First, the boring infrastructure (tests, fixtures, linting) is what lets every
later stage be *evaluated* rather than vibed — which is the whole point of doing this as an ML
engineer. Second, a large share of "search my plans" is solved with no AI at all by ripgrep +
org-ql; building that first means the LLM stages only need to cover what keyword search *can't*
do, which keeps them small and sharp.

---

## 0.2 Deliverables

- [ ] An installable elisp package skeleton (`orgllm`) with a customization group and autoloads.
- [ ] A build/test/lint workflow (Eask + ERT/buttercup + checkdoc + byte-compile).
- [ ] A **fixture corpus** under `test/fixtures/` (anonymized real subset + synthetic trees).
- [ ] Model + privacy configuration (Claude API backend, Ollama backend, Tier L/Tier C routing table).
- [ ] `AGENTS.md` + `CLAUDE.md` stub describing your file layout, TODO state machine, tags, hard rules.
- [ ] Baseline search bindings: `consult-ripgrep` over the plans folder, `org-ql` saved views.

---

## 0.3 Reused libraries

| Need | Library |
|---|---|
| Package build/test/lint | **Eask** (modern; `eask init`, `eask test ert`, `eask lint`) |
| Unit tests | **ERT** (built-in) and/or **buttercup** (BDD-style, readable) |
| Doc/lint | `checkdoc`, `package-lint`, byte-compile warnings |
| Keyword search | **ripgrep** + **consult** (`consult-ripgrep`) |
| Structured org search | **org-ql** (+ `consult` integration) |
| HTTP (later stages, install now) | **plz.el** |

---

## 0.4 Build & test workflow

Use **Eask** as the package/test driver so the project is reproducible and CI-able.

```
# one-time
eask init           # creates Eask file
eask install-deps
# loop
eask compile        # byte-compile, treat warnings as errors later
eask lint checkdoc
eask lint package   # package-lint
eask test ert       # or: eask test buttercup
```

**Testing convention:** one test file per source file (`orgllm-context.el` ↔
`test/orgllm-context-test.el`). Prefer **buttercup** for behavior-heavy modules (readable
`describe`/`it`) and **ERT** for small pure functions. Tests must run headless
(`emacs -batch`) so they can go in CI.

Minimal ERT smoke test to prove the toolchain:

```elisp
;; test/orgllm-smoke-test.el
(require 'ert)
(require 'orgllm)
(ert-deftest orgllm-smoke ()
  (should (fboundp 'orgllm-version)))
```

**Optional CI:** a GitHub Actions matrix (Emacs 29/30) running `eask compile && eask lint &&
eask test ert`. Worth it once the package has a few modules; skip on day one.

---

## 0.5 Package skeleton

```elisp
;;; orgllm.el --- LLM assistance for org-mode planning -*- lexical-binding: t; -*-
;; Package-Requires: ((emacs "29.1") (gptel "0.9") (org-ql "0.8") (plz "0.9"))

(defgroup orgllm nil
  "LLM assistance for org-mode planning."
  :group 'org :prefix "orgllm-")

(defcustom orgllm-plans-directory "~/org/plans/"
  "Root directory of org planning files."
  :type 'directory)

(defun orgllm-version () "0.0.1")

(provide 'orgllm)
```

Emacs **29.1+** is assumed because it ships built-in `sqlite` (needed for the vector store in
Stage 6) and `treesit`/modern niceties. Confirm with `(sqlite-available-p)`.

---

## 0.6 The fixture corpus (data-science foundation)

You need a corpus that is (a) realistic, (b) safe to commit, (c) deterministic for tests. Build
three tiers:

1. **Anonymized real subset.** Take ~5 representative files (e.g. a structured task file like
   `Projects.org`, a personal-life file like `Health.org`, a dump like a slice of `Inbox.org`).
   Run them through a one-shot anonymizer (a small elisp/LLM pass that replaces names, URLs,
   personal specifics with neutral tokens). Commit the *anonymized* output only.
2. **Hand-crafted edge cases.** Small org files exercising tricky structure: deep nesting,
   `:PROPERTIES:`/`:ID:` drawers, `:LOGBOOK:`, repeaters (`+1w`), `DEADLINE`/`SCHEDULED`,
   mixed RU/EN, `:book:`/`:video:` tags, malformed headings.
3. **Synthetic generated trees** (preview of Stage 9). A generator that fabricates org subtrees
   with *known, labeled defects*: missing next-action, near-duplicate of another node,
   mis-tagged, stale (old timestamp), "reference masquerading as TODO." These labels become
   ground truth for detector evaluation later.

Directory:

```
test/fixtures/
  real-anon/Projects.org  Health.org  Inbox-slice.org
  edge/drawers.org  repeaters.org  bilingual.org  malformed.org
  synth/  (generated; see eval/ in Stage 9)
  labels/ defects.jsonl   ; {file,node-id,defect-type} ground truth
```

> DS note: keep a `labels/` manifest from the very start. The discipline of "every fixture has
> machine-readable ground truth" is what makes Stages 5/6/9 measurable instead of anecdotal.

---

## 0.7 Model & privacy configuration

Configure two backends in gptel and a routing predicate.

```elisp
;; Cloud (commercial terms via API key)
(require 'gptel)
(setq gptel-model 'claude-opus-4-8)
(gptel-make-anthropic "Claude" :stream t :key #'gptel-api-key-from-auth-source)

;; Local (Ollama)
(gptel-make-ollama "Ollama"
  :host "localhost:11434"
  :models '(qwen2.5:32b llama3.3:latest))

;; Privacy routing
(defcustom orgllm-private-file-regexp
  (rx (or "Health" "Financial" "Relationship") (* nonl) ".org" eos)
  "Files whose contents must never leave the machine." :type 'regexp)

(defcustom orgllm-private-tag "private"
  "Org tag marking a subtree as local-only." :type 'string)

(defun orgllm--tier (file tags)
  "Return `local or `cloud for FILE and TAGS."
  (if (or (and file (string-match-p orgllm-private-file-regexp file))
          (member orgllm-private-tag tags))
      'local 'cloud))
```

This predicate is consumed by the request wrapper in Stage [01](01-core-client.md); add a unit
test now (`Health.org` ⇒ `local`, `:private:` tag ⇒ `local`, `Projects.org` ⇒ `cloud`). Model
default is `claude-opus-4-8`; you'll route triage-style high-volume calls to `claude-haiku-4-5`
in later stages for cost.

> Anthropic has **no embeddings endpoint** — all embeddings (Stage 6) are local via Ollama, or a
> third-party (Voyage/Cohere/Jina) if you ever want hosted. This is also a privacy win.

---

## 0.8 The conventions document (`AGENTS.md` + `CLAUDE.md`)

This is the single most leveraged non-code artifact: it teaches *any* agent (gptel tool-use,
Claude Code, Codex) your structure and invariants. Keep it tight (< ~150 lines — instruction
budgets are real; bloated rule files degrade *all* instructions uniformly).

`AGENTS.md` should contain:

1. **File map** — what each org file is for (commitments vs reference dumps; which are Tier L).
2. **TODO state machine** — your exact `org-todo-keywords` (`TODO | NEXT | IN-PROGRESS | DONE`)
   and what each means.
3. **Tag conventions** — `:book:`, `:video:`, `:plan:`, `:private:`, etc.
4. **Hard rules** — *NEVER* rewrite a heading carrying `:ID:`; *NEVER* delete `:LOGBOOK:`;
   *ALWAYS* show a diff before writing; preserve RU/EN as-is unless asked to translate.
5. **Reading order** — when asked about an area, read that file, then `Inbox`/`Unsorted`.
6. **Privacy** — never send Tier-L files to a cloud model.

`AGENTS.md` is the tool-agnostic standard (OpenAI/Google/Cursor/… , Linux-Foundation-stewarded).
**Claude Code does not auto-load `AGENTS.md`**, so add a one-line `CLAUDE.md`:

```
@AGENTS.md
```

(`@`-import pulls the contents in; prefer this over a symlink, which gets awkward under Dropbox.)

---

## 0.9 Baseline search (zero AI)

Wire up the non-AI retrieval that the LLM stages will *not* need to reinvent:

```elisp
;; Keyword search across plans
(defun orgllm-grep ()
  "ripgrep across the plans directory."
  (interactive)
  (consult-ripgrep orgllm-plans-directory))

;; Structured search examples (org-ql)
;;  - all :book: items:           (org-ql-search files '(tags "book"))
;;  - all deadlines next 14 days: (org-ql-search files '(deadline :to 14))
;;  - priority A across files:    (org-ql-search files '(priority "A"))
```

Bind `orgllm-grep` to e.g. `C-c l g`. Add a couple of saved `org-ql` views (e.g.
`my/agenda-books`, `my/agenda-stale`). This alone covers category E's exact/structured half.

---

## 0.10 Evaluation for this stage

- **Toolchain check:** `eask compile && eask lint && eask test ert` is green headless.
- **Privacy predicate:** unit tests pin Tier-L/Tier-C routing for the fixture files.
- **Search sanity:** a small ERT test that `org-ql` returns the expected node count for a fixture
  query (e.g. "fixture has exactly 3 `:book:` items").
- **Fixture integrity:** a test asserting every node referenced in `labels/defects.jsonl` exists
  in the fixtures (guards against drift).

---

## 0.11 Definition of Done

- [ ] `orgllm` byte-compiles clean, lints clean, smoke test passes headless.
- [ ] Eask + test layout in place; one buttercup and one ERT example run.
- [ ] Fixture corpus committed with a `labels/` ground-truth manifest.
- [ ] gptel configured with Claude + Ollama; `orgllm--tier` predicate tested.
- [ ] `AGENTS.md` written; `CLAUDE.md` = `@AGENTS.md`.
- [ ] `orgllm-grep` + 2 org-ql views bound and working.

---

## 0.12 Risks / notes

- **Dropbox + concurrent writes:** only ever run write-enabled tooling on one machine; save +
  sync before invoking agents (avoids `(Conflicted Copy)` files). Re-stated in Stage 7/8.
- **Don't over-invest in CI now** — a green local `eask test` is enough until you have ≥3 modules.
- Keep `AGENTS.md` short from day one; resist the urge to enumerate every tag.
