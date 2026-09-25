# Stage 9 — Evaluation, Datasets & the Research Track (Cross-Cutting)

> Goal: the data-science spine that makes the whole project measurable instead of anecdotal —
> reusable eval datasets (real-anonymized + synthetic), per-category metrics, an LLM-as-judge
> harness, prompt/model regression testing, experiment tracking, and a list of genuine research
> questions worth a notebook. This stage is **cross-cutting**: you stand the harness up early
> (after Stage 2) and feed it from every stage.

**Question categories:** governs the quality of all A–I.
**Depends on:** runs alongside everything; first usable after Stage [02](02-selection-assistants.md).
**Effort:** ongoing.

---

## 9.1 Why an explicit eval stage

You're an ML engineer; treat each assistant as a model you ship. Without an eval harness you can't
tell whether a prompt tweak helped or quietly regressed, whether Opus is worth 5× Haiku for a task,
or whether semantic search beats BM25 on *your* notes. The harness turns "feels better" into a
number and a regression test.

---

## 9.2 Deliverables

- [ ] `eval/datasets/` — labeled sets per category (retrieval, duplicates, triage/hygiene, rewrite,
      review, refile, paper-to-note).
- [ ] A **synthetic org generator** producing trees with planted, labeled defects.
- [ ] `eval/run-eval.el` — a harness that runs a command/config over a dataset and scores it.
- [ ] `eval/rubrics/` — LLM-as-judge rubrics for generative tasks.
- [ ] An **experiment log** (sqlite) recording config → metrics, for A/B and regression.
- [ ] A short **research backlog** (open questions to investigate as notebooks).

---

## 9.3 Datasets (build incrementally, one per category)

| Dataset | Built in | Labels | Metric |
|---|---|---|---|
| `retrieval.jsonl` | [04](04-keyword-retrieval.md) | query → relevant node ids | recall@k, MRR, nDCG |
| `duplicates.jsonl` | [05](05-agentic-workflows.md) | node-pair → dup/not | precision/recall/F1 |
| `clustering/*` | [05](05-agentic-workflows.md) | flat list → reference grouping | adjusted Rand index |
| `triage.jsonl` | [05](05-agentic-workflows.md) | inbox item → {task/file-X/discard} | precision/recall/F1, confusion matrix |
| `hygiene.jsonl` | [05](05-agentic-workflows.md) | node → {task / not-a-task / stale} | precision/recall/F1 |
| `rewrite.jsonl` | [02](02-selection-assistants.md) | vague → ideal actionable | rubric (1–5) + structure-preserved check |
| `review.jsonl` | [02](02-selection-assistants.md) | subtree → known defects | detector precision/recall |
| `refile.jsonl` | [05](05-agentic-workflows.md) | item → correct destination | top-1 / top-3 accuracy |
| `paper-to-note/*` | [07](07-cross-base.md) | url → ref note + ref follow-ups | rubric + task precision/recall |

Sourcing: mine **real** examples (anonymized) where you can — they're the most valid — and
**synthesize** the rest for volume and for defect types that are rare in your real data.

---

## 9.4 Synthetic data generation (the scalable part)

A generator (strong model + templates) fabricates realistic org subtrees with **known** defects so
detectors can be measured at any volume:

- planted **duplicates** (paraphrase an existing node);
- planted **mis-tags** (apply a wrong-but-plausible tag);
- planted **not-a-task** items (reference masquerading as TODO);
- planted **stale** items (old timestamps, obsolete tech);
- planted **missing-next-action** goals.

Each generated node carries its ground-truth label in `labels/`. This gives you a large, balanced
test set that your real corpus can't provide, and lets you compute recall at known defect counts.

```elisp
;; eval/gen-synth.el (sketch)
(defun orgllm-gen-synth (n defect-type out-file)
  "Generate N org nodes of DEFECT-TYPE with ground-truth labels into OUT-FILE.")
```

> Validity caveat: synthetic data tests *mechanism*, real data tests *fit*. Report both; never
> tune solely on synthetic (it can be too clean/too uniform).

---

## 9.5 The harness (`eval/run-eval.el`)

```elisp
(defun orgllm-eval-run (dataset command config)
  "Run COMMAND with CONFIG over DATASET; score; append a row to the experiment log."
  ;; for each example: build context from the fixture, run the command with a
  ;; (possibly stubbed) backend, score against label or via rubric judge, accumulate.
  )
```

