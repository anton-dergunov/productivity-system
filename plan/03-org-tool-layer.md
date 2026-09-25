# Stage 3 — Org Semantic Tool Layer (Operations the Model May Call)

> Goal: expose your *org operations* — capture, refile, state change with logging, schedule,
> tag, agenda/org-ql query — as sanctioned tools the LLM can call, so that mutations are
> **structurally correct** (LOGBOOK entries created, IDs preserved, templates respected) rather
> than text-edited and hoped-for. Start with the 80/20 `emacsclient`-eval approach; optionally
> graduate to a proper MCP server for reuse across clients.

**Question categories:** **G** (apply enrichment correctly); enables **C/D/H** in Stage 5.
**Depends on:** Stage [01](01-core-client.md) (uses request + preview).
**Effort:** ~1 week.

---

## 3.1 Why a tool layer (and why it matters more for Org than Obsidian)

Your asymmetry intuition from the Obsidian chat is exactly right: the value of a tool layer is
proportional to how much **operational semantics** sit on top of the files. Obsidian notes are
inert markdown — an agent with filesystem access does fine. Org is the opposite: a running Emacs
holds your TODO state machine, capture templates, agenda config, IDs, property drawers, clocking,
statistics cookies. A raw text edit of `TODO`→`DONE` can silently skip the `:LOGBOOK:` entry that
`org-todo` would create. A tool that exposes *your operation* makes correctness structural.

---

## 3.2 Deliverables

- [ ] A set of sanctioned org-operation functions (pure elisp, individually tested).
- [ ] `emacsclient`-eval exposure of those functions for external agents (Claude Code, etc.).
- [ ] gptel tool-use registration so the **in-Emacs** assistant can call them.
- [ ] A permission/audit tier (RO / RW) and a confirm-before-write gate.
- [ ] (Optional) the same functions exposed as a real MCP server via `mcp-server-lib.el`.

---

## 3.3 Reused libraries

| Need | Library |
|---|---|
| Org operations | built-in `org`, `org-capture`, `org-refile`, `org-id`, `org-clock` |
| Structured query | **org-ql** |
| In-Emacs tool-use | **gptel** `gptel-make-tool` / `gptel-tools` |
| External tool transport | `emacsclient --eval` (built-in), or **mcp-server-lib.el** for MCP |
| Reference design | **gptel-got** (RO/RW/RWX tool tiers for org), **rhblind/emacs-mcp-server** (10 org + 3 roam tools) |

---

## 3.4 The sanctioned operations

Write each as a small, pure-ish elisp function with a typed signature and a docstring (the
docstring becomes the tool description the model sees). Group by permission tier.

**Read-only (RO):**

```elisp
(defun orgllm-tool-query (ql-sexp &optional files)
  "Run an org-ql query QL-SEXP over FILES; return a list of (heading file id todo tags).")
(defun orgllm-tool-agenda (span)
  "Return agenda items for SPAN (today|week) as structured data.")
(defun orgllm-tool-get-node (id)
  "Return the full subtree text + metadata for node ID.")
(defun orgllm-tool-list-tags ()
  "Return the existing tag vocabulary.")
```

**Read-write (RW) — each goes through confirm/preview:**

```elisp
(defun orgllm-tool-capture (template-key fields)
  "Capture a new item using your `org-capture-templates' TEMPLATE-KEY and FIELDS.")
(defun orgllm-tool-set-state (id new-state)
  "Change TODO state of node ID via `org-todo' (logs to LOGBOOK).")
(defun orgllm-tool-refile (id target)
  "Refile node ID under TARGET heading (preserves subtree + IDs).")
(defun orgllm-tool-schedule (id date)
  "Set SCHEDULED/DEADLINE on node ID.")
(defun orgllm-tool-add-tag (id tag)
  "Add TAG to node ID (only from existing vocabulary unless forced).")
