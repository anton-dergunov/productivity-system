# Upstream workarounds

Every place this configuration works around a bug or a limitation in Emacs or a
package: what goes wrong, where the workaround lives, and how to tell when it
can go. The notes linked from each entry have the full reasoning.

**Status:** a registry; update it whenever a workaround is added or removed.
**Code:** spread across the modules named below.

## How to use this list

Before upgrading a package, look up its section. When a workaround's "remove
when" condition is met, delete the workaround and its entry together. Only one
entry has a test that detects the upstream fix by itself (filenotify); for the
rest the check is manual.

## Emacs

**The macOS freeze.** `[NSApp run]` exits only when an application-defined
event comes back, and that event can be lost (no main window, or a focus
hand-over), with no recovery path.
*Workaround:* `patches/emacs-30-ns-appdefined-windownumber.patch` and
`-retry.patch`, applied by building patched Emacs.
*Remove when:* an Emacs release fixes the lost-event recovery.
([macos.md](macos.md))

**The frame title is replaced by the grid size during a live resize** (NS).
*Workaround:* `patches/emacs-30-ns-resize-title.patch` (cosmetic).
*Remove when:* upstream drops or makes optional the title rewrite.

**The line-number gutter flickers while pixel-scrolling** (NS:
`FRAME_SMALLEST_FONT_HEIGHT` is 1, so the width estimate counts pixels).
*Workaround:* `display-line-numbers-width` 2 as a minimum, in `config.org` →
`** Line numbers`.
*Remove when:* the estimate counts lines. ([macos.md](macos.md))

**The tool bar left painted over the buffer** (NS, macOS 26) when turned off
after the first frame exists.
*Workaround:* `early-init.el` sets `tool-bar-lines` to 0 before any frame.
*Remove when:* never; settings that must beat frame creation belong there.

**filenotify.el calls a nil callback.** One kqueue event can carry "deleted"
and "changed"; handling the first clears the callback, and the second calls nil.
*Workaround:* `ps/file-notify-setup` (`lisp/ps-file-notify.el`) skips a watch
whose callback is gone.
*Remove when:* `tests/test-ps-file-notify.el`, which asserts the bug is still
present, starts failing. ([data-safety.md](../foundations/data-safety.md))

**`mouse-drag-line` leaves the global `track-mouse` stuck** at `dragging`. It
restores the value with a plain `setq` in whatever buffer is current when the
drag ends; in a buffer with a local `track-mouse` (eat makes one) the global
value is never restored, and the pointer shape freezes everywhere.
*Workaround:* `ps/scrollbar--unstick-track-mouse` on `post-command-hook`.
*Remove when:* `mouse-drag-line` restores with `let` or `default-value`.

**Wheel events nothing binds.** A wheel event outside any window arrives as
`[nil wheel-up]`, and fast trackpad scrolling produces `double-` and
`triple-wheel-*` variants.
*Workaround:* global bindings in `config.org` → `** Smooth scrolling
(ultra-scroll)`.
*Remove when:* mwheel binds them. ([scroll-indicator.md](../interface/scroll-indicator.md))

**macOS `ls` has no `--dired`.**
*Workaround:* `config.org` → `** Workaround for unsupported =ls --dired= on
macOS` uses GNU `ls` when installed, and turns `dired-use-ls-dired` off
otherwise.
*Remove when:* never, on macOS without coreutils.

**A stale MELPA index names tarballs that no longer exist**, so installing a
new package fails with a 404 on any machine that already had an index.
*Workaround:* the package bootstrap in `config.org` refreshes the index once
per session, only after an install has failed.
*Remove when:* package.el retries on a 404 by itself.

## Org

**Half-typed heading stars are parsed as emphasis.** Org's guard needs a
complete headline, so `**` without its space turns bold and can hide the next
heading's bullet.
*Workaround:* `lisp/ps-heading-stars.el` binds `org-outline-regexp-bol` and the
emphasis regexps around `org-do-emphasis-faces`.
*Remove when:* Org's guard also covers star-only lines and bodies spanning into
a star-led line. ([org-display-fixes.md](../editing/org-display-fixes.md))

**`org-element-at-point` gets slower the deeper point is in a large section**
while the cache is off, and `org-appear` calls it on every command.
*Workaround:* the cache is re-enabled buffer-locally in Org buffers
(`config.org` → `*** Re-enable the org-element cache for live Org buffers`),
while staying globally off as a startup guard.
*Remove when:* the startup guard is no longer needed.

## org-modern

**Tag pills split when a headline wraps**, stranding a grey padding box, because
the padding is a literal space inside a display string.
*Workaround:* `lisp/ps-tags.el` turns those spaces into no-break spaces.
*Remove when:* org-modern pads with a display property that is not a space.

**TODO and priority pills vanish inside a selection**, because they use
`:inverse-video`.
*Workaround:* `ps/selection--flatten-face` (`lisp/ps-selection.el`) resolves the
inversion into plain colours.
*Remove when:* org-modern names a foreground for those faces.

**`org-modern-agenda` restyles badges the agenda layout already drew**, if a line
carries `org-todo-regexp` or `org-not-done-regexp`.
*Workaround:* `ps/agenda-layout--strip-display-props` leaves them out.
*Remove when:* never; it is an interaction between two passes, not a bug.
([agenda-layout.md](../planning/agenda-layout.md))

## org-appear with jinx

