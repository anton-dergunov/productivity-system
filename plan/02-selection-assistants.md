# Stage 2 — Selection-Scoped Assistants (Rewrite, Review, Enrich)

> Goal: deliver the first three user-facing assistant families — all operating on the current
> selection or subtree, all routed through the Stage 1 harness. These are the cheapest, safest,
> highest-frequency wins, and reaching here is your **MVP milestone**: you can rewrite, review,
> and enrich any subtree with full review control.

**Question categories:** **B** (rewrite/polish), **A** (review/critique), **G** (enrich/metadata).
**Depends on:** Stage [01](01-core-client.md).
**Effort:** ~1–2 weeks.

---

## 2.1 Why these first

They are selection-scoped (context is tiny → fast, cheap, private-friendly), they have an obvious
review surface (you're looking right at the subtree), and they cover the operations you'll invoke
many times a day. Each command is a thin wrapper over `orgllm-request` + `orgllm-preview`.

---

## 2.2 Category B — Rewrite / polish (`orgllm-rewrite.el`)

User-facing commands (each operates on region, or subtree if no region):

| Command | What it does |
|---|---|
| `orgllm-rewrite-clarify` | tighten wording, fix grammar, keep meaning |
| `orgllm-rewrite-actionable` | turn a noun-phrase note into a verb-first `TODO` |
| `orgllm-translate` | RU↔EN (auto-detect source; you choose target) |
| `orgllm-summarize-pasted` | compress a pasted article/abstract → 2-line note + the 1 actionable |
| `orgllm-rewrite-region` | freeform: prompt + region |

Skeleton:

```elisp
(defun orgllm-rewrite-actionable ()
  "Rewrite the region/subtree as a clear, verb-first actionable TODO."
  (interactive)
  (let* ((beg (if (use-region-p) (region-beginning) (org-entry-beginning-position)))
         (end (if (use-region-p) (region-end) (org-entry-end-position)))
         (text (buffer-substring-no-properties beg end))
         (md (orgllm-context-metadata)))
    (pcase-let ((`(,sys . ,_) (orgllm-prompt 'rewrite-actionable)))
      (orgllm-request text :system sys
        :file (alist-get 'file md) :tags (alist-get 'tags md)
        :callback (lambda (out) (orgllm-preview-replace beg end out "*rewrite*"))))))
```

Prompt design notes:
- **Preserve org structure**: system prompt instructs "return valid org, keep heading level,
  keep `:PROPERTIES:`/`:ID:`/`:LOGBOOK:` untouched, keep TODO keyword unless asked."
- **Language fidelity**: do not silently translate; RU stays RU unless `orgllm-translate`.
- **Few-shot**: include 2–3 examples (vague → actionable) drawn from your real anonymized data;
  store them in the prompt template so Stage 9 can A/B them.

---

## 2.3 Category A — Review / critique a subtree (`orgllm-review.el`)

Operates on the current subtree (+ breadcrumb). Output is *additive* (suggestions), so it goes to
a **proposal buffer**, not ediff — you read and selectively act.

| Command | What it does |
|---|---|
| `orgllm-review-completeness` | "what's missing here? what would block this?" |
| `orgllm-review-suggest-subtasks` | propose concrete child TODOs for a vague item |
| `orgllm-review-angles` | review from N angles: prereqs, dependencies, cost, time, risk |
| `orgllm-review-done-p` | "does this look complete / archivable?" + rationale |
| `orgllm-review-stale` | flag items referencing obsolete tech/old dates |

The output format matters: ask for an **org subtree of suggestions** (so you can refile accepted
items directly), each suggestion tagged with a one-word rationale and a confidence. Example
desired output:

```org
* Suggested next actions (review)
** TODO Book a dermatologist appointment   :suggested:
   confidence: high — subtree lists symptoms but no booking action
** TODO Define the 3-week posture routine   :suggested:
   confidence: med — "create plan" has no concrete steps
