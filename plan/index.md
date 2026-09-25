# LLM Integration for Org-Mode Planning — Master Plan

> A staged, research-flavored implementation plan for bringing LLM assistance into an
> Emacs + Org-mode planning system, built mostly in Emacs Lisp (with tests), reusing
> existing libraries where they are strong and building bespoke components where org
> semantics demand it.

This is the index. Each **stage** has its own file in this folder with concrete steps,
library choices, elisp sketches, optional/alternative implementations, tests, and a
data-science evaluation section. Read this file first, then work the stages in order —
but every stage is designed to be **independently useful**, so you always have a working
system after each one.

---

## 1. What we are building

A personal LLM assistant for your **org planning files** that supports *every* question
category below. It starts as a thin, safe, selection-scoped client inside Emacs and grows,
layer by layer, into a retrieval-backed, tool-using, cross-base (Org ↔ Obsidian) system
that you can also reach on the go — without ever forcing you to leave Emacs for daily work.

### The nine question categories (the acceptance target)

The whole project is "done" when these are all supported with a real command and a
reviewable output. (Letters match the taxonomy from our earlier discussion.)

| # | Category | Example query | Primary stage |
|---|----------|---------------|---------------|
| A | Review & critique a subtree | "What's missing under *Back*? Is this done?" | [02](02-selection-assistants.md) |
| B | Rewrite / polish selected text | "Make this task actionable; translate RU→EN" | [02](02-selection-assistants.md) |
| C | Organize / group / restructure | "Cluster this flat ML list; find duplicates" | [05](05-agentic-workflows.md) |
| D | Prioritization & planning | "What should I do next in *Languages*?" | [05](05-agentic-workflows.md) |
| E | Search & cross-file Q&A | "Where did I note pose detection?" | [04](04-keyword-retrieval.md) / [06](06-semantic-retrieval.md) |
| F | Summarize & digest | "Turn *Unsorted* into a themed TOC" | [05](05-agentic-workflows.md) |
| G | Enrichment & metadata | "Suggest tags/DEADLINE; annotate this link" | [02](02-selection-assistants.md) / [03](03-org-tool-layer.md) |
| H | Consistency & hygiene | "Find items under TODO that aren't tasks" | [05](05-agentic-workflows.md) |
| I | Goal alignment | "Which Projects tasks serve my ML goal?" | [05](05-agentic-workflows.md) / [06](06-semantic-retrieval.md) |

---

## 2. Architecture in one picture

The single most important idea, distilled from your two research chats: **interaction
surface, knowledge scope, and agent capability are three orthogonal axes.** Do not couple
them.

```
        ┌──────────────────────── FACES (interaction surfaces) ───────────────────────┐
        │   Emacs (gptel + orgllm)      Obsidian (later)      Mobile / remote (later)  │
        └───────────────────────────────────┬─────────────────────────────────────────┘
                                             │
                            ┌────────────────┴────────────────┐
                            │     ONE BACKEND / ONE BRAIN       │
                            │  models: Claude (API) | Ollama    │
                            └────────────────┬────────────────┘
                                             │
          ┌──────────────────────────────────┼──────────────────────────────────┐
          │ TOOL / CAPABILITY LAYER                                              │
          │  • org operations (emacsclient eval → capture/refile/state/agenda)   │
          │  • keyword/structured retrieval (ripgrep, org-ql)                    │
          │  • semantic retrieval (org-aware chunker + embeddings, later)        │
          │  • file read/write/grep over both roots (agentic, later)             │
          └──────────────────────────────────┬──────────────────────────────────┘
                                             │
                    ┌────────────────────────┴────────────────────────┐
                    │ KNOWLEDGE SCOPE                                   │
                    │  Org plans (~670 KB, ~170K tok)  +  Obsidian vault│
                    │                                   (~2.6 MB md)    │
                    └──────────────────────────────────────────────────┘
```

**Consequences of this picture:**

- The Emacs client is "just a face." Giving it more knowledge scope or more tools is
  *configuration*, not a re-architecture. You are never locked in.
