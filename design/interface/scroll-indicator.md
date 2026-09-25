# Custom scroll-position indicator

Internal design note. Not user documentation. Module: `lisp/ps-scrollbar.el`.

## Problem

The native scroll bar is unusable here. On the macOS GNU Emacs **NS (Cocoa)**
build the toolkit draws it and **ignores the `scroll-bar` face**, so it can't be
recoloured (always a hard, dark stripe) and won't auto-hide. No Emacs version or
built-in setting changes this.

We want a calm, theme-coloured, auto-hiding indicator of scroll position.

## What it is

A global minor mode (`ps/scrollbar-mode`) that shows a small **pill** at the
right edge of a window while you scroll, fading when idle. It is a position
**indicator**, not a draggable control — you scroll with the wheel/trackpad/
keyboard (smooth via ultra-scroll, configured in `config.org`).

The pill is a tiny **child frame** whose background colour is the thumb, sized to
the thumb and positioned at its location over the reserved right fringe. One pill
frame per parent Emacs frame, cached in `ps/scrollbar--frames`. Geometry is from
the pure, unit-tested `ps/scrollbar--thumb-span` plus absolute window edges
(`window-edges … t t`) minus the parent's native origin (child-frame positions
are parent-relative). A `window-size-change-functions` handler hides it on a real
window resize, and reveals happen on scroll (and optionally hover) from a
low-frequency timer; it fades after `ps/scrollbar-hide-delay`.

## Hard-won macOS NS / mirrored-display lessons

This took many iterations because the target is a macOS NS Emacs running behind a
**BetterDisplay scaled / mirrored virtual screen**. The non-obvious findings,
preserved so they aren't rediscovered the hard way:

- **The native bar can't be themed/hidden** → custom is required.
- **Child frames are not composited by the virtual-screen mirror *if their image
  is painted before they are shown*.** Show the frame first, then redisplay. (A
  top-level frame composites fine but carries an unremovable macOS window
  shadow, so we use a child frame.)
- **Narrow rectangles inside an SVG collapse to ~1px on the scaled display**
  (only full-canvas rects render). So the pill is a **solid-coloured frame**, not
  an SVG image — frame *sizes* render correctly. (This also means no rounded
  corners: rounding needs transparent corners, which don't composite on the
  mirror.)
- **The pill width must scale with the actual fringe width**; a fixed pixel count
  is ~3× too thin on the HiDPI buffer.
- **Our own `window-size-change-functions` handler must ignore the changes we
  make** (guarded by `ps/scrollbar--busy` and a real-size comparison), or it
  destroys the pill mid-render.
- **A re-shown (hidden→visible) child frame can end up visible-but-not-painting.**
  We never `make-frame-invisible`; "hide" **deletes** the frame and the next show
  recreates a fresh one (self-healing).
- **macOS lets the user move and resize this borderless window, and no frame
  parameter prevents it.** Making the frame accept focus lets our handler grab a
  click, but it then steals focus and still mis-behaves. So the pill is **not
  interactive**; an accidental nudge is **snapped back** from the timer
  (`ps/scrollbar--snap-back`). This is why dragging the thumb was dropped — it
  cannot be made robust on this platform.

## Interactivity, round two: click delivery works; scroll-forwarding is messy

After shipping the non-interactive indicator above, a follow-up round added a
single-click-to-reposition affordance, track-scoped hover, a fade, and fixed a
latent bug (scrolling over the thumb itself did nothing). Two platform facts
worth preserving:

