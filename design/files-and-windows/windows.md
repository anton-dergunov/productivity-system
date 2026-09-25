# Windows

Which window a view or a file opens in: the shared rule that planning views and
followed links obey, and why side panels never count.

**Status:** built
**Code:** `lisp/ps-window.el`; used by the agenda wiring in `config.org`
(`ps/window--split-if-alone-advice`, `ps/window--inhibit-split-advice`),
`ps-open`, `ps-nav`, the Availability and Conflicts views, blank-line recovery,
the vault welcome screen and Info Triage. User docs:
`docs/Files-and-navigation.org` → "Window management".

## Problem

Emacs's default is to put a new buffer "somewhere": it may split the frame,
reuse another window, or replace the one you are in, depending on how many
windows are open and what `display-buffer` concludes. Org's agenda adds its own
logic on top (`org-agenda-window-setup`). The result was a layout that changed
unpredictably each time a view opened, and windows that multiplied.

## Decisions

**A content window is any window that is not a side window.** The file tree and
the Claude Code panel are side windows (they carry the `window-side`
parameter): persistent docks that the rules below never take over, split or
count.

**Planning views take over the selected window**, leaving every other window's
buffer, split and size alone. The Agenda, Calendar, Tasks, Availability and
Conflicts all follow this (`ps/window-show-here`); for the agenda it is
`org-agenda-window-setup` `current-window`.

**...except when the selected window is the only content window**, in which case
it is split first, so what was already on screen stays visible beside the new
view (`ps/window--split-if-alone`). "Split when alone" needs no setting to get
the common cases right: with one window, a view opens beside your file; with
Claude Code already in the other half, it replaces the window it was opened
from.

**A refresh never splits.** Rebuilding a view that is already on screen
(`org-agenda-redo`, or the agenda building its blocks) would otherwise add a
window on every redo (`ps/window--inhibit-split-advice`,
`ps/window--building-agenda-block-p`).

**Stepping through something never splits.** Following a trail (the Info Triage
queue into an item's index, into its folder, into a file) should not add a
window at each step, so those use `ps/window-replace-here` and
`ps/window-visit-only-here`. So does going back, since a step backwards that
adds a window is not a step backwards.

**A list that should stay on screen opens things beside it.** A buffer that
sets `ps/open-keep-window` (the Info Triage queue does) sends what it opens to
the most recently used *other* content window (`ps/window-visit-beside`), so the
list stays where it is while you look at what it lists. Using the most recently
used one keeps several links in a row landing in the same pane.

**The Claude Code panel is a deliberate exception**: it stays a side window that
docks right or bottom by frame shape
([claude-code-panel.md](../ai/claude-code-panel.md)).

**Transient choosers go to the bottom.** The agenda dispatcher and the calendar
date picker are shown as a short full-width strip at the bottom
(`display-buffer-alist`), always in the same place. The dispatcher's own
`delete-other-windows` is suppressed while it is up, so choosing a view does not
collapse the frame.

## Constraints and traps

- **A side window is dedicated with the value `side`, not `t`**, and
  `switch-to-buffer` refuses only `t`. So opening a view while the file tree is
  selected silently replaced the tree inside its own narrow slot, which looked
  as though the command had done nothing; pressed again, it worked.
  `ps/window--select-main` selects a content window first, and every helper
  calls it.
- **Split before noting the departure**, in `ps/window-visit-here`. The split
  selects a new window still showing the old buffer; noting afterwards records
  the step in the window that is about to leave, so back returns the right
  window.
- **`ps-window` stays a leaf.** Its link to navigation history is soft
  (`fboundp`), so the window rules never depend on `ps-nav` being loaded.
- **Only split when the current buffer is actually visible**
  (`ps/window--current-buffer-visible-p`); otherwise there is nothing to keep on
  screen.

## Rejected

- **Org's default `reorganize-frame`.** It bypasses `display-buffer-alist` with
  its own logic, which is why the agenda sometimes split and sometimes replaced
  a window.
- **Showing `*Org Agenda*` at the bottom through `display-buffer-alist`.** An
  earlier plan; the take-over rule replaced it.
