# Stage 7 — Cross-Base Integration (Org ↔ Obsidian)

> Goal: let one agent operate over **both** roots — org plans (system of commitments) and the
> Obsidian vault (system of knowledge) — and deliver the flagship cross-border workflow:
> *given a paper link, fetch it, create an Obsidian note in your template, analyze gaps against
> your learning plan, and create linked follow-up org tasks.* The two bases stay separate (the
> separation is an asset); the agent bridges them.

**Question categories:** the cross-border ones (composes B/F/G/I across two stores).
**Depends on:** Stages [03](03-org-tool-layer.md) (org tools), [05](05-agentic-workflows.md) (workflow controller).
**Effort:** ~1–2 weeks.

---

## 7.1 Principle: one agent, two roots, two faces

From your Obsidian chat: keep **Org = commitments**, **Obsidian = knowledge**; don't merge them.
The agent's job is to *link* them. Concretely, the same backend gets read/write access to both
directories; the *face* you use can be Emacs (for org-centered tasks) or a vault-side assistant
(for note-centered tasks), but data scope is shared, not disjoint.

Two access mechanisms, by store:

- **Org:** the Stage-3 tool layer (operational semantics — capture/refile/state/IDs).
- **Obsidian:** **direct filesystem access** (it's inert local markdown). An agent can read, grep,
  parse, and write notes with no server. Obsidian MCP is an *optional* later refinement, worth it
  only for Obsidian-native conveniences (heading-relative patching, tag ops, templates, link
  graph). For your scenario MCP is *more* limiting than FS, so default to FS + a good `AGENTS.md`.

---

## 7.2 Deliverables

- [ ] An agent configuration with both roots accessible (and Tier-L exclusions enforced).
- [ ] `AGENTS.md` extended to describe the vault: folder layout, `[[wikilink]]` style, the paper-
      note template, where new notes go.
- [ ] Link resolution: follow org→vault links and `[[wikilinks]]` to pull context.
- [ ] The flagship workflow `orgllm-paper-to-note` end-to-end.
- [ ] An end-to-end eval of that workflow on sample papers.

---

## 7.3 Reused libraries / tools

| Need | Tool |
|---|---|
| Agent over both roots | **Claude Code / Agent SDK** (via `claude-code-ide.el`), or gptel tool-use with FS read/write tools |
| Web fetch (paper) | agent's web-fetch tool (Claude Code), or a `plz`-based fetch tool in elisp |
| Org operations | Stage-3 tools (`emacsclient` / gptel) |
| Vault ops (optional) | Obsidian MCP (`mcp-obsidian` via Local REST API: `get_file_contents`, `search`, `patch_content`, `append_content`, …) |
| Vault templates (optional) | `obsidian-mcp-tools` (Templater execution, semantic search) |

---

## 7.4 The flagship workflow — `orgllm-paper-to-note`

Trigger from an org task that is a paper link (you have *many* such "tasks-that-are-really-links").
Steps (an agentic loop with tools):

1. **Read the org task** (title, URL, any notes) — Stage-3 `get-node`.
2. **Fetch** the paper/abstract from the URL (web-fetch tool).
3. **Create an Obsidian note** in your paper template (title, authors, summary, key ideas,
   relation to your work) — FS write into the vault's papers folder, `[[wikilink]]`-consistent.
4. **Gap analysis vs your learning plan:** read the relevant org learning-plan subtree (and, if
   Stage 6 is built, semantic-search the vault for related notes); identify missing prerequisites
   or adjacent topics.
5. **Propose follow-up org tasks** (e.g. "read prerequisite X", "implement Y") and a **link** from
   the org task to the new vault note — via Stage-3 `capture`/`refile`, all behind preview.

Output is a single reviewable proposal: the new note (FS diff) + the proposed org edits (batch
tool-calls). You approve as a unit.

```elisp
(defun orgllm-paper-to-note ()
  "From the org paper-link at point: fetch, write a vault note, find gaps, propose tasks."
  (interactive)
  (let ((node (orgllm-tool-get-node (org-id-get-create))))
    (orgllm-workflow-run orgllm-paper-to-note-system
                         (orgllm-prompt-fill 'paper-to-note node)
                         orgllm-crossbase-tools)))  ; web-fetch + vault-write + org tools
```

This one workflow is the proof of the whole "one agent, two roots" thesis and the single most
valuable cross-border feature for your usage pattern.

---

## 7.5 Link resolution

Make the agent able to traverse the link graph both ways:
- **org → vault:** resolve `[[file:...]]`, `[[id:...]]`, and plain vault paths referenced in tasks;
  expose `read_vault_note(path-or-title)` as a tool.
- **vault wikilinks:** resolve `[[Note Title]]` to a file; follow 1–2 hops for context (the
  lightweight personal-graph approach — no GraphRAG).

A task that says "read [[Attention Is All You Need]]" should let the agent open that note; an
org task that is *about* a vault note should let it update both sides coherently.

---

## 7.6 Obsidian MCP — when (and whether) to add it

Default: **skip it.** FS access + `AGENTS.md` conventions cover ~90%. Add an Obsidian MCP server
later only if you want:
- **heading-relative patching** (`patch_content`) so the model edits precisely without whole-file
  rewrites;
- **tag operations** (vault-wide rename/add) with Obsidian semantics;
- **template execution** (`obsidian-mcp-tools` runs Templater) so new notes match your templates
  exactly;
- **Obsidian-native search / link graph** without re-implementing it.

Trade-off: MCP needs the Local REST API plugin and a running Obsidian; its search is weaker than
ripgrep and it can't compose with shell tools. So treat it as a precision-write convenience, not
the access mechanism.

---

## 7.7 Privacy across the border

The Tier-L gate (Stage 1) still applies: never send `Health.org`/`Financial.org` content across to
a cloud model even in a cross-base workflow. Most paper/learning content is Tier-C, so this rarely
binds — but the gate is enforced in code, and cross-base prompts are assembled through
`orgllm-request` so they inherit it.

---

## 7.8 Optional / alternative implementations

- **gptel-tools vs Claude Code** for the flagship workflow: build it first with Claude Code (web
  fetch + FS + your `emacsclient` org tools, ediff review) since it's open-ended; later port the
  bounded version to an in-Emacs gptel loop if you want it fully native. Compare quality/effort.
- **Note templates as data:** keep the paper-note template as a file the agent reads, so changing
  the format doesn't require code changes.
- **Reverse workflow:** "I just wrote a vault note on X — propose org tasks/goals it implies."

---

## 7.9 Python? — No (unless you reuse Khoj for vault semantic search).

The workflow is agent + FS + org tools. Vault *semantic* search, if you want it here, reuses Stage
6's pipeline or Khoj — no new Python beyond that decision.

---

## 7.10 Evaluation for this stage

- **End-to-end on sample papers:** a small set of paper URLs with a reference "good note" + the
  set of "reasonable follow-up tasks." Score the note with an LLM-as-judge rubric (faithfulness,
  format adherence, no hallucinated claims) and the task proposals against the reference set
  (precision/recall).
- **Link integrity:** test that created links resolve both directions (org↔vault) and that no org
  `:ID:` is broken.
- **Privacy:** test that a Tier-L file injected into a cross-base prompt is refused for cloud.

---

## 7.11 Definition of Done

- [ ] Agent runs over both roots with Tier-L exclusions; `AGENTS.md` describes the vault.
- [ ] `orgllm-paper-to-note` works end-to-end with a single reviewable proposal.
- [ ] org↔vault link resolution tools live; links created by the workflow resolve both ways.
- [ ] End-to-end eval on sample papers recorded; privacy gate tested across the border.

---

## 7.12 Risks / notes

- **Dropbox conflicts:** run write-enabled cross-base jobs on one machine; save+sync first.
- **Hallucinated paper claims:** require the note to cite the fetched text; flag unsupported
  statements; keep the faithfulness rubric in eval.
- **Vault scale:** for vault *retrieval* prefer ripgrep (fast, exact) or Khoj (semantic, maintained)
  over loading many notes into context — the vault is too big to dump.
