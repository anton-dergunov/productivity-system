# File View width behaviour

Internal design note. Not user documentation. Modules: `lisp/ps-file-tree.el` →
`;;; Window width`, wired from `config.org` → `** =treemacs= file tree`.

**Status: solved.** See "The solution" at the end. The failed attempts are kept
because they map out the dead ends, and because attempt 4 was the right idea
executed wrongly.

## Goal

The File View (treemacs left-side window) should keep its width fixed when the
Emacs **frame** is resized (dragging the OS window border), while still allowing
the user to manually resize it by dragging the vertical divider.

Manual resizing works fine (`treemacs-width-is-initially-locked nil`). The
problem is that frame resize proportionally redistributes horizontal space to all
windows, including treemacs.

## What we established about the environment

- Treemacs creates its buffer as a proper **left side window**
  (`(window-parameter w 'window-side)` → `'left`).
- `treemacs-width-is-initially-locked = nil` causes treemacs to register a
  `window-configuration-change-hook` handler that **explicitly sets
  `window-size-fixed = nil`** in the treemacs buffer on every window
  configuration change (including frame resizes).
- `mouse-drag-vertical-line` calls `mouse-drag-line` internally, which on a
  left side window raises `user-error: No resizable window on the left of this
  one` if `window-size-fixed = 'width` is set in the buffer.  The `IGNORE`
  argument that would bypass this is **not** passed by `mouse-drag-line` for
  the resize check itself (only the minimum-size check is bypassable via
  `IGNORE`).

## Approaches tried and why each failed

### 1. `window-size-change-functions` — detect and restore

Detect frame resize by comparing `frame-pixel-width` against a saved value.
When it changes, call `(window-resize tw delta t)` to push treemacs back to
the saved column count.

**First implementation bug:** used `(treemacs-get-local-window)` which queries
`selected-frame`, not the frame argument passed to `window-size-change-functions`.
When the hook fires for a non-selected frame, the function returned nil and no
restore happened.

**Fixed implementation** (`get-buffer-window buf frame`) + a `resize-pending`
flag to prevent the follow-up hook invocation (triggered by our own
`window-resize` call) from being misread as a user drag.

**Why it still failed:** `window-resize` **silently errors on side windows**.
It raises an error for horizontal resize of a left side window, which
`ignore-errors` swallowed. The treemacs window was never restored.

### 2. `window-size-fixed = 'width` in `treemacs-mode-hook`

Setting the buffer-local `window-size-fixed` to `'width` makes
`resize_frame_windows` (C-level) skip the window entirely when distributing
horizontal space. This **did work** for frame resize — confirmed by the user.

**Problem:** `mouse-drag-vertical-line` → `mouse-drag-line` raises
`user-error: No resizable window on the left of this one` when
`window-size-fixed = 'width` is set. Manual resize was completely broken.

### 3. `window-size-fixed = 'width` + advice on `mouse-drag-vertical-line`

Added `ps/treemacs--allow-resize` (`:around` advice) to temporarily clear
`window-size-fixed` in the treemacs buffer for the duration of the drag.

**Problem:** treemacs's own `window-configuration-change-hook` (installed by
treemacs when `treemacs-width-is-initially-locked = nil`) fires on every window
configuration change and sets `window-size-fixed = nil`. This fired during/after
frame resize, clearing our setting before the next resize was protected.

The advice correctly cleared and restored the flag for manual drags (confirmed
via traces: `fixed=nil` at the point `mouse-drag-line` ran). But manual drag
still raised the same error — `mouse-drag-line` itself (not just `window-resize`)
checks side-window constraints independently.

### 4. `preserve-size` window parameter

Set `(window-parameter w 'preserve-size '(t . nil))` via
`window-configuration-change-hook`. The `preserve-size` parameter is documented
to cause `resize_frame_windows` to skip the window.

**Confirmed set** (`(window-parameter w 'preserve-size)` → `(t)` = `(t . nil)`).
**Did not work** — frame resize still changed the treemacs width.

**Why (established later):** there is no `preserve-size` window parameter. The
real one is `window-preserved-size`, and its value is not a cons of flags but
`(BUFFER PIXEL-WIDTH PIXEL-HEIGHT)` — a *recorded pixel size*, checked against
the window's current size and buffer by `window-preserved-size` /
`window--preserve-size`. Setting a made-up parameter name was a no-op, so the
conclusion drawn about the NS backend was wrong. It was the right mechanism,
reached through the wrong door: `window-preserve-size` is the function to call.

