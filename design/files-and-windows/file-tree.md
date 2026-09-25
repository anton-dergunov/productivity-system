# File tree

The vault's folders and files in a side panel on the left, built on treemacs
and bent from a view of code projects into a calm navigator for Org notes.

**Status:** built
**Code:** `lisp/ps-file-tree.el` and `lisp/ps-file-tree-icons.el`; wired in
`config.org` → `** =treemacs= file tree`; settings block `** File Tree
(ps-file-tree.el / ps-file-tree-icons.el)`. User docs:
`docs/Files-and-navigation.org`.

## Problem

treemacs is built for code projects: a root line per project, git-status
colours, a follow mode that expands and re-roots the tree to reveal the current
file, and file names shown exactly as they are on disk. Here the tree is the
main way to move around a vault of plan files, so it should read like the
folder list in Obsidian: sections, clean names, and nothing moving unless the
user moves it.

## Decisions

**One project for the whole vault** (`ps/file-tree-root-mode` `single`), with its
root line hidden (`ps/file-tree-hide-root`), so the tree starts at the vault's
own entries and files at the top level are visible. The alternative, `subdirs`,
makes each top-level folder its own project with a bold label, but then files
directly in the vault appear nowhere. treemacs forbids overlapping projects, so
the two cannot be combined.

**Top-level folders are the section headers**: bold
(`ps/file-tree-bold-top-level`), with a thin strip above each
(`ps/file-tree-top-level-spacing`). The strip is an overlay `before-string`,
not a `line-spacing` property on the line above: `line-spacing` adds its space
*below* that line, so the previous entry's highlight would extend into it. The
overlay's priority is -100 so treemacs's fringe marker, which sits at the same
position, stays on the line rather than floating on the strip.

**Names read like titles**: `.org` is dropped and `_` shown as a space
(`treemacs-file-name-transformer`). The same function names files in the mode
line and the frame title, so `Deep_Learning.org` reads "Deep Learning"
everywhere.

**What the tree hides is a display choice**, separate from what the agenda
scans. `ps/file-tree-ignored-files` hides the configuration files next to the
notes, dotfiles and build output; the agenda's exclusions are in
`ps-org-files`.

**File sets** (`ps/file-tree-file-sets`) are named include and exclude filters
over paths, switched from the tree's mode line. By default a set only filters
the tree. With `ps/file-tree-set-applies-to-agenda` (shown as 📅) it also
restricts the agenda, Conflicts and Availability. The current set and that
flag persist across restarts.

**Order is alphabetical unless stated** (`ps/file-tree-order`): names before
`:rest` are pinned to the top, names after it to the bottom. treemacs always
draws folders before files, which no ordering can change.

**No git colours.** `treemacs-git-mode` is off: a modified file would otherwise
take the git face and lose its category styling.

**Follow only moves the highlight.** `ps/file-tree--follow` highlights the
current file if it is already on screen, and never expands a folder or
re-roots the tree, so the tree never shifts under you. treemacs's own follow
modes are off.

**One click opens a file** in the most recently used content window, never a
side or dedicated one (`ps/file-tree--target-window`). Excluding every side and
dedicated window, not just the tree, is what stopped windows multiplying when a
file landed in a dedicated window and Emacs split off another. The general
click model is in [opening-and-navigation.md](opening-and-navigation.md).

**External changes arrive three ways.** `treemacs-filewatch-mode` watches every
expanded folder, but only for files appearing and disappearing: plain content
changes are dropped while git mode is off, and a folder never expanded is not
watched at all. Git sync refreshes the tree after a pull that brought something
in. The header line's refresh button covers the rest.

**The width holds when the frame is resized, and the divider still drags.**
`ps/file-tree-width-setup` calls `window-preserve-size` on the tree window from
`window-size-change-functions` (`ps/file-tree-pin-width`):

- A preserved width makes `window-size-fixed-p` true for the C-level frame
  resize, so the columns go to the other windows.
