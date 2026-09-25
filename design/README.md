# Design notes

Why this configuration is built the way it is: the problems each part solves,
the decisions taken, the alternatives that were tried or rejected, and what is
not built yet. These notes are for anyone changing the code, including the
author coming back to it months later. For how to *use* the features, see the
user documentation in [`docs/`](../docs/Index.org).

## What lives where

| Place | Holds |
|---|---|
| [`docs/`](../docs/Index.org) | What a feature does, and how to use and customize it. |
| `design/` (here) | The *why* that outlives any one function: evidence, product decisions, rejected alternatives and their reasons, shared principles, what is not built yet. |
| `;;; Commentary:` in `lisp/*.el` | The local *how*: what the code does, and which line must not be replaced and why. |
| `* Settings` in `config.org` | What each option does. |

Rule of thumb: if the explanation would still be needed after the module was
rewritten, it belongs here; if it explains a particular piece of code, it
belongs next to that code. A note links to the module's Commentary rather than
repeating it.

## Writing a note

```markdown
# Title

One or two sentences: what this is about.

**Status:** built | partly built | planned | research | retired
**Code:** `lisp/ps-<module>.el`; settings block `** <Feature> (ps-<module>.el)`

## Problem
## Decisions                — each with its reason
## Rejected                 — each alternative, and why it lost
## Constraints and traps    — only those that span modules
## Not built yet
```

- Describe the current state, not the story of getting there: no dates,
  incident diaries, test-run counts or chat. When something is replaced, say
  in one line what replaced it and why, and add the change to `history.md`.
- Name functions and settings so a reader can search for them; avoid line
  numbers, which go stale.
- Keep examples neutral: no real task titles or private paths.
- One topic per note; lowercase, hyphenated file names.

## Contents

Notes marked *planned* are not written yet. Notes marked *to rewrite* still
hold their original draft (a pre-build plan, a chat, or an investigation log)
and are being brought into the shape above.

### Overview

- `architecture.md` — *planned.* How the pieces fit: the loading chain,
  `config.org` versus `lisp/`, the settings layers, load-order constraints,
  and the principles shared across modules.
- `history.md` — *planned.* The major changes of direction and why: packages
  replaced, approaches dropped.

### Foundations — `foundations/`

- `vaults.md` — *planned.* Several Org folders, one open at a time, switched at
  runtime without one vault's settings leaking into the next.
- `data-safety.md` — *planned.* Why edits are not lost: one save path,
  reverting, file watching, git sync, and living alongside Dropbox.

### Planning — `planning/`

- [`agenda-views.md`](planning/agenda-views.md) — What each planning view is
  for, how the views are wired into `org-agenda`, and the week and month
  options that were considered.
- [`agenda-layout.md`](planning/agenda-layout.md) — How each agenda line is
  rebuilt into aligned columns with badges.
- [`schedule-view.md`](planning/schedule-view.md) — The Schedule section drawn
  as a timeline or a list of events instead of Org's time grid.
- `situations.md` — *planned.* Context tags and the saved searches built on
  them.
- [`capture-chat.md`](planning/capture-chat.md) — *to rewrite* (a prompt). To
  become `capture.md`, or be dropped in favour of the info-triage project.

### Editing — `editing/`

- [`blank-line-recovery.md`](editing/blank-line-recovery.md) — Restoring the
  blank lines mobile Org apps strip, from the file's git history.
- [`typo-checker.md`](editing/typo-checker.md) — High-precision, multilingual
  spell checking.
- `org-display-fixes.md` — *planned.* The font-lock and display fixes in Org
  buffers, which can break one another.

### Interface — `interface/`

- [`typography.md`](interface/typography.md) — Fonts by role, and which
  surfaces can use a proportional font.
- [`mode-line.md`](interface/mode-line.md) — The planning-focused mode line:
  what it shows, and everything it leaves out.
- [`scroll-indicator.md`](interface/scroll-indicator.md) — The auto-hiding
  scroll indicator that replaces the native scroll bar.
- `icons.md` — *planned.* The Material Symbols icon pipeline shared by the
  agenda, the file tree and the folder listing.

### Files and windows — `files-and-windows/`

- [`file-tree.md`](files-and-windows/file-tree.md) — *to rewrite* (covers the
  width only so far). The treemacs side panel and the workarounds it needs.
- `windows.md` — *planned.* Which window a view opens in, and why side panels
  never count.
- `opening-and-navigation.md` — *planned.* One dispatcher for opening files,
  how clicks are handled, and back/forward history.

### AI — `ai/`

- [`claude-code-panel.md`](ai/claude-code-panel.md) — *to rewrite* (a prompt
  and two investigation logs). Claude Code in a side panel.
- [`agent-context.md`](ai/agent-context.md) — What an AI agent is told about
  the Org conventions, and how that stays in sync with `config.org`.
- `in-emacs-llm.md` — *planned.* The gptel and semantic-search experiment, and
  why it was set aside (the code is kept at the `archive/llm-integration` tag).

### Platform — `platform/`

- [`macos.md`](platform/macos.md) — macOS-specific behaviour: the freeze fixed
  by the patches in [`patches/`](../patches/), the habits that keep its exposure
  low, and the platform facts other modules depend on.
- `upstream-workarounds.md` — *planned.* Every workaround for a bug in Emacs or
  a package: the bug, how to tell it has been fixed, and how to remove the
  workaround.