### 5. `window-size-fixed = 'width` re-applied at hook depth 90

Re-applied `window-size-fixed = 'width` via `window-configuration-change-hook`
at depth 90 (treemacs's own handler runs at the default depth 0, so ours fires
after it and wins the ordering race). Combined with `ps/treemacs--allow-resize`
advice.

**Frame resize:** worked — `window-size-fixed = 'width` was in place when
`resize_frame_windows` ran, so treemacs was skipped.

**Manual resize:** still broken — `mouse-drag-line` raised `user-error: No
resizable window on the left of this one` 100× even with the advice temporarily
clearing `window-size-fixed`. The error originates inside `mouse-drag-line`'s
own side-window constraint check, which is separate from the `window-size-fixed`
check and cannot be bypassed from outside the function.

**Correction:** there is no side-window constraint check in `mouse-drag-line`.
It just calls `(adjust-window-trailing-edge window growth t t)`, and that
`user-error` is raised in `adjust-window-trailing-edge` (window.el), from the
loop that walks left looking for a resizable window. With
`window-size-fixed = 'width` the treemacs window itself is not resizable and
there is nothing further left, so the loop runs out. The advice failed because
the drag also has to survive *later* motion events, each re-entering
`adjust-window-trailing-edge` — and, more fundamentally, because
`adjust-window-trailing-edge`'s retry pass ignores `preserved` sizes only,
never `window-size-fixed`.

## The solution

`window-preserve-size` on the treemacs window, re-applied from
`window-size-change-functions`. Implemented as `ps/file-tree-pin-width` /
`ps/file-tree-width-setup` in `lisp/ps-file-tree.el`.

Why this satisfies both halves of the goal, in Emacs 30.2 (window.el):

- **Frame resize leaves it alone.** A preserved width makes
  `window-size-fixed-p` return non-nil with `IGNORE = nil`, and the C-level
  frame-resize path honours that: the columns go to the other windows.
- **Dragging still works.** `adjust-window-trailing-edge`, when its first pass
  finds no resizable window, retries with `ignore = 'preserved`
  (window.el:3526-3547). `window--size-fixed-1` consults
  `window--preserve-size` only when `ignore` is not `'preserved`
  (window.el:1778-1779), so the retry sees the window as resizable. That retry
  is what `window-size-fixed` can never benefit from — the buffer-local
  variable is checked unconditionally, with no `IGNORE` escape at all. Hence
  preserved = immovable by the frame, movable by the mouse; fixed = immovable
  by both.
- **Each drag re-pins.** `window-preserve-size` records the width *as it is
  now*; `window--preserve-size` compares that record against the live width, so
  the pin lapses the moment a drag changes it. The hook re-records on the next
  redisplay, making the dragged width the new pinned one.

Also verified in a live GUI Emacs (`set-frame-width` drives the same
`adjust_frame_size` → `resize_frame_windows` path as an OS window drag):

- Frame 100 → 160 → 70 → 120 cols: tree stayed at 22 columns throughout.
- Drag, then resize the frame both ways: the new width held.
- Shrinking the frame far enough that the tree would have to give: Emacs clamps
  the *frame* at its minimum width instead (92 → 35 cols requested, 35 given)
  rather than shrinking a preserved window. So there is no drift to repair, and
  no restore logic is needed.
- Splits, `delete-other-windows`, `balance-windows`, `treemacs-set-width`,
  hide/show: all leave the tree pinned; the explicit width commands re-pin at
  their new width (`enlarge-window`/`shrink-window` drop the preserved size by
  design, and the hook records the result).

`treemacs-width` is updated to `window-total-width` on each re-pin, which is
the unit treemacs's own `display-buffer` call uses, so hiding and re-showing
the tree round-trips the user's width exactly.

## What not to do

- Don't reach for `window-size-fixed` (that is what
  `treemacs-width-is-initially-locked` / `treemacs-toggle-fixed-width` set) —
  it kills dragging, per above.
- Don't try to detect a frame resize and resize the tree back: `window-resize`
  errors on side windows, which is what sank attempt 1.
