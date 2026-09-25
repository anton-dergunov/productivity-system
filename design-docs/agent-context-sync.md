# Flowing config.org conventions to the AI assistant

Internal design note. Not user documentation.

## Problem

`config.org` is the single source of truth for how tasks are represented in this
system: the TODO keyword set (`org-todo-keywords` = `TODO NEXT INPR WAIT MAYB DONE`),
priorities (Org defaults A/B/C), the directory the agenda scans (the Org base
directory itself, per `ps/org-files-root`),
tags, and timestamp conventions. When the Claude Code assistant edits the user's Org
files it needs those facts — otherwise it guesses (e.g. inventing an internal todo
list, or writing to a file that does not exist).

We want a way to make those conventions available to the agent that satisfies three
goals at once:

1. **One source of truth** — no second place that can silently drift from `config.org`.
2. **Near-zero per-session token cost** — nothing large re-read on every session.
3. **Low maintenance** — ideally no manual step a human must remember.

The agent's domain-level prose (what "task" means, disambiguation defaults, boundaries)
lives in a hand-written `AGENTS.md` and rarely changes; that part is settled. This note
is only about the *enumerable, drift-prone facts* above.

## The design space

Three independent axes:

- **Where the knowledge lives at read time:** static auto-loaded markdown · a file read
  on demand · tool schemas · behind a tool (Emacs computes the answer).
- **How it is kept in sync:** hand-maintained · generated (codegen) · never duplicated
  (computed at runtime).
- **Whether the agent manipulates raw Org text or calls semantic operations.**

## Options

### 1. Generated conventions block in AGENTS.md (codegen)

An Emacs function reads the *live* values and writes them into a delimited region of
`AGENTS.md` (`<!-- BEGIN ps-generated --> … <!-- END -->`).

- Refresh on **Emacs startup**, on `ps/reload-config` (F10), and on tangle.
- **Write only when the rendered block actually differs** from what is already on disk,
  so `AGENTS.md`'s mtime is untouched when nothing changed (matters for file-sync tools
  like git auto-sync / Obsidian sync).

**Pros:** `config.org` stays the only source; `AGENTS.md` is static and auto-loaded, so
**zero per-session cost**; no manual sync; works for *any* agent that reads `AGENTS.md`,
not just Claude Code; the render function is pure and ERT-testable; nothing needs a
running Emacs at read time.

**Cons:** a regeneration step must fire on config change (covered by the
startup/reload/tangle triggers, optionally a CI drift check); still teaches *syntax*, so
the agent hand-edits text and can still err — but now fully informed.

### 2. Read config.org (or a slimmed extract) on demand

`CLAUDE.md`/`AGENTS.md` tells the agent to read the source each session.

**Pros:** truly single source if it reads `config.org` directly; no codegen.

**Cons:** **per-session token cost** every session; `config.org` is ~1800 lines of noisy
elisp; the agent may forget to read it. A "slimmed extract" file still has to be
generated — which collapses into Option 1, only read on demand instead of auto-loaded.
Dominated by Option 1.

### 3. MCP semantic tools (Emacs computes; conventions never leave Emacs)

Register tools like `org_add_task` / `org_set_state` / `org_list_tasks` / `org_query`
via `claude-code-ide-make-tool`. The agent calls a tool; the same Emacs code that powers
the UI applies `org-todo-keywords`, priorities, ordering, and logging.

**Pros:** **zero duplication** — conventions never leave Emacs; strongest correctness for
*mutations* (no syntax mistakes; can enforce invariants like ≤4-char keywords and valid
states); composes with `org-ql` for queries; reusable by other agents over MCP; enables
the "trigger an action" idea (capture, refile, archive).

**Cons:** only works while an Emacs + live session exists (no help for a headless or
other agent merely reading files); adds tool-schema tokens to *every* session (bounded,
modest); more code to write, test, and maintain; the agent may bypass the tools and
hand-edit unless steered; the claude-code-ide tools register globally for all sessions;
does not by itself teach the agent to *read*/understand conventions (only the tool
descriptions do).

### 4. Hardcode in AGENTS.md + drift test

Hand-write the values; an ERT/CI test fails if `AGENTS.md` and `config.org` disagree.

**Pros:** simplest to read and author; explicit; the test prevents silent drift.