```

Why these exact ops: they cover G fully and are the verbs Stage 5 workflows compose
(triage → capture/refile; prioritization → schedule; hygiene → set-state/refile).

**Invariants & tests (critical):**
- `set-state` produces a LOGBOOK entry (assert drawer grows);
- `refile` preserves the node's `:ID:` and all child IDs (assert IDs unchanged, links intact);
- `capture` uses your real template (assert resulting node matches template shape);
- every RW op is **idempotent-safe** and **confirm-gated** (no write without approval).

---

## 3.5 Exposing tools — two transports

### (a) `emacsclient --eval` — the 80/20

Since the agent (Claude Code) runs locally next to your Emacs daemon, you don't strictly need
MCP. Document the sanctioned functions in `AGENTS.md` and let the agent call:

```
emacsclient --eval '(orgllm-tool-set-state "abcd-1234" "DONE")'
```

Zero extra moving parts; it *is* a tool layer. Add a thin allow-list wrapper
`orgllm-rpc` that only dispatches to whitelisted functions and refuses arbitrary eval (security).

### (b) gptel tool-use — for the in-Emacs assistant

Register each function as a gptel tool so your Emacs-native assistant (Stages 2/5) can call them
in a tool-use loop:

```elisp
(gptel-make-tool
 :name "org_query" :function #'orgllm-tool-query
 :description "Run an org-ql query and return matching headings."
 :args '((:name "ql_sexp" :type string :description "org-ql sexp DSL")))
```

### (c) MCP server (optional, later) — for reuse across clients

When the "global system" ambition arrives (Stage 8), wrap the same functions as a proper MCP
server with **mcp-server-lib.el** (or adopt **rhblind/emacs-mcp-server**, which already ships
~10 org tools + 3 org-roam tools and respects your live capture templates/tags). MCP buys you
clean tool schemas and one definition reused by gptel, Claude Code, and future faces.

> Recommendation: ship (a)+(b) now; defer (c) until you have ≥2 faces wanting the same tools.

---

## 3.6 Permission & audit

Adopt a tiered model (à la gptel-got):
- **RO** tools run freely.
- **RW** tools require confirmation (a `y-or-n-p` or, for batches, a preview list you approve).
- An **audit log** (append-only org or sqlite) records every RW op: timestamp, tool, args,
  node id, accepted/rejected. This is your safety net and, later, eval data ("how often did I
  reject the agent's proposal?").

---

## 3.7 Optional / alternative implementations (research)

- **Adopt vs build:** evaluate `rhblind/emacs-mcp-server` and `laurynas-biveinis/org-mcp`
  against your own functions. Build-your-own wins on fit (your capture templates, your IDs);
  adopting wins on maintenance. A reasonable hybrid: adopt their server, add your custom tools.
- **Structured-output capture:** have the model emit a JSON object matching a capture template's
  fields; validate against a schema before `org-capture`. Reduces malformed captures.
- **Dry-run mode:** every RW tool can run in `:dry-run t` returning the *would-be* diff, which the
  agent shows you before committing. Pairs with the audit log for measuring acceptance rate.

---

## 3.8 Python? — No.

This layer is inherently Emacs-side (it *is* org/Emacs semantics). Python would only re-implement
org badly. Stay in elisp.

---

## 3.9 Evaluation for this stage

- **Invariant tests** (the core): LOGBOOK created on state change; IDs preserved on refile;
  capture matches template; tag added only from vocabulary. All on fixtures, headless.
- **Tool-call correctness:** with a stubbed model that emits a known tool call, assert the loop
  dispatches to the right function with parsed args.
- **Security:** `orgllm-rpc` refuses a non-whitelisted symbol; refuses arbitrary `eval`.
- **Acceptance-rate baseline:** after a week of use, compute % of RW proposals you accepted from
  the audit log — your first real "is the agent trustworthy here" metric.

---

## 3.10 Definition of Done

- [ ] RO + RW tool functions implemented and invariant-tested.
- [ ] `emacsclient`-eval allow-listed dispatch (`orgllm-rpc`) works from a shell.
- [ ] gptel tools registered; an in-Emacs tool-use loop can query + (confirm-gated) mutate.
- [ ] RW confirm gate + append-only audit log in place.
- [ ] `AGENTS.md` updated to document the sanctioned functions for external agents.

---

## 3.11 Risks / notes

- **Arbitrary-eval danger:** never expose raw `eval` over emacsclient to an agent — always go
  through the allow-list. Test the refusal path.
- **Buffer vs disk state:** external `emacsclient` ops act on live buffers (good — reflects
  unsaved edits), whereas file-based MCP servers read disk. Be consistent; prefer the live-Emacs
  path so the agent sees what you see.
- **Confirm fatigue:** for batch workflows (Stage 5) use a single approve-the-list step instead of
  per-op prompts.