Key properties:
- **Deterministic mode:** a stubbed backend returning canned responses for unit-test-level CI
  (no network); a **live mode** for real metrics.
- **Config object** captures model, prompt-template version, params, retrieval settings — so every
  run is reproducible and comparable.
- **Append-only experiment log** (sqlite): `(timestamp, dataset, command, config, metric, value)`.

---

## 9.6 LLM-as-judge for generative tasks

Rewrite, review, summary, paper-note quality aren't string-matchable. Use a rubric judge:

- Rubrics live in `eval/rubrics/` as data (e.g. rewrite: clarity, actionability, structure
  preserved, language fidelity — each 1–5 with anchored descriptions).
- Judge with a strong model (`claude-opus-4-8`), **different** from or at least independent of the
  generator; report per-criterion scores.
- **Calibrate the judge** against a handful of your own human ratings (compute agreement) so you
  trust it before relying on it at scale.
- Pair every generative rubric with a **hard programmatic check** (org valid? IDs preserved?
  LOGBOOK intact? language unchanged when not translating?) — these are pass/fail gates.

---

## 9.7 Regression testing & A/B (the payoff)

- **Prompt regression:** every prompt template is versioned (Stage 1 registry); changing one
  triggers an eval run; a drop on the relevant dataset blocks the change. This is the main reason to
  keep prompts as data.
- **Model A/B:** run the same dataset on `claude-haiku-4-5` vs `claude-sonnet-4-6` vs
  `claude-opus-4-8` (and a local model); plot the quality/cost frontier; pick per-command routing.
- **Pipeline A/B:** the Stage-6 comparison matrix (embedder, chunker, rerank, BM25) lands here.
- **Trend tracking:** because results are logged, you can watch metrics over time and catch silent
  drift (e.g. a gptel/model update changing behavior).

---

## 9.8 Research backlog (notebook-worthy questions)

Genuine open questions this corpus lets you study — each a small experiment:

1. **Org chunking ablation:** does subtree+breadcrumb actually beat body-only / fixed-size on
   retrieval? By how much? (Public literature on org-specific chunking is thin — your result is
   genuinely novel.)
2. **Semantic vs BM25 on personal notes:** does dense retrieval beat strong keyword search on a
   keyword-rich personal corpus, or is it a wash? (Often a wash — worth proving for yourself.)
3. **Reranker value:** LLM-as-reranker vs cross-encoder vs none — quality delta vs latency/infra.
4. **Cheap-vs-strong routing:** for which categories does Haiku match Opus? Where's the cliff?
5. **Multilingual retrieval:** how well does bge-m3 bridge your RU↔EN mix vs alternatives?
6. **Instruction-count degradation:** does a longer `AGENTS.md` measurably hurt adherence? Find the
   point where adding rules stops helping.
7. **Self-critique / self-consistency:** does a second filtering pass improve precision on
   hygiene/duplicate detection without tanking recall?
8. **Acceptance-rate as a quality signal:** does your real edit-acceptance rate (from the audit log)
   correlate with offline rubric scores? (Validates the whole eval approach against lived use.)

---

## 9.9 Python? — Optional, for analysis/plots only.

The harness, judges, and metrics run fine in elisp. But for ad-hoc analysis, plotting frontiers,
or significance testing you may *prefer* a Python/Jupyter notebook reading the sqlite experiment
log — that's a comfortable use of Python that doesn't touch the runtime system. Keep the system
elisp; analyze in whatever you like.

---

## 9.10 Definition of Done (treat as ongoing)

- [ ] `run-eval.el` harness with deterministic + live modes; sqlite experiment log.
- [ ] ≥1 dataset per category, with real + synthetic examples and ground-truth labels.
- [ ] LLM-as-judge rubrics + calibration-against-human agreement for generative tasks.
- [ ] Prompt-change → eval-run regression gate wired for at least the Stage-2 commands.
- [ ] At least 2 research-backlog questions answered with a logged experiment.

---

## 9.11 Risks / notes

- **Eval cost:** live eval makes real API calls — keep datasets small (20–50), cache responses,
  use Haiku for judging where it's calibrated, and run full sweeps sparingly.
- **Judge bias:** an LLM judge can favor a particular style; calibrate against human ratings and
  don't optimize purely to the judge.
- **Synthetic ≠ real:** always report real-data metrics alongside synthetic; tune on the mix.
- **Don't let eval become the project.** It exists to keep the assistants honest — build just
  enough to catch regressions and answer the research questions you actually care about.