**Cons:** **two sources of truth** — the exact thing we set out to avoid; every config
change needs a manual `AGENTS.md` edit; the test reports drift but does not fix it;
brittle as the convention set grows.

### 5. Hybrid

Static `AGENTS.md` prose (domain + disambiguation + boundaries) **+** a generated block
(Option 1) for the enumerable facts **+** optional MCP tools (Option 3) layered later for
high-value mutations / triggers.

## Comparison

| Option | Single source | Per-session cost | Maintenance | Mutation safety | Helps headless/other agents |
|--------|---------------|------------------|-------------|-----------------|-----------------------------|
| 1 Generated block | Yes (config) | ~0 (static) | Auto (on triggers) | No change (hand-edit) | Yes (reads file) |
| 2 Read on demand  | Yes | High, every session | Low | No change | Yes |
| 3 MCP tools | Yes (Emacs) | Modest (schemas) | Higher (code) | Strong | No (needs live Emacs) |
| 4 Hardcode + test | No (two) | ~0 | Manual edits | No change | Yes |
| 5 Hybrid (1+3) | Yes | ~0 + modest | Auto + code | Strong (for tooled ops) | Partly |

## Recommendation

Start with **Option 1 inside the Hybrid**: it meets the immediate need with the least
machinery and zero per-session cost, and has no prerequisites. Layer **Option 3** later
if hand-editing proves error-prone, or once we want the agent to *trigger actions*
(capture, refile, archive, schedule) rather than just edit text. Options 2 and 4 are
dominated.

Everything Option 3 needs already exists in-stack — `claude-code-ide-make-tool` plus the
Org API (`org-todo`, `org-set-property`, `org-capture`, and `org-ql` for queries) — so no
second MCP server is required. Standalone "org MCP" servers exist in the ecosystem but
would duplicate a server process and lose this config's awareness of the live settings.

## Sketch of the recommended first step (Option 1)

- A new module, e.g. `lisp/ps-ai-context.el`, with:
  - a **pure** `ps/ai-context--render-conventions` that takes the relevant values
    (keyword set, priorities, planning subdir, date format) and returns the markdown
    block — ERT-testable in isolation;
  - `ps/ai-context-sync` that reads the live values, renders the block, and **rewrites
    `<base>/AGENTS.md` only if the delimited region's content changed**.
- Triggers: call it from Emacs startup (after `config.org` loads), from
  `ps/reload-config` (F10), and from the tangle path.
- `config.org` keeps a small settings block per the project's `defcustom`-defaults
  convention if any knobs are exposed.

This is a follow-up implementation task; the decision recorded here is the input to it.

## What was actually built (2026-08-01)

Option 1, with one change of shape: the generated text is **its own file**, not a delimited
region inside `AGENTS.md`. `ps/ai-context-sync` writes
`<my-org-base-directory>/.claude/generated-context.md` (`ps/ai-context-file`), and
`AGENTS.md` — hand-written, never touched by Emacs — points at it in prose and with an
`@`-import line so Claude Code inlines it automatically.

Why the separate file beat the delimited region:

- **Nothing rewrites a file the user authors.** Marker-splicing churns `AGENTS.md`, and a
  damaged marker pair silently disables the whole feature — which is exactly what happened:
  neither the real notes' nor the sample's `AGENTS.md` ever contained the markers, so the
  original implementation was a no-op from the day it shipped.
- **The generated file can be gitignored.** It is regenerated on every Emacs start, so
  there is nothing to track. This removes the standing annoyance that running
  `scripts/run_emacs_dev.sh` dirtied the checked-in `samples/realistic/AGENTS.md`.
- **Regeneration frequency stops being a trade-off.** Since no hand-written file is
  touched, it is free to also refresh on a debounced `after-save-hook`, which is what keeps
  the file index current.

The scope also grew by one item beyond the conventions: a **file index** built from each
scanned file's `#+SUBTITLE:` line, so the agent can route without opening every file. Same
argument as the conventions — it is an enumerable, drift-prone fact that already has a
source of truth (the files themselves), and it was previously hand-maintained inside
`AGENTS.md` under a comment claiming it was generated.

Option 3 (MCP semantic tools) remains the sensible next layer and is untouched by this.
