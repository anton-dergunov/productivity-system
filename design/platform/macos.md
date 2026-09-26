# macOS

What is specific to running this configuration on macOS's GNU Emacs build (the
NS, or Cocoa, port): the freeze that needs patched Emacs, the habits that keep
its exposure low, and the platform facts other modules are built around.

**Status:** built
**Code:** `patches/*.patch`; `early-init.el`; in `config.org`, the
auto-revert block (`*** Auto-save org buffers + auto-revert on disk change`)
and the gutter width (`** Line numbers`); `lisp/ps-scrollbar.el`, `lisp/ps-claude.el`, `lisp/ps-org-save.el`.
User docs: `docs/Installation.org` → "macOS: build Emacs with the freeze fix".

## The freeze

**Symptom.** Emacs stops accepting keyboard and mouse input and never recovers;
only Force Quit ends it. The window keeps redrawing and even reflows on resize.
It tends to follow a change of focus or window state: minimising and restoring,
switching apps, a second frame taking focus. Minimising while a background task
runs, which git sync counts as, was enough to trigger it several times a day.

**Mechanism.** The bug is in Emacs, not in this configuration, and affects
every stock macOS build of Emacs 30:

- Every redisplay flush (`ns_flush_display`) calls `ns_read_socket_1`, which
  enters a nested AppKit event loop, `[NSApp run]`.
- That loop exits only when an "application-defined" event that Emacs posts to
  itself comes back through `-[EmacsApp sendEvent:]`.
- The event is addressed to `[NSApp mainWindow]`. While no window is main
  (minimised, or while key and main status are being handed over) the window
  number is 0 and AppKit discards the event. Even with a valid window number,
  the event can be lost during a focus hand-over.
- There is no recovery path: by the time the event is posted, the flag that
  allows re-posting it is already cleared and the timer that could wake the
  loop is already invalidated. One lost event hangs Emacs forever.

**Nothing inside Emacs can recover it.** Timers, watchdogs, `with-timeout` and
auto-save all run on the blocked main thread; so does the Claude Code
integration's local server, which stops answering too. Diagnosis has to happen
outside the process.

**The fix is two patches, and both are needed:**

- `emacs-30-ns-appdefined-windownumber.patch` addresses the event to the main
  window, else the key window, else any window with a valid number.
- `emacs-30-ns-appdefined-retry.patch` re-posts the event every half second
  until the loop actually exits. It is armed only around `ns_read_socket_1`,
  which normally returns in microseconds, so an idle Emacs is not woken more
  often than before. A freeze reproduced with only the first patch applied,
  which is how the second became necessary.

The patch headers record the evidence in detail. The diagnosis came from
attaching `lldb` to a hung process; that works on an emacs-plus build but not
on the hardened-runtime build from emacsformacosx.com, which is one reason
emacs-plus is the recommended install. The upstream report closest to this is
bug#18705 ("Hang in ns_select -> [NSApp run]").

**What was ruled out on the way.** The first suspects were this
configuration's own code: saving Org buffers on focus loss (to a slow
cloud-synced folder), and the scroll indicator's forced redisplay of its child
frame. Logging every native call they made showed neither was running when the
freeze hit; the wedge was inside Emacs's own redisplay, reached both from timer
firings and from the ordinary "redisplay before waiting for input" pass. The
logging was removed once the patches were in place. The hardening done along
the way stayed, because each part is justified on its own (below).

## Habits that keep exposure low

Every redisplay flush rolls the dice on an unpatched build, and each costs CPU on
any build. So:

- **Never force `(redisplay t)` from a timer.** Use `force-window-update`, which
  marks a window for the next ordinary redisplay (`ps/claude--reanchor-windows`).
- **Prefer notifications to polling.** `auto-revert-avoid-polling` makes
  reverts wait for file-system notifications instead of a five-second timer.
- **Keep timers activity-driven.** The scroll indicator ticks fast only while
  something is scrolling or fading and drops to a slow poll otherwise, pauses
  entirely when Emacs loses focus, and removes its hooks after a long time
  unfocused; see [scroll-indicator.md](../interface/scroll-indicator.md).
- **Bound what runs on focus loss.** `ps/org-save-on-focus-loss` skips when
  nothing is modified or when Emacs has been idle longer than
  `ps/org-save-on-focus-loss-idle-threshold` (a focus event around sleep and
  wake is when the cloud-synced folder is slowest), runs under a timeout, and
  never lets an error escape into the other focus handlers.
- **Mind the frame count.** Every live frame is a native window that redisplay
  must flush.

## Child frames on a scaled, mirrored display

The scroll indicator is a child frame, and the machine it was built on runs
Emacs behind a scaled, mirrored virtual display (BetterDisplay). Facts found
the hard way:

- **Show the child frame, then paint it.** One painted before it is shown is not
  composited by the mirror. A top-level frame would composite, but carries a
  window shadow that cannot be removed.
- **Narrow rectangles inside an SVG collapse to about one pixel** on the scaled
  display; only full-canvas shapes render. So the pill is a solid-coloured frame
  sized to the thumb, and has no rounded corners (those need transparent
  corners, which do not composite either).
- **A child frame hidden and shown again can end up visible but not painting.**
  Hiding therefore deletes the frame, and the next show creates a fresh one.
- **macOS lets the user move and resize a borderless frame**, and no frame
  parameter prevents it. An accidental nudge has to be snapped back.
- **A `no-accept-focus` child frame does receive `down-mouse-1`**, reliably and
  without taking keyboard focus. Tracking a drag across frame boundaries is
  what cannot be made robust.
- **Input over a child frame goes to the child frame**, including wheel events,
  so they must be forwarded to the window underneath. Dispatching them also
  makes Emacs select the child frame's window to look up its local keymap,
  which has visible side effects in the parent.

## Other platform facts

- **The native scroll bar ignores the `scroll-bar` face** and cannot auto-hide,
  which is why the custom indicator exists.
- **The tool bar must be off before the first frame exists.** On macOS 26 it is
  drawn as a floating panel over the frame, and turning it off later leaves
  that panel painted until some unrelated redraw. `early-init.el` sets
  `tool-bar-lines` to 0 in `default-frame-alist`, so it is never built.
- **The line-number gutter flickers unless given a minimum width.** On this
  build `FRAME_SMALLEST_FONT_HEIGHT` is 1, so Emacs's estimate of the largest
  visible line number counts pixels rather than lines and sits near 1000. Pixel
  scrolling then flips the width between 3 and 4 digits.
  `display-line-numbers-width` 2 (a minimum) stops it.
- **A window-divider drag is handled below Lisp**, after the Lisp click handler
  has returned, so code that must stay quiet during a drag cannot rely on advice
  alone (see `ps/scrollbar--drag-in-progress`).
- **`mouse-position` is a cross-process call**, so how often it runs matters.
- **During a live resize, the NS port replaces the frame title with the grid
  size.** `emacs-30-ns-resize-title.patch` removes that; it is cosmetic.
- **Homebrew builds emacs-plus with `-Os`.** For `-O2`, add `cflags << "-O2"`
  near the top of the `cflags` list in
  `$(brew --repository)/Library/Taps/d12frosted/homebrew-emacs-plus/Formula/emacs-plus@30.rb`;
  Homebrew's own flags come first, so this one wins. `brew update` silently
  reverts the edit.

## Not built yet

- The patches are carried locally. Once an Emacs release fixes the freeze, the
  two freeze patches and the "build patched Emacs" step in the installation
  docs can go.
