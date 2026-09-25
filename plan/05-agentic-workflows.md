# Stage 5 — File & Cross-File Agentic Workflows

> Goal: deliver the multi-file, multi-step workflows that need the model to *plan and compose
> tools* — inbox triage, duplicate detection, regrouping/clustering, hygiene audit,
> prioritization, goal alignment, weekly review, digests. Reaching here is your **daily-driver
> milestone**: the system now helps you run your planning practice, not just edit one node.

**Question categories:** **C** (organize), **D** (prioritize), **F** (summarize/digest),
**H** (hygiene), **I** (goal alignment).
**Depends on:** Stages [02](02-selection-assistants.md), [03](03-org-tool-layer.md), [04](04-keyword-retrieval.md).
**Effort:** ~2–4 weeks.

---

## 5.1 Two implementation strategies (and when to use each)

These workflows are agentic: read several files, reason, call tools, propose changes. You have
two ways to run them, sharing the same backend/roots/tools:

| Strategy | What it is | Best for | Trade-off |
|---|---|---|---|
| **(A) In-Emacs gptel + tool-use loop** | The Stage 3 tools + a controller loop in elisp | bounded, repeatable workflows (triage, dedup, hygiene) that you want fully inside Emacs with native preview | you write the orchestration; long loops block a buffer |
| **(B) Claude Code / Agent SDK over the folder** | An external agent with file + your `emacsclient` tools, driven via `claude-code-ide.el` | open-ended, heavy autonomous jobs (big reorg, year-end rollup) needing free exploration + ediff review | less "Emacs-native"; terminal session |

**Recommendation:** build each workflow first as **(A)** because it stays uniform elisp, is
testable, and gives you native preview; reserve **(B)** for the genuinely open-ended jobs where
writing a bespoke controller isn't worth it. Treat (A) vs (B) as a comparison experiment per
workflow (Stage 9): measure quality, latency, and your edit-acceptance rate.

The in-Emacs controller is a small loop:

```elisp
(defun orgllm-workflow-run (system goal &optional tools)
  "Run a tool-use loop: SYSTEM prompt, GOAL, allowed TOOLS; collect a proposal."
  (let ((gptel-tools (or tools orgllm-default-tools)))
    (orgllm-request goal :system system
      :callback #'orgllm-workflow--present)))  ; present proposal for review
```

---

## 5.2 The workflows

### C — Organize / group / restructure (`orgllm-workflows.el`)

| Command | Behavior | Output |
|---|---|---|
| `orgllm-cluster-file` | propose a thematic grouping of a flat list (e.g. the ML-practice list → NLP/CV/recommenders/generative/classical) | proposed reorganized subtree (ediff) |
| `orgllm-find-duplicates` | scan across files for near-duplicate nodes (Anki appears in Projects+Languages; Kokoro in Projects+Inbox) | table of (node A, node B, similarity, suggested merge) |
| `orgllm-suggest-refile` | for a node/inbox item, propose target file+heading with confidence | refile proposal → Stage-3 `refile` tool on accept |
| `orgllm-merge-subtrees` | merge two related subtrees, de-duping children | ediff of merged result |

For duplicates, start with a cheap candidate generator (ripgrep/title-trigram overlap), then ask
the model to judge only the candidate pairs — don't ask it to compare all-pairs. (This is the
classic blocking-then-scoring IR pattern; it's also far cheaper.)

### F — Summarize / digest

| Command | Behavior |
|---|---|
| `orgllm-digest-file` | turn a dump (`Unsorted`/`Inbox`) into a themed table-of-contents subtree |
| `orgllm-inbox-triage` | for each inbox item: classify {make-task / file-to-X / discard}, propose action |
| `orgllm-area-overview` | "state of my Health goals in 10 bullets" from one file |

`orgllm-inbox-triage` is the highest-value F workflow and a great **cheap-model** target: route
each item to `claude-haiku-4-5` for classification, batch them, present one approve-the-list step
that then drives Stage-3 `capture`/`refile` tools. (Confirm-once, not per-item.)

### H — Consistency & hygiene

| Command | Behavior |
|---|---|
| `orgllm-hygiene-not-a-task` | flag items under TODO trees that are really reference (no action verb) |
| `orgllm-hygiene-keywords` | flag inconsistent TODO-keyword usage / heading depth |
| `orgllm-hygiene-orphans` | `:goal:` nodes with no next action / no schedule (org-ql + LLM rationale) |

Hygiene is partly mechanical (org-ql finds candidates) + partly judgment (LLM explains/justifies).
Compose: org-ql narrows, LLM annotates and proposes the fix, you approve.

### D — Prioritization & planning

| Command | Behavior |
|---|---|
| `orgllm-next-actions` | "what should I do next in AREA?" given goals + state + deadlines |
| `orgllm-sequence-project` | order a project's tasks with dependencies + suggested schedule |
| `orgllm-quick-wins` | surface low-effort/high-value items in an area |