- We start with the Emacs face + org scope + minimal tools, and add scope/tools/faces over
  time. Each addition is a stage, not a rewrite.
- Heavy autonomous multi-file jobs can be delegated to an agent (Claude Code / Agent SDK)
  using the **same** backend and **same** roots — optionally launched from inside Emacs.

---

## 3. Design principles (apply to every stage)

1. **Never auto-write.** Every mutation is shown as an `ediff`/diff or proposal buffer and
   applied only on your confirmation. Your data is dear; the system is a co-pilot, not an
   autopilot. (Stage [01](01-core-client.md) builds this harness once; everything reuses it.)
2. **Scope by default.** Most operations need only the current subtree/region/file. Send the
   minimum context. Whole-corpus and cross-file work is the exception, gated behind retrieval
   or explicit opt-in. (Cost & quality both improve.)
3. **Each layer independently useful.** After every stage you have something you'd use daily.
   This is the property that keeps hobby infrastructure alive.
4. **Reuse before build.** gptel, org-ql, consult, ripgrep, Khoj, mcp-server-lib.el do heavy
   lifting. We build only the org-semantic glue that has no good off-the-shelf equivalent
   (the org-aware chunker, the operation tool layer, the eval harness).
5. **elisp-first, Python only when it removes real pain.** The one place Python earns its
   keep is the cross-encoder reranker in the research track (Stage [06](06-semantic-retrieval.md));
   everything else stays in Emacs Lisp. We always offer an elisp-only fallback.
6. **Local-first privacy.** Cloud (Anthropic API, commercial terms — no training, 7-day
   retention) for hard synthesis on non-sensitive files; Ollama-local for `Health.org`,
   `Financial.org`, `Relationships.org`. Scope discipline is enforced in code, not vibes.
7. **Everything is evaluated.** As an ML engineer you get a real DS spine: fixture corpora,
   labeled datasets (real-anonymized + synthetic), per-category metrics, LLM-as-judge rubrics,
   and prompt/model regression tests. See [09](09-evaluation-research.md).

---

## 4. Technology stack (summary)

