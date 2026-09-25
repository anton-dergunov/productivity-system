# Mode line

A mode line that shows only what matters for planning: which document, where in
it, and which section, and nothing an editor for programmers would show.

**Status:** built
**Code:** `lisp/ps-mode-line.el`; the file tree's line in `lisp/ps-file-tree.el`
and `lisp/ps-git-sync.el`; the open-task count from `lisp/ps-task-count.el`;
back and forward buttons from `lisp/ps-nav.el`. Settings block
`** Mode line (ps-mode-line.el)`. User docs: `docs/Agenda.org` → "The mode
line", and `docs/Files-and-navigation.org` → "The mode line outside your
plans".

## Problem

Emacs's default mode line answers a programmer's questions: encoding, line
endings, the git branch, the major mode and a list of minor-mode lighters. None
of that means anything in a planning setup that edits Org files, reads an
agenda and browses a file tree; the aim was something closer to Obsidian or a
dedicated planning app.

## Principles

- **Every item must justify its space.** What is obvious or rarely needed goes.
- **Don't repeat global state in every window.** Sync status is the same for the
  whole vault, so it is shown once, in the file tree's mode line.
- **Answer three questions**: which document am I in, where in it, and which
  section.

## The shapes

```
plan file     Inbox · 12 · 38% · Projects > Website > Launch checklist
planning view Agenda ▾ · ⚠ 2 conflicts
              Tasks ▾ · 64%
anything else ~/notes/reading/index.md • · 14%
file tree     Focus ▾ 📅 ✓ Sync
```

**Plan file**: name, open tasks, position, heading breadcrumb. **Planning
view**: its name as a menu of views; the Agenda adds a clickable conflict count,
Tasks its position. **Anything else**: the abbreviated path and an unsaved mark.
**File tree**: the file-set selector, whether the set also filters the agenda
(📅), and the sync state.

## Decisions

**A plan file is one the agenda scans** (`ps/org-files-in-scope-p`), not any Org
buffer. The capture queue, this repository's documentation and `config.org` are
Org too, but a task count and a heading path mean nothing there; what those need
is to say which file they are, so they get the third shape with its path.

**The file name drops `.org`**, in the mode line and the frame title alike: every
plan is an Org file, so the extension says nothing. When two open files share a
name, the folder is added in front (`Personal/Inbox`).

**Position is a percentage only.** The line-number gutter already shows the line,
and a column number has no use in a planning document.

**The breadcrumb is heading titles only**: no keyword, priority, tags or
cookies. When the line is too long, breadcrumb segments are shortened one at a
time, longest first. The file name and position are never shortened.

**No save mark for plan files.** They are saved automatically and reverted when
they change on disk (see [data-safety.md](../foundations/data-safety.md)), as in
Obsidian. Anything else, such as a Markdown note, gets `•` until it is written,
because nothing saves it for you and an edit could otherwise sit unwritten with
no sign of it.

**No lighters, encoding, line endings, branch or read-only marker**, anywhere.

**Views are named by purpose**: "Agenda", "Calendar · Week", "Tasks",
"Situation · On foot", not Org's "Org Agenda" or "All". Every view title is
clickable (`▾`) and opens the same menu of views as Productivity → Plan & Review
(`ps/mode-line-view-menu-items`, the single definition both use). The Agenda
shows no position, to stay compact; Tasks shows it, because that list gets long.

**Sync state keeps its words.** "✓ Sync", "Syncing", "Sync Off", "Conflicted
Copies", "Sync Retrying" and "Sync Failed" always carry a text label: icon-only
states proved hard to remember. Only the problem states get a warning or error
face. The last successful sync time is in the tooltip rather than on the line,
where it would be noise.

**One separator**, `·` (`ps/mode-line-separator`). Selectors use `▾`, without
brackets, so the file tree's selector matches the view titles.

**The frame title** is the buffer's short name; the Claude Code session shows as
"Claude Code".

**Mouse-2 and mouse-3 on the mode line do nothing.** By default they delete
other windows or the window itself, which is easy to trigger by accident.

## Constraints and traps

- **Two mode lines coexist.** Plan files set the planning line buffer-locally;
  everything else uses the *default* `mode-line-format`, set once rather than
  per mode, because a list of modes is wrong the first time an unlisted one is
  opened. Every deliberately styled buffer (agenda, file tree, Claude panel,
  Availability, Conflicts) sets its own. The default is built from a constant,
  so reloading the config cannot stack segments.
- **Back and forward buttons go in both lines** (`ps/mode-line--with-nav`), or
  they work in only half the frame, and they stay outside the per-window cache
  below, which navigation does not invalidate.
- **The plan-file line is cached per window**, keyed on the line, the buffer
  name and the task-count generation. The name is in the key because `uniquify`
  renames an open buffer when a second file of the same name opens; the
  generation because the count updates from an idle timer without point moving.
- **The generic line does no file I/O.** It runs in every window on every
  redisplay, so it uses string operations only (`abbreviate-file-name`), and it
  is wrapped in an error guard, since a failure there breaks every window.
- **Counts are owned by the mode line and filled by other modules.** The mode
  line declares the task count and conflict count variables;
  `ps-task-count` and the conflict check fill them.

## Rejected

- **Save state for plan files** (above).
- **A line number next to the percentage**, since the gutter shows it.
- **An absolute or relative sync time on the line**, and **icon-only sync
  states** (above).
- **Brackets around selectors.** Cleaner without, and consistent with the view
  titles.

## Not built yet

- **A file selector on the name**: clicking the file name would open a menu of
  the vault's hierarchy, folders and files, replacing buffer cycling.
- **Heading navigation**: clicking a breadcrumb segment would list its sibling
  headings and jump to the one chosen.
