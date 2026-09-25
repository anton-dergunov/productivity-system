# Claude Code panel

Claude Code running in a side panel inside Emacs, pointed at the vault rather
than at a code repository, and made to behave like a stable part of the window
layout.

**Status:** built
**Code:** `lisp/ps-claude.el`, over `claude-code-ide.el` with its `eat` terminal
backend; settings block `** Claude Code (ps-claude.el)`; package setup in
`config.org` → `** Claude Code IDE (claude-code-ide.el)`. User docs:
`docs/AI-integration.org`. What the assistant is told about the notes is in
[agent-context.md](agent-context.md); why this replaced an in-Emacs LLM client
is in [in-emacs-llm.md](in-emacs-llm.md).

The Commentary of `ps-claude.el` records each fix in detail, numbered 1 to 12.
This note keeps the reasons that span modules and the lessons that are not
visible in the code.

## Problem

`claude-code-ide.el` assumes it is helping with a code project, and its `eat`
terminal assumes a text grid where every character is one cell wide. Here the
assistant helps with Org planning files, and the panel has to:

- work on the vault, not on whatever repository the current buffer is in;
- see the editor's selection;
- pick up files it edits without "Reread from disk?" questions;
- redraw correctly as it is resized, which it did not.

## Decisions

**The panel is a side window**, docked on the right when the frame is wider
than tall and at the bottom otherwise, decided afresh each time it opens. It is
deliberately *not* subject to the rule that planning views take over the
selected window ([windows.md](../files-and-windows/windows.md)): like the file
tree, its value is staying in one predictable place while you work elsewhere.

**Its working directory is the vault** (`my-org-base-directory`), not the
project root of the current buffer, which for any buffer in this repository
would be the configuration's own source tree. The selection lookup is advised
to use the same key, or the session (stored under the vault) and the lookup
(keyed by the git root) never meet and the selection never arrives.

**The selection reaches Claude reliably.** Three defects stood in the way:

- the package sent 1-based positions over what is VS Code's protocol, so every
  range was one line off;
- nothing was sent when a session connected;
- the CLI clears what it holds after every prompt, while the package only sent
  on change.

So `ps/claude--current-selection` sends 0-based positions, and the selection is
re-asserted when a session connects and whenever the panel becomes the selected
window, the last moment before a prompt is typed. A region is easy to lose on
the way to the panel, so the last non-empty region of a file is remembered until
a command runs there with no region.

**Files Claude writes are re-read quietly.** When Claude visits a file it just
wrote before auto-revert has caught up, `find-file-noselect` would ask "Reread
from disk?". The panel's entry points revert a stale, *unmodified* buffer first,
and `revert-without-query` in `config.org` covers every other path. A buffer
with unsaved edits still asks, so a real conflict is never silently lost; see
[data-safety.md](../foundations/data-safety.md).

**One terminal row is one screen line.** Session buffers never soft-wrap
(`ps/claude--no-soft-wrap`). Several glyphs Claude uses on nearly every line
(⏺ ⎿ ⏵ ⧉ ⚠) are drawn 14 pixels wide in an 8-pixel cell while `char-width`
reports 1, and a full row has about 2 pixels of slack. So a row overruns the
window and spills a character onto a second screen line. Clipping a few pixels
of one glyph is the right trade against the layout of the whole pane.

**The window is anchored directly.** eat positions a window with `recenter`
and an argument counted in *buffer* lines, while `recenter` counts *screen*
lines; the two agree only while nothing wraps, and the package's own position
keeper has the same defect. `ps/claude--synchronize-scroll` sets the window
start to eat's display beginning, the position that arithmetic was aiming for.
It is installed both from `eat-mode-hook` and as an override of the package's
position keeper, so load order does not matter.

**A resize tells the process its new size.** The package's workaround for an
upstream reflow glitch (claude-code#1422) suppresses the size update for
height-only changes after eat has already resized its own model, so the
`claude` process kept drawing for the old size. A plain timer re-syncs the
process from `eat-term-size` once a resize settles, and repaints at once.
During a divider drag, reflows are throttled.

**Quitting does not ask about the session.** The terminal, the MCP listener and
every accepted MCP connection all have query-on-exit flags; they are cleared
just before exit (`ps/claude-no-exit-prompt`).

**Cmd-V pastes into the session.** eat's keymaps rebind `C-y` to `eat-yank` but
not `s-v`, which fell through to plain `yank` and was overwritten by eat's
redraw at once; `s-v` is now `eat-yank` too.

**Tall glyphs are handled globally.** Claude's spinner, bullets and emoji used
to raise the line height and make the text below them jump. That is fixed by
`face-font-rescale-alist`, not per buffer, since `line-height` can raise a line
but never cap it.

## Lessons

**There is no safety valve inside Emacs.** A separate, intermittent freeze: the
main thread spinning at full CPU inside one `eat--process-output-queue` call over
a desynchronised terminal, while the `claude` process itself sat idle. Once a
call never returns, `with-timeout`, quit and watchdog timers cannot run either,
so the only fix is preventing the desynchronised state, not interrupting the
loop. It was not pinned to a trigger before the diagnostic logging was removed;
it looked worse after sleep and wake. What remains is
`ps/claude--eat-output-guard`, which swallows a transient `args-out-of-range`
from eat and schedules a resync.

**Keep forced work out of the hot output path.** A forced `eat-term-resize` or
redisplay while output is flowing brings back the "content fills only the top
half" rendering bug, so any guard there must be tightly gated. From timers, use
`force-window-update`, never a forced redisplay
([macos.md](../platform/macos.md)).

## Rejected

- **Choosing a font with narrower glyphs.** Eleven fonts were measured; none
  supplies one-cell forms of all these characters, and macOS fallback picks the
  wide font whichever family is asked for. It is not Claude's error either: it
  pads a row to the width it was told.
- **Clipping lines only while the divider is dragged.** It was the same idea as
  the no-wrap rule, applied for two seconds at a time.
- **Recomputing the terminal size from `window-body-width` and
  `-height`.** That could differ from eat's own by a row or column and never
  converge, which is why a stuck pane sometimes needed several manual resizes.
- **Gating the reflow throttle on `track-mouse`.** Emacs's drag bookkeeping can
  leave it reporting a drag forever.

## Not built yet

- Once claude-code#1422 is fixed upstream, the package's reflow suppression can
  be turned off (`claude-code-ide-prevent-reflow-glitch` nil); the resync here
  is harmless either way.
- A scroll indicator for the panel needs Claude Code to report its scroll
  position; see [scroll-indicator.md](../interface/scroll-indicator.md).
