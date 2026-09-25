# In-Emacs LLM client and semantic search

An experiment with an LLM client inside Emacs (gptel) and semantic search over
the notes, and why it was set aside in favour of Claude Code in a panel. The
code is kept, frozen, for a possible return.

**Status:** retired (kept on the `archive/llm-integration` tag)
**Code:** not on the main branch. The tag holds `lisp/ps-gptel.el`,
`lisp/ps-org-db.el`, `scripts/keep_to_org.py`, `scripts/setup-org-db.sh`, their
tests, a staged plan in `plan/` and `docs/semantic-search-eval.org`. The branch
is from June 2026 and far behind main, so any return means bringing the modules
forward by hand, not rebasing.

## What was tried

**gptel as the client**, with Claude as the default backend and Gemini and
Ollama as alternatives, and three tools that let the model see the notes:
`list_notes`, `read_note` and `search_notes` (ripgrep over the vault).

**A staged plan** (`plan/index.md`) for a full assistant over the notes, built
mostly in Emacs Lisp. It set nine kinds of question as the target: review a
subtree, rewrite text, restructure, prioritise, search across files, summarise,
enrich with metadata, check consistency, align with goals. Its central idea was
that the interaction surface, the knowledge in scope, and the agent's tools are
three independent axes, so any client is "just a face". Its principles: never
write without review, send the smallest context that works, reuse existing
libraries, keep sensitive files on a local model, and evaluate everything.

**Semantic search**, evaluated against the ripgrep baseline on the sample notes
(`docs/semantic-search-eval.org`):

- **ripgrep**: instant and free, but purely lexical. "Things I want to do to
  improve my sleep" does not find "Reduce caffeine after 15:00".
- **org-db-v3**: a local FastAPI server with SQLite full-text and vector
  indexes, fed by an Emacs client that parses Org with `org-element`. It found
  exactly the concept matches ripgrep misses, indexed the sample notes in
  seconds, used about 180 MB of memory and answered in under a second, and
  already had gptel tool integration. Recommended.
- **Khoj**: a full "second brain" application (Django, its own web UI,
  scheduling, model management). Not installed: its dependencies and disk
  footprint were far beyond what search over one vault needs, and gptel already
  provided the chat layer.

## Why Claude Code instead

Claude Code in a side panel ([claude-code-panel.md](claude-code-panel.md))
covered the main need better, for three reasons:

- **It already sees the files.** Nearly every useful question about plans needs
  the context of several files. gptel sees nothing until tools are built for
  it, and building good ones is most of the plan above; Claude Code reads,
  searches and edits the vault as it is.
- **Its edits arrive as diffs to review**, which matched the plan's first
  principle without building a review harness.
- **Its conventions come from files**, so one generated context file
  ([agent-context.md](agent-context.md)) tells it how tasks are written, with
  no tool schemas.

What gptel did better, and what was given up:

- **Quick, inline, stateless requests**: rewriting a selection or asking one
  unrelated question. Claude Code is slower and heavier for that.
- **A choice of model**, including cheap and local ones, where Claude Code is
  one vendor.
- **The cost model**: gptel's usual path is a metered API key.

## What would make it worth revisiting

- A need for fast inline rewriting or one-off questions that the panel handles
  poorly.
- A local model for sensitive files, or a much cheaper model for bulk work such
  as triage.
- Concept search that neither ripgrep nor Claude Code's own searching provides
  well enough. org-db-v3 was the chosen option.

If it comes back, the pieces most worth keeping are the note tools, the
org-db-v3 integration and the plan's review-before-write principle. The plan's
model names and costs are from mid-2026 and will be out of date.
