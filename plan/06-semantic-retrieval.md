# Stage 6 — Semantic Retrieval & Org-Aware Indexing (the Research Stage)

> Goal: add meaning-based retrieval for the queries keyword search provably misses (vocabulary
> mismatch — "onboarding ramp-up" vs notes that say "first 90 days"). Build the **org-aware
> chunker** (the single highest-leverage decision), an embeddings index, and a retrieve-then-rerank
> pipeline. This is the most research-flavored stage: multiple implementations to compare,
> embedded in a real evaluation loop. **Do not start it until Stage 4's eval shows ≥5 fuzzy
> queries where keyword recall@5 < 0.7.**

**Question categories:** **E** (fuzzy/semantic); materially improves **C** (dedup) and **I**
(task↔goal matching by meaning).
**Depends on:** Stage [04](04-keyword-retrieval.md) (gold set + the "is this earned yet?" gate).
**Effort:** ~2–4 weeks (research).

---

## 6.1 The gate: is this even needed?

Your org corpus is ~170K tokens — much of it fits a single context window, and ripgrep nails
exact terms. So semantic retrieval is *only* justified for fuzzy recall. Enforce the gate with the
Stage-4 `retrieval.jsonl` eval: if keyword recall on fuzzy queries is already high, defer this
stage indefinitely and use the budget elsewhere. When it *is* earned, this stage pays off mainly
on the larger, growing Obsidian vault (Stage 7) and on cross-vocabulary org queries.

> Honest default from your research: **try Khoj first** (turnkey, native org+markdown, keeps its
> index fresh, ships mobile/web clients). Build the custom pipeline as the *research* track to
> learn/measure, or if Khoj's recall is insufficient on your eval set.

---

## 6.2 Deliverables

- [ ] An **org-aware chunker** (subtree + ancestor breadcrumb + metadata) — reusable, tested.
- [ ] An embeddings index (Ollama `bge-m3` → Emacs built-in `sqlite`), incremental on save.
- [ ] A retrieve-then-rerank pipeline exposed as an LLM tool (`org_semantic_search`).
- [ ] A measured comparison: Khoj vs custom; embedding models; chunking variants; rerank on/off;
      semantic vs BM25 baseline.

---

## 6.3 Reused libraries

| Need | Library |
|---|---|
| Org parsing | **org-element** (reuse Stage 1 primitives) |
| Embeddings | **Ollama** `bge-m3` (1024-d, 8192 ctx, multilingual — good for RU/EN) or `nomic-embed-text-v1.5` |
| HTTP | **plz.el** |
| Vector store | **Emacs 29+ built-in `sqlite`** (vectors as blobs, brute-force cosine) |
| Turnkey option | **Khoj** (self-hosted; bi-encoder + cross-encoder built in) |
| Reranker (research) | **bge-reranker-v2-m3** (Python) — *the one justified Python component* |

---

## 6.4 The org-aware chunker (highest-leverage component)

Generic markdown chunkers shred org's structural signal. Build a structural chunker:

1. **Unit = a heading subtree** (heading line + body + children up to a token budget).
2. **Prepend the ancestor breadcrumb** to the embedded text ("Plans > Health > Back > …") — this
   is what gives the embedding its semantic anchor. (Reuse `orgllm-context--breadcrumb`.)
3. **Fold in metadata** (TODO state, tags, scheduled/deadline) both as filterable fields *and* into
   the embedded text (so "what active goals do I have?" matches `TODO`/`NEXT` nodes).
4. **Down-weight/skip `:LOGBOOK:`/`:PROPERTIES:`** in the embedded text, but keep them in the
   stored chunk so the LLM sees them when retrieved.
5. **Split long bodies (>~1500 tok)** by paragraph/sub-heading, repeating the breadcrumb on each.
6. **Stable chunk IDs** = org `:ID:` (+ sub-index for splits) so re-indexing is incremental.

```elisp
(cl-defstruct orgllm-chunk id file breadcrumb text meta hash)

(defun orgllm-chunk-buffer ()
  "Return a list of `orgllm-chunk' for the current org buffer."
  ...) ; walk org-element headlines; build embed-text = breadcrumb + meta + body
