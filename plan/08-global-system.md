# Stage 8 — Global System: Shared Backend, Remote/Mobile Access & Ops

> Goal: turn the per-stage pieces into one coherent system you can reach from multiple faces
> (Emacs, Obsidian-side, mobile/remote) over the same backend, the same tools, and the same
> (optional) index — plus the operational glue: index maintenance, cost/prompt logging, and
> enforced privacy. This is the "keep it alive and reachable" stage, not a new-capability stage.

**Question categories:** none new — it's deployment/ops for all of A–I.
**Depends on:** Stages [06](06-semantic-retrieval.md), [07](07-cross-base.md).
**Effort:** ~1–2 weeks.

---

## 8.1 Principle: one backend, multiple faces

You already have the faces (Emacs) and will add more (Obsidian-side, mobile). The win here is to
ensure they all talk to the **same** capability layer and (if built) the **same** index, so there's
one source of truth and one place to maintain. The realistic dependency order (from your research):
shared files (done, Dropbox) → one agent + `AGENTS.md`/`CLAUDE.md` → org tool layer
(`emacsclient`/MCP) → remote access → shared semantic index last.

---

## 8.2 Deliverables

- [ ] The org tool layer exposed as a stable **MCP server** (graduating from Stage-3 `emacsclient`)
      so every face reuses one tool definition.
- [ ] **Remote access**: Tailscale + Claude Code on an always-on machine; mobile driving.
- [ ] A **shared index** location (if Stage 6 built) served to all faces; automated re-indexing.
- [ ] **Ops**: prompt/cost logging (datasette-style sqlite), and the **privacy enforcement** layer
      (scope discipline + optional redaction) productionized.

---

## 8.3 Reused libraries / infra

| Need | Tool |
|---|---|
| Org tools as MCP | **mcp-server-lib.el**, or **rhblind/emacs-mcp-server** |
| Remote networking | **Tailscale** (your machines already synced via Dropbox) |
| Remote agent | **Claude Code** over SSH / driven from the Claude mobile app |
| Prompt/cost logging | **simonw/llm** sqlite logs + **datasette**, or your own sqlite table |
| Semantic index host | your own sqlite/sqlite-vec, or **Khoj** (ships web/mobile clients) |
| Redaction (optional) | hand-tuned regex pass; Presidio if you ever want heavier NER |

---

## 8.4 Promote the org tool layer to MCP

In Stage 3 you ran tools via `emacsclient --eval` (the 80/20). Now that ≥2 faces want the same
operations, wrap them as a real MCP server (mcp-server-lib.el) — clean tool schemas, one
definition consumed by gptel, Claude Code, and any future client. Keep the `emacsclient` path as a
fallback. (If you'd rather not maintain a server, adopting `rhblind/emacs-mcp-server` and adding
your custom tools is the lower-maintenance route.)

---

## 8.5 Remote & mobile access

- **Tailscale** across your machines gives "the same agent over the same two roots" from anywhere
  via SSH — no public exposure. Run write-enabled agents on **one** machine to avoid Dropbox
  conflict copies.
- **Mobile:** Claude Code sessions can be driven from the Claude mobile app, covering a good chunk
  of "on the go" with zero new infra. For semantic search on mobile specifically, Khoj's mobile/web
  clients are the turnkey option (it hosts the index and serves all faces).
- Keep the always-on machine (a NAS/Pi/desktop) as the agent + index host; faces are thin clients.

---

## 8.6 Shared index & maintenance

- One index location (sqlite file in Dropbox, or Khoj's store on the always-on host) read by all
  faces. Avoid per-face duplicate indexes.
- **Automated re-indexing:** on-save hook for the active file (incremental, hash-diff) + a nightly
  full reconcile (cron) to catch external edits (mobile capture, Obsidian edits). Khoj does this
  itself; if custom, schedule it.
- **Index health check:** a small job that reports chunk count, last-reindex time, and any files
  missing from the index → surfaced in your weekly review.

---

## 8.7 Ops: logging, cost, privacy

- **Prompt/cost log:** record every cloud call (timestamp, file/tier, model, input/output tokens,
  cost, command, accepted?). An sqlite table queried with datasette gives you spend dashboards and
  the data to A/B prompts/models (Stage 9). Cheap, high value.
- **Privacy enforcement (productionized):**
  - The Tier-L gate (Stage 1) is the hard guarantee; add a startup self-test asserting Tier-L
    files route local.
  - Optional **redaction layer**: a regex pass stripping your name/family/employer before any cloud
    call, shown for review. Start with a hand-tuned regex over your own identifiers (enough for
    personal use); reach for Presidio only if you want NER-grade redaction.
  - **Scope discipline as code:** cloud commands refuse Tier-L; a periodic audit greps the prompt
    log for any Tier-L path that ever reached a cloud backend (should be empty).
- **Cost guardrails:** route high-volume classification to `claude-haiku-4-5`; reserve
  `claude-opus-4-8` for synthesis; cap per-day spend with a soft warning.

---

## 8.8 Optional / alternative implementations

- **Khoj as the global semantic+chat layer** vs your own: Khoj gives mobile/web for free and owns
  index maintenance; your own gives full control and fits your IR background. A sensible split:
  Khoj for the big growing vault; your sqlite pipeline for the small org corpus.
- **Webhook/scheduled jobs:** a nightly "inconsistency auditor" that diffs current state vs a saved
  snapshot and writes drift to `Inbox.org` for morning review (composes Stage-5 hygiene). Cron on
  the always-on host.

---

## 8.9 Python? — Only if you adopt Khoj/Presidio (both encapsulated).

Your code stays elisp. Khoj (Python+server) and Presidio (Python) are external services behind a
REST/CLI boundary — not code you maintain. The MCP server, logging, and redaction regex are all
fine in elisp.

---

## 8.10 Evaluation for this stage

- **Reachability test:** issue the same query from Emacs and from a remote/mobile session; assert
  identical tool access and (if indexed) identical retrieval results.
- **Index freshness:** edit a node on machine A; assert it's retrievable from machine B after the
  reconcile.
- **Privacy audit:** automated check that the prompt log contains zero Tier-L paths sent to cloud.
- **Cost report:** weekly spend + tokens by command/model, to drive routing decisions.

---

## 8.11 Definition of Done

- [ ] Org tools available as MCP (or adopted server) reused by ≥2 faces.
- [ ] Remote (Tailscale/SSH) and mobile access to the same agent + roots working.
- [ ] Shared index with automated incremental + nightly re-indexing (or Khoj managing it).
- [ ] Prompt/cost log live; privacy self-test + audit green; cost routing in place.

---

## 8.12 Risks / notes

- **Concurrent writes across machines** are the main hazard — single writer, save+sync discipline,
  prefer tools that respect live buffer state.
- **Index drift** is the silent killer of these systems — automate reconcile and surface health in
  the weekly review so you notice rot.
- **Don't over-build remote.** Tailscale + Claude Code mobile covers most "on the go"; resist a
  bespoke server until something concrete demands it.