```

You then refile accepted items into the real subtree (Stage 3 gives a one-key refile tool).

---

## 2.4 Category G — Enrichment / metadata (`orgllm-enrich.el`)

Small, high-frequency metadata helpers. These pair naturally with the Stage 3 tool layer (which
actually *applies* state/tag/schedule changes correctly), but the *suggestion* lives here.

| Command | What it does |
|---|---|
| `orgllm-enrich-tags` | suggest tags from your existing tag vocabulary (don't invent new ones) |
| `orgllm-enrich-deadline` | propose `SCHEDULED`/`DEADLINE` from context |
| `orgllm-enrich-priority` | suggest `[#A/B/C]` with rationale |
| `orgllm-annotate-link` | add a one-line "what is this" under a bare URL |
| `orgllm-enrich-summary` | add a 1-line summary property to a long node |

Key design choice for `orgllm-enrich-tags`: pass the **existing tag set** (from
`org-global-tags`/`org-get-buffer-tags`) into the prompt and constrain the model to choose from
it (+ at most one new suggestion, clearly marked). This keeps your taxonomy clean — a recurring
need given tags scattered across files. Use **structured output** (JSON list of tags) and parse,
rather than scraping prose.

```elisp
(defun orgllm-enrich-tags ()
  "Suggest tags for the current node from the existing vocabulary."
  (interactive)
  (let ((vocab (orgllm--all-tags))
        (text (orgllm-context-subtree t)))
    (orgllm-request-json
     (format "Choose 1-4 tags for this node from VOCAB. You may propose at most one NEW tag, prefixed '+'.\nVOCAB: %s" vocab)
     :context text
     :schema '(:type array :items (:type string))
     :callback (lambda (tags) (orgllm--offer-tags tags)))))
```

---

## 2.5 Optional / alternative implementations (research)

- **Inline `#+begin_ai` blocks** (via `org-ai`) for conversational review embedded in a plan
  document — nice when you want the critique to live next to the plan. Offer as an alternate face.
- **Two-pass review** (research): pass 1 generates findings with a strong model; pass 2 (a
  cheaper model or a rubric prompt) filters/ranks them. Measure whether the second pass improves
  precision without killing recall (Stage 9 metrics). Mirrors the "report-everything-then-filter"
  pattern that improves recall measurement.
- **Self-consistency for stale/done detection**: sample the judgment 3× and majority-vote; compare
  accuracy vs single-shot on your labeled `stale`/`done` fixtures.

---

## 2.6 Python? — No.

All selection-scoped; pure elisp + gptel. Keep it uniform.

---

## 2.7 Evaluation for this stage (the DS part)

This is where generative-quality evaluation begins. Build a small labeled set under
`eval/datasets/`:

- **Rewrite (B):** 20–30 (input subtree → reference improved subtree) pairs from your anonymized
  data. Metric: **LLM-as-judge** rubric (clarity, actionability, structure preserved, language
  fidelity) on a 1–5 scale, plus a hard check that org structure/IDs survive (programmatic).
- **Review (A):** 15–20 subtrees with hand-labeled "missing next action / over-scoped / stale"
  flags (reuse the synthetic-defect fixtures from Stage 0). Metric: precision/recall of the
  detector against those labels.
- **Enrich (G):** 20 nodes with reference tags. Metric: tag **precision/recall vs vocabulary**,
  and a penalty for inventing tags already present under a synonym.

Harness: `eval/run-eval.el` loads a dataset, runs the command with a stubbed-or-real backend,
scores against labels/rubric, writes results to an sqlite log (Stage 9). Run it whenever you tweak
a prompt to catch regressions.

> Synthetic-data angle: generate 100 vague task strings with a strong model, each paired with its
> "ideal actionable rewrite," to stress-test `orgllm-rewrite-actionable` at volume and surface
> failure modes (e.g. it over-expands single tasks into multi-step plans).

---

## 2.8 Definition of Done

- [ ] B/A/G command families implemented, each routed through preview/proposal.
- [ ] `orgllm-enrich-tags` constrained to existing vocabulary (structured output, tested).
- [ ] Org invariants (heading level, IDs, LOGBOOK) preserved — tested on fixtures.
- [ ] An eval dataset + harness exists for each category, with a baseline score recorded.
- [ ] Keybindings under a single prefix (e.g. `C-c l r/v/e`).

---

## 2.9 Risks / notes

- **Over-expansion**: actionable-rewrite tends to turn one task into a mini-project. Constrain in
  the prompt ("rewrite as a single task unless clearly multiple") and test for it.
- **Tag sprawl**: without the vocabulary constraint, the model invents near-synonyms. The
  constraint is load-bearing; keep the test.
- **Language drift**: verify RU stays RU on a bilingual fixture (`bilingual.org`).