- **A `no-accept-focus` child frame *does* receive `down-mouse-1` cleanly,
  every time, without stealing keyboard focus** — confirmed live with a
  throwaway frame before building on it. This is *not* the same failure mode
  as the drag attempt above (that needed to track an in-progress drag across
  frame boundaries, which is what actually couldn't be made robust); a single
  click delivered to a frame that never receives focus works fine. This
  unblocked click-to-reposition.
- **Wheel/trackpad scroll lands on the pill, not the parent, when the cursor
  is over the thumb** (same separate-OS-window cause as the click case), so it
  has to be forwarded by rewriting the event's `posn-window` in place and
  re-dispatching. Several follow-on platform quirks surfaced fixing this,
  worth preserving:
  - Re-injecting the corrected event via `unread-command-events` (letting
    Emacs's own command loop dispatch it, the same path used for scrolling an
    ordinary unselected window) sounds cleanest but in practice left the real
    window's mode-line selection state stuck wrong more often than driving
    the scroll directly. Driving it manually — `select-window` on the real
    target, pinned (not reverted via `with-selected-window`, which reverts to
    whatever Emacs already switched to dispatch the pill's own local map) —
    was the more reliable of the two.
  - **Repositioning the pill while it is mid-handling the wheel-event stream
    that targets it does not visually take effect** on this display: the pill
    freezes under the cursor until the target position no longer overlaps it.
    Destroying and recreating the frame on every wheel tick (the "self
    healing" pattern used elsewhere) avoided the freeze but was visibly
    heavier — full native-window churn at that frequency caused its own
    mode-line flicker. `make-frame-invisible` (keeping the frame object
    alive, not destroying it) is lighter and avoids that, at the cost of
    needing the same "visible but not painting" caution as the delete/recreate
    path; a short "stay invisible" window after each duck (longer than one
    tick) avoids a rapid show/hide blip while continuous wheel events keep
    landing on the same spot. None of this fully eliminates a brief flicker
    of the *pill itself* while actively scrolling with the cursor parked
    exactly on it — accepted as a known, narrow cosmetic limitation rather
    than chased further, the same call made on dragging.
- **A wheel event whose pixels belong to no window at all** (the sliver
  between a window's right edge and the literal frame border) is reported as
  the two-element key sequence `[nil wheel-up]` — printed as `<nil>
  <wheel-up>` — not `[wheel-up]` alone. Nothing in stock Emacs binds this
  (mwheel.el's prefix list only covers named areas like `right-fringe`), nor
  does it cover `double-`/`triple-wheel-*` variants synthesized by fast
  trackpad scrolling in *any* area, named or not. Both are silenced/forwarded
  globally in `config.org`, not specific to this module.
- **Hover detection needs pixel, not character-cell, precision.** The track
  is often narrower than one character cell, so `mouse-position`-based window
  lookup (already used for scroll detection, where only "which window"
  matters) is too coarse for "is the pointer specifically over the track";
  `mouse-pixel-position` plus `ps/scrollbar--strip-rect` is used instead, and
  only when hover-reveal is enabled, so the common scroll-only path pays no
  extra cost.

## eat-mode / Claude Code window: why it is excluded

`eat-mode` is *not* in `ps/scrollbar-exclude-modes` (eat buffers running
regular shells do get a pill once their session is long enough). Claude Code
session buffers (`*claude-code[...]*`) are excluded separately by name in
`ps/scrollbar--candidate-window-p`.

**Root cause:** Claude Code is an Ink/React TUI. It never emits ANSI terminal
scroll commands (`\e[S` / linefeed-at-bottom-row). Instead, every render is a
full cursor-up + erase + rewrite cycle. eat's `display-begin` marker only
advances when real scroll commands arrive — so it stays at position 1
permanently. `window-start` likewise never changes (always `pmin=1`), and
`window-end` is always `pmax`. Our thumb-span sees "all content fits" and
returns nil → pill stays hidden for the entire lifetime of the session.

Signals investigated and ruled out (all exhausted empirically):

- `window-start`/`window-end`: always 1 and pmax — identical whether at the
  live bottom or scrolled 30 pages up via Claude Code's UI.
- `eat-term-display-beginning`: always 1 (no scrollback accumulates in buffer).
- `point-max`: live experiment across 5 scroll depths yielded
  2048 → 2191 → 4633 → 1930 → 1342 → 3322 — completely non-monotonic,
  reflecting only the byte count of the current Ink redraw.
- `eat-term-display-cursor`: tracks in lockstep with pmax, equally useless.
- eat internal struct (`eat--t-term`, `eat--t-disp`): no scroll-position slot.
- `CLAUDE_CODE_NO_FLICKER=1`: no change — rendering model stays rewrite-in-place.
- eat line mode (`C-c C-l`): window-start does change in this mode, but the
  buffer is only one screenful (~1-4 K chars). The full conversation history
  lives in Claude Code's JavaScript memory and is unreachable from Emacs.

**Future path:** if Claude Code ever emits a custom OSC sequence encoding its
scroll position (analogous to OSC 7 for working directory), eat could forward
it as buffer-local state and this exclusion could be lifted.

## The background-return freeze (2026-07, ongoing)

Symptom: leave Emacs in the background for anywhere from a couple of minutes
to overnight, return, and the whole frame is dead -- no keyboard, no mouse,
clicks do nothing (`C-g` produces no beep/message) -- yet window resize still
reflows text correctly. Only an external restart recovers it.

Two live investigations, second one decisive:

- **First pass** guessed `ps/org-save-on-focus-loss` (synchronous save of Org
  buffers on the Dropbox CloudStorage mount, on every focus loss). That was
  wrong as the cause: it was hardened anyway (skip-if-unmodified,
  skip-if-long-idle, timeout) and is worth keeping, but see below.
- **Second pass caught a live freeze and pinned the mechanism.** A native
  `sample` of the frozen process showed the main thread **truly blocked, 0%
  CPU, static CPU time**, parked in `mach_msg` inside **`ns_flush_display`** --
  a *display flush during redisplay* that entered AppKit's event loop
  (`ns_read_socket_1` -> `[EmacsApp run]` -> `nextEventMatchingMask`) and
  never returned. Decisively: Emacs also hosts the claude-code-ide MCP **HTTP
  server**, and a request to it (`localhost:PORT`) connected at TCP level but
  got **no response** (timeout) -- proving the wedge starves *all* input
  servicing (keyboard, mouse, and network fds alike), not just window events.
  Resize survives because it is handled by AppKit/WindowServer window
  machinery on a path that isn't blocked on that wait.

Consequence worth remembering: once the main thread is wedged in
`ns_flush_display`, **nothing inside Emacs can recover it** -- every Emacs
timer, watchdog, and auto-save runs on that same blocked thread. Recovery is
external only. So no in-Emacs "watchdog" can help; diagnosis has to be
after-the-fact from a persisted log.

What forces the wedging flush is not yet proven. A stack sample can't
distinguish the callers because they all bottom out in `ns_flush_display`.
The two prime suspects, both present at freeze time and both documented-fragile
on this mirrored/scaled NS display:
1. **This module's `(redisplay t)`** in `ps/scrollbar--render-1` -- a forced
   synchronous flush of a borderless child frame.
2. **The Claude Code `eat` terminal** redraw (`eat--process-output-queue`),
   which rewrites its whole Ink UI very frequently.

`lisp/ps-freeze-log.el` (wired in `config.org`) was added to disambiguate on
the next occurrence: a 2 s main-thread heartbeat (stops exactly at the wedge),
focus in/out logging, and a "current op" marker file for high-frequency call
sites. After a freeze, the tail of `tmp/ps-freeze.log` plus the marker file
name the last operation that ran.

**Third occurrence (2026-07-17, ~21:08) caught by this logging, and it
narrowed the window further without yet naming the exact call.** No Claude
Code was running this time (only a large Org file, so the scrollbar was the
only active suspect). The log showed the wedge happened **~400 ms after
regaining focus** from a ~1 minute background stretch: `focus-change -> t` at
21:08:26.328, one more heartbeat at 21:08:26.730, then nothing. Crucially,
**neither of the two originally-bracketed operations (`(redisplay t)` and
`make-frame-visible`) was in progress** -- the log's only scrollbar entries
were from two minutes earlier and had completed cleanly. That means the
wedge is in one of the *other* native Cocoa calls this module makes on every
tick or render, which were not yet bracketed: `(mouse-position)` (called
unconditionally every 0.15 s tick -- the highest-frequency native call in the
module and the top suspect now), `(mouse-pixel-position)` (hover check),
`make-frame` (a fresh pill frame is created on every focus regain, since the
old one is destroyed on focus loss), and `set-frame-size`/`set-frame-position`
(both in the render path and in `ps/scrollbar--snap-back`). All of these are
now bracketed too (marker-file only, to stay cheap at 0.15 s frequency) via
the shared `ps/scrollbar--log-op`/`--log-op-done` helpers -- see each call
site. The next freeze should pin down the exact stalled call from the marker
file alone.

### Fourth occurrence (2026-07-28): the wedge is NOT in our code

Caught live with the widened instrumentation, and it **exonerates this
module's own native calls** while explaining the mechanism properly.

- **The op marker was EMPTY.** Every native Cocoa call this module makes is
  now bracketed (`mouse-position`, `mouse-pixel-position`, `make-frame`,
  `delete-frame`, `set-frame-size`/`-position`, `make-frame-visible`,
  `(redisplay t)`). None was in progress. The last scrollbar render had
  completed cleanly **84 seconds** before the wedge.
- **The stack shows why.** The frame *above* `ns_flush_display` is
  `detect_input_pending_run_timers` -> `redisplay_preserve_echo_area`. That is
  **Emacs's own internal redisplay**, which `keyboard.c` runs whenever *any*
  timer has fired (`if (old_timers_run != timers_run && do_display)`), not a
  redisplay we requested. On the NS build that flush calls `ns_read_socket_1`,
  which enters a **nested AppKit event loop** (`[NSApp run]`). That loop is
  meant to exit when Emacs posts itself an "appdefined" wake-up event; here it
  never exits, so the Lisp interpreter never regains control -- which is why
  keyboard, mouse *and* network fds are all starved at once, while AppKit-level
  behaviour (window resize, reflow, mouse-face) keeps working, since AppKit is
  still pumping events inside that nested loop.
- **Trigger is a focus/window-state transition.** The log's last heartbeat
  reads `focus=t`, and **no focus-loss line was ever written** even though the
  user minimized/Cmd-Tabbed away at that moment -- so the wedge happened
  *during* that transition, before the focus hook could run. The same
  correlation holds for the earlier occurrences (all on backgrounding or
  return-from-background). The user also observed Emacs missing from Cmd-Tab
  afterwards, consistent with the app being stuck mid window-state change.

**So the root cause is in the Emacs NS port, not in this config.** What the
config controls is *exposure*: that nested event loop is entered once per timer
firing, and this module's 0.15 s tick is by far the biggest contributor --
~6.7 firings/second while focused, ~192k per 8 h focused day, and roughly
**576,000 entries over the ~3 days of uptime that preceded this freeze** (one of
which wedged). The tick runs at that rate continuously while Emacs is focused,
*even when the pill is invisible and nothing is scrolling*.

Instrumentation added this round: the heartbeat now carries
`sb-ticks=N (+delta)` (`ps/scrollbar--tick-count`), so a future log shows
whether the tick was firing, and how fast, right up to the wedge; and
teardown/reinstall now log a line each, which were previously invisible.

**Reducing exposure is the actionable lever** (a true fix would be upstream).
Acted on: the tick is now **two-speed** (see below). A further A/B, if freezes
persist, is to run with `ps/scrollbar-enabled` nil in `local.el` for a few
days; if they still occur, the remaining exposure is elsewhere (e.g. the
freeze-log heartbeat itself, at 0.5 firings/second) or purely upstream.

### The two-speed tick (2026-07-28)

The tick was **never actually activity-driven**, despite that being the
intent when the polling reduction was done: `ps/scrollbar--timer` was touched
in only four places (mode enable/disable and focus gain/loss), so while Emacs
was focused it fired at 6.7 Hz forever, whether or not anything was scrolling.
What had actually been done was lowering the interval (0.05 -> 0.15) and
pausing on focus loss.

Now the timer runs at `ps/scrollbar-tick-interval` (fast) only while there is
work -- pill visible, fade in progress, or within `ps/scrollbar--fast-linger`
(hide-delay + fade-duration) of the last activity -- and otherwise drops to
`ps/scrollbar-idle-poll-interval` (1 s). `ps/scrollbar--apply-speed` runs at
the end of *every* tick, including skipped ones, so it always settles back.
Scroll-reveal is not delayed by the idle rate: `window-scroll-functions`
(`ps/scrollbar--on-scroll`) escalates immediately, which is why that hook is
worth having despite running inside redisplay -- it only touches timer state,
never buffers/windows/frames. `ps/scrollbar--note-activity` deliberately will
not start a timer that is nil, so mode-off and focus-paused states stay off.

Measured in a live sandbox via the heartbeat's `sb-ticks` counter: idle went
from `+13` to `+2` per 2 s heartbeat (6.7 Hz -> 1 Hz, **~85% fewer
nested-loop entries**), and an end-to-end probe confirmed idle `slow` ->
real scroll -> `fast` within the same tick -> back to `slow`.

**Hover was also fixed, and was the reason the idle poll had to stay at all.**
Hover-reveal had never worked in practice: the hover check was gated on
`mouse-moved` (a *character-cell* comparison of `mouse-position`), so a
motionless pointer counted as "not hovering", leaving no render target -- the
pill appeared for `ps/scrollbar-hide-delay` and then faded out while the
pointer was still sitting on the track. `ps/scrollbar--resolve-hover` now
reuses the cached hover window when the pointer has not moved (which is
simply correct: an unmoved pointer cannot have entered or left the track),
costing no extra `mouse-pixel-position` call. Hover fundamentally cannot be
event-driven -- Emacs only emits mouse-movement events under `track-mouse` --
which is why an idle poll remains rather than going fully event-driven; the
tradeoff is that hover-reveal can take up to `ps/scrollbar-idle-poll-interval`
to notice the pointer arriving.

### Fifth occurrence (2026-07-31): not timer-driven, and a second frame

Caught live again, with the two-speed tick already running in production
(heartbeats show the idle `+2` per 2 s). Two findings that **narrow the blame
away from this module further**, and one that widens the mechanism:

- **A different path into the same wedge.** Freeze #4 reached
  `ns_flush_display` via `sit_for -> detect_input_pending_run_timers`, i.e. a
  *timer-triggered* redisplay. This one reached it via
  `read_char -> wait_reading_process_output -> redisplay_preserve_echo_area`
  -- the ordinary "about to wait for input, redisplay first" pass, with **no
  timer involved at all**. So the vulnerable operation is *any* redisplay that
  reaches the NS flush, not specifically a timer-driven one. Reducing timer
  frequency lowers how often the dice are rolled; it cannot stop this class.
- **The module was dormant at the wedge.** The marker was empty again, and the
  last pill render was ~100 s before the freeze, with the tick idling at 1 Hz.
  The pill is *deleted* when hidden, so it was contributing no native window
  at that moment either.
- **The new variable was a second top-level frame** (user had just opened one;
  no minimise was involved this time, unlike earlier occurrences). Every live
  frame is a native window that redisplay must flush, and each flush enters
  the nested `[NSApp run]`, so frame count is a straightforward exposure
  multiplier. The log also shows five focus transitions in the ~70 s before
  the wedge, consistent with switching between two frames.

Instrumentation added: the heartbeat now carries `frames=N child=M`
(`ps/freeze-log--frame-counts`), and top-level frame creation/deletion is
logged (child frames deliberately skipped -- the pill's churn would flood it).
Verified live that opening a second frame logs
`[frame] top-level frame created; frames=2 child=0`, and that the tick still
settles back to the 1 Hz idle rate with two frames open (the brief `+6` right
after creation is only the creation transient).

**Where this leaves the diagnosis.** Across the occurrences the constant is
the upstream NS bug -- a redisplay flush entering `[NSApp run]` which never
exits. What varies is only what happened to be redisplaying. The scrollbar now
looks unlikely to be the trigger at all: it was idle and frameless at this
freeze. The most informative remaining variable is the **number of top-level
frames**, which the new heartbeat field will confirm or refute directly on the
next occurrence.

### Long-unfocus hardening (done alongside)

Regardless of which suspect is confirmed, this module was hardened to be
completely inert while backgrounded: `ps/scrollbar--on-focus-change` already
paused the tick timer on focus loss, but left `window-size-change-functions'
and the `mouse-drag-vertical-line` advice installed. After
`ps/scrollbar-teardown-delay` seconds still unfocused (30 min by default),
`ps/scrollbar--teardown-hooks` now fully removes those too
(`ps/scrollbar--reinstall-hooks` restores them transparently on the next focus
gain), so nothing here is reachable during a long idle stretch.

## Customization surface

`config.org` → /Settings → Scroll bars/: `ps/scrollbar-width`,
`ps/scrollbar-fringe-width`, `ps/scrollbar-hide-delay`,
`ps/scrollbar-show-on-hover` (now on by default, scoped to the track itself),
`ps/scrollbar-min-thumb-pixels`. Colour: the `ps/scrollbar-thumb` face.
Smooth scrolling: ultra-scroll in /Editor & UI/. Wheel-event hygiene
(`[nil wheel-*]` and `double-`/`triple-wheel-*` bindings, the buffer-bounds
message silencer) lives in /Editor & UI → Smooth scrolling (ultra-scroll)/,
not in `ps-scrollbar.el`, since it applies everywhere, not just over the
indicator.