| Concern | Choice | Notes |
|---|---|---|
| LLM client (Emacs) | **gptel** | de-facto Emacs LLM client; org-native; tool-use; `gptel-rewrite` w/ ediff |
| Cloud model | **Claude `claude-opus-4-8`** (default), `claude-sonnet-4-6` (mid), `claude-haiku-4-5` (cheap/triage) | API key on a developer account = commercial terms |
| Local model | **Ollama** (e.g. Qwen/Llama 14–32B) | sensitive files; offline; cheap routine tasks |
| Keyword search | **ripgrep** + **consult-ripgrep** | instant, exact, no AI |
| Structured search | **org-ql** (+ consult) | tags/state/deadline/property DSL |
| Org operation tools | **emacsclient eval** (80/20), then **mcp-server-lib.el** | capture/refile/state/agenda as sanctioned functions |
| Embeddings | **Ollama `bge-m3`** (or `nomic-embed-text-v1.5`) via HTTP | Anthropic has no embeddings endpoint; local is private + free |
| Vector store | **Emacs 29+ built-in `sqlite`** (brute-force cosine) → sqlite-vec/Khoj at scale | a few thousand chunks ⇒ brute force is fine |
| Reranker | **LLM-as-reranker** (elisp) // **bge-reranker-v2-m3** (Python, research) | the one justified Python component |
| Turnkey semantic option | **Khoj** (self-hosted) | native org + markdown, keeps index fresh, mobile/web clients |
| Agentic cross-base | **Claude Code / Agent SDK**, optionally via **claude-code-ide.el** | one agent, two roots, ediff review |
| HTTP in elisp | **plz.el** | modern curl-backed HTTP for Ollama/embeddings |
| Build/test | **Eask** + **ERT**/**buttercup** + checkdoc/package-lint | CI via GitHub Actions optional |

Model-ID note: use the exact strings above (`claude-opus-4-8`, `claude-sonnet-4-6`,
`claude-haiku-4-5`). Default to Opus 4.8 for quality; drop to Haiku 4.5 for high-volume
classification (e.g. inbox triage) where cost matters.

---

## 5. Stage roadmap

| Stage | File | Goal | Categories | Rough effort | Depends on |
|---|---|---|---|---|---|
| 0 | [00-foundations.md](00-foundations.md) | Project scaffolding, env, fixtures, baseline non-AI search, conventions doc | — (E partial) | 1 weekend | — |
| 1 | [01-core-client.md](01-core-client.md) | `orgllm` core: context extraction + request wrapper + preview/apply safety harness | infra for all | 1 weekend | 0 |
| 2 | [02-selection-assistants.md](02-selection-assistants.md) | Rewrite, review-subtree, enrich — selection-scoped commands | A, B, G | 1–2 weeks | 1 |
| 3 | [03-org-tool-layer.md](03-org-tool-layer.md) | Org operation tools (emacsclient eval; later MCP) + tool-use wiring | G, enables C/D/H | 1 week | 1 |
| 4 | [04-keyword-retrieval.md](04-keyword-retrieval.md) | ripgrep + org-ql retrieval as commands *and* tools; aggregations | E (exact/structured) | 3–5 days | 0 |
| 5 | [05-agentic-workflows.md](05-agentic-workflows.md) | Multi-file workflows: triage, dedup, regroup, hygiene, prioritization, goal alignment, weekly review | C, D, F, H, I | 2–4 weeks | 2,3,4 |
| 6 | [06-semantic-retrieval.md](06-semantic-retrieval.md) | Org-aware chunker + embeddings + retrieve-then-rerank; Khoj vs custom; the research stage | E (fuzzy), boosts C/I | 2–4 weeks (research) | 4 |
| 7 | [07-cross-base.md](07-cross-base.md) | One agent, two roots; the paper→Obsidian-note→gap-analysis flagship workflow | cross-border | 1–2 weeks | 3,5 |
| 8 | [08-global-system.md](08-global-system.md) | Shared backend/index, remote + mobile access, ops, privacy enforcement | deployment | 1–2 weeks | 6,7 |
| 9 | [09-evaluation-research.md](09-evaluation-research.md) | The cross-cutting DS spine: datasets, metrics, judges, experiments, research questions | quality of all | ongoing | all |

A reasonable **MVP milestone** is end of Stage 2 (you can rewrite, review, and enrich any
subtree safely). A reasonable **"daily driver" milestone** is end of Stage 5. Stages 6–9 are
the research/scale/ergonomics frontier.

---

## 6. Repository layout (proposed)

Lives alongside your existing config (e.g. inside the `productivity-system` repo or as a
sibling package). Working package name **`orgllm`** (rename freely; one prefix throughout).

```
orgllm/
  orgllm.el                 ; entry / customization group / autoloads
  orgllm-context.el         ; subtree/region/file/breadcrumb extraction (Stage 1)
  orgllm-request.el         ; gptel request wrappers, model routing, privacy gate (Stage 1)
  orgllm-preview.el         ; ediff/proposal-buffer apply harness (Stage 1)
  orgllm-prompts.el         ; prompt template registry (Stage 1+)
  orgllm-rewrite.el         ; category B (Stage 2)
  orgllm-review.el          ; category A (Stage 2)
  orgllm-enrich.el          ; category G (Stage 2)
  orgllm-tools.el           ; org operation tools + gptel-make-tool (Stage 3)
  orgllm-search.el          ; ripgrep/org-ql commands + tools (Stage 4)
  orgllm-workflows.el       ; triage/dedup/regroup/hygiene/prioritize/goals (Stage 5)
  orgllm-index.el           ; chunker + embeddings + vector store (Stage 6)
  orgllm-retrieve.el        ; retrieve-then-rerank (Stage 6)
  orgllm-crossbase.el       ; Org↔Obsidian workflows (Stage 7)
  test/
    fixtures/               ; sample + synthetic org corpora (Stage 0)
    orgllm-context-test.el
    ...
  eval/
    datasets/              ; labeled eval sets per category (Stage 9)
    rubrics/               ; LLM-as-judge rubrics
    run-eval.el            ; harness
  AGENTS.md                ; conventions for any agent (Stage 0 / 7)
  CLAUDE.md                ; one line: @AGENTS.md (Claude Code import)
  Eask                     ; build/test config
  README.md
```

---

## 7. Privacy model (enforced, not aspirational)

- **Tier L (local-only):** `Health.org`, `Financial.org`, `Relationships.org`, anything you
  tag `:private:`. Routed to Ollama. The code in [01](01-core-client.md) refuses to send these
  to any cloud backend (a hard gate keyed on file path / tag, with tests).
- **Tier C (cloud-ok):** `Projects.org`, `ML.org`, `Programming.org`, technical/learning notes.
  Routed to Claude API under commercial terms (no training, short retention).
- **Redaction layer (optional):** a regex pass stripping your name/family/employer before any
  cloud call, surfaced for review. See [08](08-global-system.md).
- Use **API keys on a developer account**, never consumer Claude/ChatGPT/Gemini, for any
  cloud call. (See your `chat_about_architecture.md` §6 for the full provider comparison.)

---

## 8. Evaluation philosophy (the DS spine)

Every assistant is treated as a model you ship and regression-test:

- **Fixture corpus** (Stage 0): an anonymized subset of your real files + synthetically
  generated org trees, so tests are deterministic and shareable.
- **Labeled datasets** (Stage 9): e.g. duplicate pairs (C), refile targets (C), retrieval
  relevance judgments (E), "is this a real task?" labels (H).
- **Metrics per category:** retrieval → recall@k / MRR / nDCG; classification (triage, hygiene)
  → precision/recall/F1; generative (rewrite, review, summary) → LLM-as-judge rubric scores +
  spot human review.
- **Synthetic data generation:** use a strong model to fabricate realistic org subtrees with
  known defects (missing next-action, duplicate, mis-tagged) to test detectors at scale.
- **Experiment tracking:** prompts/models/params logged (datasette-style sqlite) so you can A/B
  and avoid silent regressions when you tweak a prompt.

Details and reusable harness in [09](09-evaluation-research.md).

---

## 9. Decision thresholds & what NOT to build

- **Don't build semantic search until keyword search has measurably failed** ≥5 real queries.
  At your corpus size, ripgrep + whole-file context beats RAG for most tasks.
- **Don't build GraphRAG.** Org headings are already entities; `[[id:]]` links are already
  edges. A 1–2 hop link-follow tool gives ~80% of the value at ~5% of the cost.
- **Don't replace org with Obsidian** (or vice-versa). Org = system of commitments; Obsidian =
  system of knowledge. Keep the split; let the agent bridge it (Stage 7).
- **Don't let any agent write unattended.** Preview-and-apply, always.
- Re-evaluate the embeddings decision if org text grows past ~50 MB (won't happen — you're
  shrinking it) or if Khoj recall@5 < 0.7 on your eval set.

---

## 10. How to use this plan

- Treat each stage file as a **sprint backlog**: it has a goal, deliverables, a build section,
  optional/research branches, tests, an evaluation section, and a "Definition of Done" checklist.
- You can stop after any stage and have a coherent product.
- Where a stage offers **alternatives** (e.g. in-Emacs tools vs Claude Code; LLM-rerank vs
  cross-encoder), treat them as experiments to run and compare — that's the research flavor you
  asked for, and Stage 9 gives you the measurement tools.

---

## 11. Glossary

- **Face / frontend** — an interaction surface (Emacs, Obsidian, mobile).
- **Tool layer** — sanctioned operations the model may call (org capture/refile/state, search).
- **Org-aware chunking** — splitting org by heading subtree with ancestor breadcrumb + metadata,
  the single highest-leverage retrieval decision.
- **Preview-and-apply** — the safety harness: model proposes, you review a diff, you apply.
- **Tier L / Tier C** — privacy routing (local-only vs cloud-ok).
- **LLM-as-judge** — using a model with a rubric to score generative outputs in evaluation.