**The reveal collapses on every keystroke.** jinx's jit-lock function returns
nil, so jit-lock marks only the requested region fontified, and the rest of the
line is refontified after `org-appear` revealed the markers.
*Workaround:* `lisp/ps-appear.el` re-asserts the reveal at the end of each
font-lock region pass.
*Remove when:* jinx reports its bounds, or jit-lock stops intersecting.
([org-display-fixes.md](../editing/org-display-fixes.md))

## treemacs

([file-tree.md](../files-and-windows/file-tree.md) has the detail.)

**No way to hide a project's root line, and no hook after expand or collapse.**
*Workaround:* `ps/file-tree--decorate`, re-run from several hooks and commands.
*Remove when:* treemacs gains a hide-root option and a post-render hook.

**File-watch refreshes fire no refresh hook**, so decorations go stale.
*Workaround:* `:after` advice on `treemacs--process-file-events` in `config.org`.
*Remove when:* that path runs `treemacs-post-refresh-hook`.

**`treemacs-find-visible-node` expands ancestors** when a node's position is not
cached.
*Workaround:* `ps/file-tree--visible-node-position` looks nodes up without
expanding.
*Remove when:* the function stops falling back to `treemacs-find-node`.

**`treemacs-find-file-node` searches for the file name as text**, which fails
once the name transformer changed the label, and its callers do not check for
nil.
*Workaround:* `ps/file-tree-node-lookup-setup` advises it to match by `:path`.
*Remove when:* the fallback matches on `:path`.

**Deferred annotations act on a stale buffer position** after any re-render
within half a second of an expand.
*Workaround:* `ps/file-tree-annotations-setup` guards
`treemacs--apply-annotations-deferred`.
*Remove when:* treemacs checks that the node survived.

**treemacs's width lock blocks dragging the divider** (it uses
`window-size-fixed`).
*Workaround:* `ps/file-tree-width-setup` uses `window-preserve-size` instead.
*Remove when:* the lock uses a preserved size.

## eat

([claude-code-panel.md](../ai/claude-code-panel.md) has the detail.)

**Window positioning mixes buffer lines and screen lines** (`recenter` with a
count of buffer lines), and its scroll synchroniser abandons a window scrolled
up from the cursor.
*Workaround:* `ps/claude--synchronize-scroll` sets the window start directly.
*Remove when:* eat positions windows with `set-window-start`.

**A transient `args-out-of-range` from the output timer** when the diff window
first opens.
*Workaround:* `ps/claude--eat-output-guard` swallows it and schedules a resync.
*Remove when:* eat stops signalling it.

**Cmd-V is not sent to the terminal**: eat rebinds `C-y` but not `s-v`.
*Workaround:* `s-v` bound to `eat-yank` in eat's interactive keymaps.
*Remove when:* eat binds it.

## claude-code-ide

**The session's working directory is the project root**, which for a buffer in
this repository is the configuration's source tree.
*Workaround:* `claude-code-ide--get-working-directory` overridden to the vault.
*Remove when:* the package allows a fixed working directory.

**The selection lookup uses a different key from the session**, so the selection
never arrives.
*Workaround:* advice on `claude-code-ide-mcp--get-buffer-project`.
*Remove when:* both use the same key.

**Selection positions are 1-based, nothing is sent on connect, and nothing is
re-sent after the CLI clears it** at each prompt.
*Workaround:* `ps/claude--current-selection` and the re-assert logic in
`lisp/ps-claude.el`.
*Remove when:* the package sends 0-based positions on connect and on panel
focus.

**The reflow-glitch workaround for claude-code#1422 leaves the process at its
old size** after height-only resizes.
*Workaround:* a resync from `eat-term-size` once a resize settles.
*Remove when:* #1422 is fixed; then set `claude-code-ide-prevent-reflow-glitch`
nil. The resync can stay.

**Quitting asks about the session's processes**: accepted MCP websocket
connections do not inherit `:noquery`.
*Workaround:* `ps/claude-no-exit-prompt` clears the flags before exit.
*Remove when:* the package marks them itself.

## Behaviours designed around

These are not bugs, and the code around them is permanent. They are listed
because each has caught this configuration out once.

- **A side window is dedicated `side`, not `t`**, and `switch-to-buffer` refuses
  only `t` ([windows.md](../files-and-windows/windows.md)).
- **`push-button` does not move point on a mouse click**
  ([blank-line-recovery.md](../editing/blank-line-recovery.md)).
- **`window-buffer-change-functions`' default value is called with a frame**,
  not a window ([opening-and-navigation.md](../files-and-windows/opening-and-navigation.md)).
- **`mouse-1-click-follows-link` ignores a release that moved a few pixels**, and
  a bound `mouse-1` loses to `org-appear`'s reveal
  ([opening-and-navigation.md](../files-and-windows/opening-and-navigation.md)).
- **`string-width` counts invisible characters**
  ([org-display-fixes.md](../editing/org-display-fixes.md)).
- **`:inherit` resolves through face remapping**, so heights multiply
  ([org-display-fixes.md](../editing/org-display-fixes.md)).
- **Ediff:** its copy commands bind `inhibit-read-only`, it does not restore
  `buffer-read-only`, it opens with no difference selected, and
  `ediff-setup-windows-plain-compare` calls `delete-other-windows`
  ([blank-line-recovery.md](../editing/blank-line-recovery.md)).
- **`eval-after-load` forms run in registration order**, so a later `setq` of
  `org-agenda-custom-commands` wipes earlier entries
  ([situations.md](../planning/situations.md)).
- **`org-agenda-redo` calls `recenter`**, so a refresh needs the agenda's window
  selected ([agenda-views.md](../planning/agenda-views.md)).