These consume Stage-4 aggregations (deadlines, stale) + the goal statements at the top of files
(e.g. `Projects.org` goals). Output is advisory (proposal buffer); accepted scheduling flows
through the Stage-3 `schedule` tool.

### I — Goal alignment

| Command | Behavior |
|---|---|
| `orgllm-align-goals` | score each task in a file against the file's stated goals; flag misaligned |
| `orgllm-goal-coverage` | for each goal, list which tasks serve it; surface goals with no tasks |

This is where Stage-6 semantic retrieval later helps (matching tasks↔goals by meaning, not
keywords), but a first version works on a single file in one context window.

### Weekly review (capstone, composes everything)

`orgllm-weekly-review`: pull last week's clocked/closed items (Stage-3 agenda/clock tools),
compare planned vs done, surface stale goals (H), propose next-week priorities (D), write a review
subtree to `Inbox.org` for your Monday read. This single command exercises C/D/F/H/I together and
is the best "is this system actually useful" smoke test.

---

## 5.3 Output discipline (so multi-file edits stay safe)

- Cross-file mutations are **never** applied in bulk silently. Each workflow yields a **proposal**:
  either a list of tool-calls you approve as a batch, or an ediff per file.
- Prefer **structured proposals** (JSON: list of `{op, node-id, args, rationale, confidence}`)
  that you render as a checklist; you toggle items, then apply via Stage-3 tools. This gives you
  per-item control without per-item prompts.
- Everything goes through the Stage-3 audit log.

---

## 5.4 Optional / alternative implementations (research)

- **(A) vs (B) head-to-head:** run `orgllm-cluster-file` and a year-rollup both ways; measure
  output quality (rubric), token cost, latency, and your acceptance rate. Decide per-workflow.
- **Cheap-vs-strong model routing:** triage/hygiene classification on `claude-haiku-4-5`; synthesis
  (digest, weekly review) on `claude-opus-4-8`. Measure the quality/cost frontier (Stage 9).
- **Self-critique pass** for duplicates/hygiene: generate findings, then a second prompt prunes
  false positives. Compare precision/recall vs single-pass on labeled fixtures.
- **Link-follow expansion** for goal alignment: when a task links `[[id:]]` to another node,
  pull 1–2 hops of linked context (the lightweight "personal graph" alternative to GraphRAG).

---

## 5.5 Python? — Mostly no.

Stay in elisp for orchestration. The only place Python *might* tempt you is large-scale duplicate
detection if you wanted embedding-based candidate generation — but that belongs in Stage 6, and
even there the candidate generator can be elisp + Ollama embeddings. Keep Stage 5 pure elisp.

---

## 5.6 Evaluation for this stage (DS — this is the rich one)

Per workflow, build a labeled dataset and a metric:

- **Duplicates (C):** a set of labeled duplicate/non-duplicate node pairs (mine real near-dupes
  like Anki/Kokoro; synthesize more by paraphrasing nodes). Metric: precision/recall/F1; also
  measure candidate-generator recall (does blocking miss true dupes?).
- **Clustering (C):** take a flat list with a hand-made "ideal grouping"; score the proposed
  grouping with clustering metrics (e.g. adjusted Rand index against your reference labels).
- **Triage/hygiene (F/H):** labeled "is-task / not-a-task", "correct destination" sets →
  precision/recall/F1; confusion matrix to see systematic errors.
- **Prioritization/goal-alignment (D/I):** harder to label objectively → LLM-as-judge rubric
  (does the ranking respect deadlines? is the alignment justified?) + periodic human spot check.
- **Acceptance rate:** from the audit log, the fraction of proposed ops you accept per workflow —
  your north-star "trust" metric over time.

Synthetic-data angle: generate org files with planted defects (N duplicates, M mis-tagged, K
not-a-task) and measure each detector's recall at known ground truth — repeatable at any volume.

---

## 5.7 Definition of Done

- [ ] Each category (C/D/F/H/I) has ≥1 working workflow with batch-approve proposals.
- [ ] `orgllm-weekly-review` composes tools end-to-end and writes a review to `Inbox.org`.
- [ ] Candidate-then-score pattern used for duplicates (no all-pairs LLM calls).
- [ ] Labeled datasets + metrics exist for duplicates, clustering, triage/hygiene; baselines logged.
- [ ] (A)-vs-(B) comparison run for at least one heavy workflow, with a recommendation recorded.

---

## 5.8 Risks / notes

- **Long-context attention degrades** past ~60k tokens of org; don't "read all files and find
  issues" blindly — scope per file or use Stage-4 retrieval to narrow first, and sample-check
  outputs (optionally with a second model).
- **Bulk-write danger:** never skip the batch-approve step. The audit log + dry-run are your guard.
- **Reorg breaks links:** prefer the Stage-3 `refile` tool (preserves IDs) over free-form file
  rewrites for any structural change.
