# Capture

How captured material reaches the plans. Capture itself is a separate project;
this configuration is where captured items are reviewed and filed, and where
the rule for what may enter the plans at all is applied.

**Status:** partly built
**Code:** `lisp/ps-info-triage.el` (the review queue, `C-c p I`); settings block
`** Info triage (ps-info-triage.el)`; `C-c p k` for Org's own capture. The
capture pipeline is the separate `info-triage` project, whose own design notes
cover everything upstream of the queue. User docs: `docs/Info-triage.org`,
`docs/Capture-and-journal.org`.

## Problem

Capturing was never what failed: links, notes and messages piled up in several
places faster than anything consumed them, and the plans themselves drifted
into lists of links to read. What was missing was a queue that is actually
worked through, and a rule for what belongs in a plan.

## Decisions

**Capture lives in its own project.** `info-triage` takes material forwarded from
a phone, extracts it on a home server, and delivers one folder per item to the
laptop, with two generated views of the queue: `triage.md` for an agent and
`triage.org` for the person. This configuration only reads that queue, and hides
the feature entirely when the inbox folder does not exist.

**Act, Keep or Drop, decided by intent, not size.** The Org plans hold what you
will *do* (the verb); only those items reach the agenda. What you want to find
again (the noun) goes to the notes vault in Obsidian, as a link inside a topic
note, and a plan task links to that note rather than holding the material
(`[[obsidian:…]]`, inserted by `ps-links`). A book or course becomes a plan task
plus one linked note; a small article becomes a link in a topic note; anything
that belongs nowhere is dropped. These rules live in the vault's own agent
instructions and a routing skill, not in code here.

**An agent proposes; the person decides.** Items are filed by Claude Code working
in the vault from the side panel ([claude-code-panel.md](../ai/claude-code-panel.md)),
which proposes where each item goes and waits for approval. An in-Emacs LLM
pipeline was designed for this first and set aside
([in-emacs-llm.md](../ai/in-emacs-llm.md)).

**The review queue is read-only and generated.** `triage.org` is rebuilt
wholesale on every sync, so nothing typed into it would survive; making it
read-only also frees single-key bindings, so the queue behaves like a folder
listing. Following an item opens it beside the queue, which keeps its window
([windows.md](../files-and-windows/windows.md)). Deleting an item's folder is
what "processed" means, and it goes to the Trash.

**Item content stays in Markdown; Org is used only to navigate.** Extracted text
is not safe inside Org markup, so the queue is an Org outline of links, and the
item itself is `index.md` in its folder.

**`Inbox.org` and `org-capture` remain the path with no dependencies**, for
anything typed on the laptop, and are filed through the same decision step.

## Constraints and traps

- **The two views share a numbering, and that is the whole interface.** The
  person reads an item's number in `triage.org` and quotes it to the agent that
  reads `triage.md`. Both number items positionally, so removing one renumbers
  everything after it: dropping an item regenerates *both* views before the
  queue is reverted (`sync.sh --regenerate`).
- **The queue's shape is a contract between the two repositories**: a level-one
  heading per day, items at level two, numbers global across days, and each
  item's folder recoverable only from its `directory` link
  (`ps/info-triage--item-directory` is the one place this side depends on it).
- **Keywords stay at four letters or fewer**, so an inbox state cannot be a new
  keyword such as `INBOX`.
- **`Inbox.org` is scanned by the agenda**, like any plan file, so what sits in it
  shows up there until it is filed.

## Rejected

- **An `Inbox.org` entry format with its own keyword and properties** as the
  landing place for everything captured: the keyword breaks the four-letter rule,
  and Org is not safe for extracted text.
- **Labelling an item's area and reading mode at capture time.** Choosing a
  destination is the decision step itself; asking for it while capturing moves
  the hard part to the worst moment.
- **A daily LLM digest with one-line summaries.** A summary hides how good the
  source is and looks complete when it is not; a truncated lead is honest.
- **Reviewing on a tablet or in a web app.** The review happens in Emacs, beside
  the agent that files.
- **A separate reading-queue file** for long reads.

## Not built yet

- **Capture templates** for `C-c p k`; Org's plain `org-capture` is used as it is.
- **Working the other capture routes from Emacs**, beyond the main inbox.
- **A clipper workflow** for material worth saving whole.