```

> This is a build-your-own area — there is no widely-used off-the-shelf org-aware chunker. Khoj's
> `org_to_entries.py` is the best public reference; read it even if you build your own. Chunking
> quality dominates everything downstream, so it's the first thing Stage 9 ablates.

---

## 6.5 Embeddings + vector store (elisp-native)

```elisp
(defun orgllm-embed (text)
  "Return embedding vector for TEXT via Ollama bge-m3."
  (let ((resp (plz 'post "http://localhost:11434/api/embeddings"
                :headers '(("Content-Type" . "application/json"))
                :body (json-encode `(("model" . "bge-m3") ("prompt" . ,text)))
                :as #'json-read)))
    (alist-get 'embedding resp)))
```

Store in Emacs's built-in sqlite (Emacs 29+): a table `chunks(id, file, breadcrumb, text, meta,
hash, vec BLOB)`. At your scale (a few thousand org chunks; ~tens of thousands once Obsidian is
added) **brute-force cosine in elisp is fine** — load vectors once, score in a loop. Incremental
re-index on save via the `hash` column (MD5 change detection, à la Khoj).

> Scale honesty: pure-elisp brute force is comfortable to ~10–20k chunks. Beyond that (large
> Obsidian vault), switch the store to **sqlite-vec** or hand vault indexing to **Khoj**. Keep the
> chunker; swap the index.

---

## 6.6 Retrieve-then-rerank

Two-stage IR pipeline (your home turf):

1. **Bi-encoder retrieval:** embed query, cosine top-50 from sqlite.
2. **Rerank top-50 → top-5.** Two implementations to compare:
   - **LLM-as-reranker (elisp, no Python):** send the 50 candidate breadcrumbs+snippets to
     `claude-haiku-4-5`/local model, ask for the top-k by relevance with scores. Zero extra infra;
     surprisingly strong; the recommended default.
   - **Cross-encoder (Python research track):** `bge-reranker-v2-m3` behind a tiny local FastAPI
     service called over HTTP. Higher quality on hard cases; the justified Python component.
3. Feed top-k chunks to the answer model, or return them via the `org_semantic_search` tool for
   the Stage-5 workflows to consume.

Expose as a tool so the agent chooses keyword vs semantic (or both) per query.

---

## 6.7 Optional / alternative implementations (the comparison matrix)

This stage is explicitly a set of experiments. Hold the Stage-4 `retrieval.jsonl` gold set fixed
and vary one axis at a time:

| Axis | Options to compare |
|---|---|
| Turnkey vs custom | **Khoj** vs your pipeline |
| Embedding model | `bge-m3` vs `nomic-embed-text-v1.5` vs `mxbai-embed-large` |
| Chunking | subtree+breadcrumb vs body-only vs fixed-size char chunks |
| Rerank | none vs LLM-as-reranker vs cross-encoder |
| Baseline | semantic vs **BM25** (from Stage 4) — does semantic actually win on *your* queries? |
| Multilingual | does `bge-m3` handle your RU/EN mix better than alternatives? (you have lots of RU) |

Each comparison is a Stage-9 experiment with recall@k / MRR / nDCG on the gold set. The BM25
baseline matters: it's common for semantic search to *not* beat strong keyword search on
keyword-rich personal notes, and proving that saves you the maintenance burden.

---

## 6.8 Python? — Only for the cross-encoder reranker, and only in the research track.

Everything else (chunker, embeddings via Ollama HTTP, sqlite store, brute-force cosine,
LLM-as-reranker) is comfortably elisp. The cross-encoder `bge-reranker-v2-m3` has no good
elisp/Ollama path, so if you pursue that comparison, run it as a tiny local HTTP service. If you'd
rather stay 100% elisp, the LLM-as-reranker covers most of the quality and you skip Python
entirely. (And if you adopt Khoj, its Python is encapsulated behind a REST client — not your code.)

---

## 6.9 Evaluation for this stage (DS — central)

- Reuse `retrieval.jsonl` (gold relevant ids). Compute **recall@5/10, MRR, nDCG** per
  configuration; produce a comparison table; pick the configuration on the Pareto frontier of
  quality vs latency vs infra cost.
- **Ablate the chunker** first (it dominates): subtree+breadcrumb vs body-only vs fixed-size.
- **Re-index correctness:** test that editing one node re-embeds only that chunk (hash check).
- **Multilingual probe:** a few RU-query→RU-node and RU-query→EN-node pairs to confirm bge-m3's
  cross-lingual retrieval works on your bilingual corpus.
- Decision record: write down which config you shipped and why (so future-you doesn't re-litigate).

---

## 6.10 Definition of Done

- [ ] Org-aware chunker implemented + tested (breadcrumb/metadata/splits/IDs).
- [ ] Embeddings index in sqlite with incremental on-save re-indexing.
- [ ] `org_semantic_search` tool live; retrieve-then-rerank working (LLM-reranker default).
- [ ] Comparison matrix run on the gold set; a shipped config chosen with a written rationale.
- [ ] BM25 baseline measured — semantic only kept if it beats it on your queries.

---

## 6.11 Risks / notes

- **Maintenance is where these projects die** (stale index six months on). Make re-indexing
  automatic (save hook) and cheap (hash diff), or offload to Khoj which maintains its own index.
- **Don't fragment structure:** never let the chunker drop the breadcrumb — that's the whole point.
- **Resist GraphRAG.** Org headings + `[[id:]]` links already give you the graph; a 1–2 hop
  link-follow tool (Stage 5) covers multi-hop needs at a fraction of the cost.
- **Scale check:** if Obsidian indexing pushes you past brute-force comfort, swap to sqlite-vec or
  Khoj before optimizing elisp loops.
