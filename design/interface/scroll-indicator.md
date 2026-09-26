# Scroll indicator

A calm, theme-coloured scroll-position indicator that appears while you scroll
and fades when you stop, replacing a native scroll bar that can do neither.

**Status:** built
**Code:** `lisp/ps-scrollbar.el`; settings block `** Scroll bars
(ps-scrollbar.el)`; wheel-event handling in `config.org` → `** Smooth scrolling
(ultra-scroll)`. User docs: `docs/Customization.org` → Scroll bar.

## Problem

On the macOS build the toolkit draws the scroll bar itself and ignores the
`scroll-bar` face: it is always a hard dark stripe and never hides. No Emacs
setting changes that (see [macos.md](../platform/macos.md)).

## What it is

A global minor mode, `ps/scrollbar-mode`, shows a small **pill** at the right
edge of a window while it scrolls, and fades it out (`ps/scrollbar-fade-duration`)
after `ps/scrollbar-hide-delay`. The pill is a tiny **child frame** whose
background colour is the thumb (the `ps/scrollbar-thumb` face), sized and
placed over the window's reserved right fringe. There is one pill per Emacs
frame. Its geometry comes from the pure `ps/scrollbar--thumb-span` plus the
window's absolute edges, less the parent frame's origin, since child-frame
positions are relative to the parent.

## Decisions

**An indicator, not a control.** You scroll with the wheel, the trackpad or the
keyboard (smooth scrolling comes from ultra-scroll). **Dragging the thumb was
dropped**: macOS lets the user move a borderless frame, nothing prevents it,
and tracking a drag across frame boundaries could not be made robust. An
accidental nudge is snapped back (`ps/scrollbar--snap-back`).

**Clicking the track jumps there** (`ps/scrollbar-click-to-scroll`). That works
because a child frame that never takes focus still receives clicks reliably. A
click on the pill itself is re-dispatched as a click on the bare fringe
(`ps/scrollbar--click-on-pill`). Handling it inside the pill's own event left
transient damage in the parent (a dimmed mode line, outline-only badges) that
survived every attempt to fix the selection; the fringe path never selects a
separate frame in the first place.

**Hover reveals the pill only over its own track**
(`ps/scrollbar-show-on-hover`), not the whole window. The track is often
narrower than a character, so hover is tested at pixel precision
(`mouse-pixel-position` against `ps/scrollbar--strip-rect`), and only when hover
is on.

**Wheel events over the pill are forwarded** to the window beneath, because the
pill, a separate OS window, receives them. `ps/scrollbar--forward-wheel`
rewrites the event's window in place and calls whatever scroll command the
target window binds, without selecting that window (selecting it would activate
an inactive window's mode line). Re-injecting the event through
`unread-command-events` was tried and left mode-line selection state wrong more
often.

**The pill ducks while it is being scrolled over.** Moving a child frame while
it is handling its own stream of wheel events does not take effect on screen:
it freezes under the pointer. So each forwarded wheel event makes the pill
invisible (`ps/scrollbar--duck`, keeping the frame rather than deleting it),
and it stays out of the way for a short hold so a continuous stream does not
make it blink. Deleting and recreating the frame on every event also worked
but was visibly heavier and made the mode line flicker. A brief flicker of the
pill while scrolling with the pointer parked exactly on it remains, and is
accepted.

**Hiding deletes the pill.** A child frame hidden and shown again can stay
visible but stop painting, so "hide" deletes it and the next show makes a new
one. The duck above is the one exception, and its next render forces a fresh
redisplay to avoid the same failure.

**The tick is two-speed.** A timer does the work: moving the pill, fading,
checking hover. It runs at `ps/scrollbar-tick-interval` only while there is
work (the pill is visible, a fade is running, or activity was recent) and drops
to `ps/scrollbar-idle-poll-interval` otherwise. A scroll escalates it at once
through `window-scroll-functions`, which is safe inside redisplay because the
handler touches only timer state. `ps/scrollbar--note-activity` never starts a
timer that is off, so disabled and paused states stay that way. Hover is the
reason an idle poll exists at all: Emacs emits no mouse-movement events without
`track-mouse`, so arrival over the track can only be noticed by looking.

**It goes quiet when Emacs is in the background.** Losing focus pauses the
timer. After `ps/scrollbar-teardown-delay` still unfocused, its hooks and advice
are removed as well, and reinstalled on the next focus.

**Claude Code sessions get no pill.** Claude Code is an Ink (React) terminal UI
that redraws in place and never emits terminal scroll sequences, so nothing in
Emacs knows its scroll position:

- `window-start` and `window-end` stay at the buffer's ends;
  `eat-term-display-beginning` stays at 1; no scrollback accumulates.
- `point-max` moves non-monotonically with the size of each redraw; the cursor
  follows it.
- eat's internal structures have no scroll position.
- `CLAUDE_CODE_NO_FLICKER` does not change the rendering model.
- eat's line mode moves `window-start`, but the buffer holds one screen; the
  conversation lives in Claude Code's own memory.

The session buffers are excluded by name in `ps/scrollbar--candidate-window-p`.
Ordinary `eat` shells are not excluded.

## Constraints and traps

- **The resize handler must ignore the pill's own changes** (`ps/scrollbar--busy`
  and a real-size comparison), or it destroys the pill mid-render.
- **The pill's width scales with the actual fringe width.** A fixed pixel count
  is about three times too thin on a high-resolution display.
- **Divider drags suppress the tick** (`ps/scrollbar--drag-in-progress`). On
  macOS the drag is handled below Lisp after the click handler returns, so the
  flag is set from the click itself, and the resize handler only *extends* it.
  Starting suppression from the resize handler instead froze the tick for its
  two-second fallback on every programmatic window change, which left a stray
  pill on screen after ediff opened or closed.
- **Wheel events outside any window** arrive as `[nil wheel-up]`, and fast
  trackpad scrolling produces `double-` and `triple-wheel-*` variants in any
  area. Stock Emacs binds neither; both are handled globally in `config.org`,
  since they apply everywhere, not just over the pill.

## Not built yet

- A pill for Claude Code, if it ever reports its scroll position through a
  terminal escape sequence that eat could pass on.