- A divider drag goes through `adjust-window-trailing-edge`, which, when it
  finds nothing to resize, retries ignoring *preserved* sizes. So the drag
  works. `window-size-fixed` has no such escape.
- The record is a width, and lapses once the width changes, so the hook
  records the dragged width as the new one. `treemacs-width` is updated with
  it, and hiding and showing the tree keeps the user's width.
- Shrinking the frame past the tree's width clamps the frame at its minimum
  instead of shrinking the tree, so no restore logic is needed.

## Workarounds for treemacs

Each is load-bearing, and each exists because of a specific treemacs behaviour.
They are also listed in
[upstream-workarounds.md](../platform/upstream-workarounds.md).

1. **Decorations are re-applied after every render.** treemacs cannot draw a
   project without its root line, and fires no hook when a node is expanded or
   collapsed. `ps/file-tree--decorate` is one idempotent pass (hidden root, the
   leftover indentation, gaps, bold headers), run from
   `treemacs-post-buffer-init-hook`, `treemacs-post-refresh-hook`, a
   buffer-local `post-command-hook`, the tree's own expand and collapse
   commands, and after each batch of file-watch events, which refresh through
   a path that fires no hook. It changes no characters, so it does not bump the
   buffer's modification tick and cannot trigger itself.
2. **Follow never uses `treemacs-find-visible-node`.** Despite its name, that
   function falls back to `treemacs-find-node`, which expands ancestors,
   whenever a node's position is not cached, which is the usual case for a
   file. `ps/file-tree--visible-node-position` looks the path up in treemacs's
   node table, which holds only nodes currently drawn, and scans buttons for
   the position, so it doubles as a "is it on screen" test and never expands
   anything.
3. **Nodes are found by path, not by their label.** Because of the name
   transformer, a file's line no longer contains its file name.
   `treemacs-find-file-node` falls back to a `search-forward` per path
   component when a node's position is not cached, fails, and returns nil,
   which its callers do not check. Deleting a shown file from another app then
   hit `(goto-char nil)` inside treemacs's file-watch handler, killing its timer
   and leaving the deleted file on screen. `ps/file-tree-node-lookup-setup`
   advises it (`:before-until`) to match on the `:path` property instead. The
   advice answers only for nodes drawn right now; for anything else treemacs's
   own lookup still runs, since its job there is to expand ancestors.
4. **Deferred annotations skip nodes that were redrawn.** Expanding a folder
   arms a half-second timer holding the node's buffer position, and nothing
   checks that the node survived. Any re-render inside that half second (a
   refresh, or a vault switch, which re-renders several times) makes it signal
   `(wrong-type-argument number-or-marker-p nil)` once per expanded node.
   `ps/file-tree-annotations-setup` adds a `:before-while` guard that skips a
   position no longer carrying a node. Skipping costs nothing: the annotations
   are git status, which is off.

## Constraints and traps

- **Inside `window-size-change-functions`, find the tree per frame**
  (`ps/file-tree--frame-window`). `treemacs-get-local-window` consults the
  selected frame, and the hook can report a different one.
- **Keep the node-lookup advice narrow.** Answering for nodes that are not drawn
  would break treemacs's expand-to-reveal.
- **There is no `preserve-size` window parameter.** The real parameter is
  `window-preserved-size`, holding a recorded pixel size; call the function
  `window-preserve-size` rather than setting parameters by hand.

## Rejected

- **`window-size-fixed`**, which is what `treemacs-width-is-initially-locked`
  and `treemacs-toggle-fixed-width` set. It holds the width through frame
  resizes but kills dragging: the drag's search for a resizable window finds
  none and signals "No resizable window on the left of this one". Clearing it
  around a drag does not help, since every later motion event re-enters the
  same check, and treemacs's own configuration-change hook resets it.
- **Detecting a frame resize and resizing the tree back.** `window-resize`
  signals on a side window, and the error was being swallowed.
- **treemacs's follow modes** (above).
- **Neotree**, which the tree replaced in 2026. The commit records what the
  switch brought (per-category icons, hidden configuration files, a tree rooted
  at the vault) rather than what Neotree lacked.
