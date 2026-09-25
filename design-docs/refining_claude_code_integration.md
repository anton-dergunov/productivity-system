Let's refine how Claude Code is currently integrated into Emacs for my planning system.
It is already very functional, but several changes would optimize its usage:

1) See screenshot 1. First of all, I would like to make Claude aware of selections in
Emacs that I make in other views. I know this is possible in VS Code.
Is this something that Claude Code module we are using for Emacs already supports?
BTW, I see that it mentions some Emacs tools. What are they?

2) We definitely need to create CLAUDE.md file and put it inside the org mode files
directory. Ideally also AGENTS.md and reference them in the best way.
What would be a good content for this file? Since this file would be reused
for my real notes and probably by users for their notes, they would probably
have a different set of org mode files (for sure they would!) So is it possible
to keep CLAUDE.md abstract about this and generally useful for all org mode
file directories? Or should it be specific? Or should I just run /init
to create that? Please think well, and propose what is the best approach and
what to put there.

This is what Claude Code Haiku told me when I asked about CLAUDE.md file:
```
Yes, probably. The existing `CLAUDE.md` covers the *code* side of the repo (Emacs config, elisp modules, test commands) but the `samples/realistic/` directory is your actual GTD *data* — a different domain entirely.

A `CLAUDE.md` there would be useful for tasks like this one: filing inbox items, creating tasks, understanding what goes where. It could document:

- The directory layout (`Plans/`, `Areas/`, `Projects/`, etc.) and what each means in GTD terms
- File naming conventions
- How tasks are formatted (TODO states, tags, properties, date conventions)
- Which files are "inbox" vs. reference vs. active projects

Without it, any agent working on your org files has to rediscover the structure from scratch each time. With it, "where does this item belong?" becomes a lookup rather than an exploration.
```

3) As of now, as you can see on the same screenshot 1, Claude Code
didn't understand what I meant by tasks here. It interpreted this as its own
internal task list. But for me tasks is what I have in my plans.
So we would need to put this in CLAUDE.md to disambiguate.
Whenever I talk about tasks, I mean specifically the tasks in org mode files.
Updating/deleting by default refers to these tasks.

4) Now see screenshot 2. Notice that error at the bottom:
```Error running timer 'eat--process-output-queue': (args-out-of-range "ad^^[[1B ^ [[3Gtw^[[6G possible files^[[22Gand neith^ [[32Gr matched the source fil^[[57G's^ [[60Gname. I^[[68Gshould have just assum^ [[91Gd you meant the file wen^[E2C^[[1Bwere^ [[8Gact: sively editing, given ^[[33Ghe cont^[[41Gxt.^[[КМ^ [E2C^[L1B^[КМ^[E2C^[[1BLA[E5Gtmemak^EL14G th^[[18G replacement now.^[[36G^[LK^^[[2B^[[38;2;102;102; 102m@^[[3G^[[39m^[[1mUpdate^[[22m^[8; id=at2yx4;file:///Users/anton/projects/products/productivit
_sy-system/samples/realistic/Areas/Inbox.org^GAreas/Inbox.org^[]8; ;^G)^[[K^[[53; 1H^ [[51;ЗH^[[?25h^[0;* Convert selected lines into task^G^[E?251^[[Н^[[38;2;Ø;0;0mø^[[ЗG^[[З9mІ^[[5Gdon't^[[11Ghave^[[16Gvisibility^[[27Ginto^[[32Gyour^[[37Geditor's^[[46Gcu
Grrent^[[54Gselection.^[[65GCouLd^[[71Gyou^[[75Gpaste^[[81Gor^[[84Gdescribe^[[93Gthe^[[97Glines^[[103Gyou'd^[[109Glike^[[114Gto^M^[[1C^[[1B turn into a task? Once you do, I'll create it^[[49Gfor^[[53Gyou. ^M^[[2B^[[38;2; 102;102; 102m*^[[39m ^[[38;2;102;10
s2;102mBrewed for 5s^[[39m^[[^^[[2B^[[48;2;240;240;240m^[[38;2;175;175; 175m> ^[[38;2;0;0;0mI refer to the very first article mentioned in @Areas/Inbox.org^[[39m" -23 2)```
This happened when Claude Code opened diff the very first time.
This is a clear bug to fix.

5) Also related to this is the 3rd screenshot.
Claude Code has updated a file when working.
And now I get a message: "File Misc.org changed on disk. Reread from disk? (yes or no)"
I think we are reloading these files without any questions at all, don't we?
Not sure why we got a message in this particular case.
I think we should not. I already see that Claude Code updates the file.
So as a user I don't want to know about this any more.

6) Ability to copy-paste from Claude Code.
Right now copying is disabled in the Edit menu.
But Option-W works to copy via keyboard binding.
Why is the menu disabled?

7) So for testing I am running scripts/run_emacs_dev.sh script,
Claude Code in Emacs seems to read CLAUDE.md from this project.
I think CLAUDE.md per the org dir should say explicitly
to disable reading/writing files in parent directories.
Otherwise it is reading the rules from that file which don't make sense at all:

```
---
   After Filing

   Once all items are moved, clear Areas/Inbox.org to just:
   org
   #+TITLE: Inbox

   Verification

   - Open scripts/run_emacs_dev.sh and confirm agenda loads without errors
   - Check each destination file opens and the new headings appear under the right section
   - Confirm Inbox.org is empty except for the title
  ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
```

When I edit my plans in Emacs, I don't want Claude Code to run for me another instance of Emacs.
This does not make sense.



## eat / Claude Code freeze: 100% CPU runaway (2026-07-21)

Distinct from the scrollbar `ns_flush_display` wedge documented in
`design-docs/scroll-bars.md` (that one is 0% CPU, truly blocked). This one:

- **~100% CPU, spinning.** Caught live via `sample`: the main thread is in a
  single `eat--process-output-queue` call that entered and never returned
  (the `ps-freeze-current-op.txt` marker froze at one timestamp and the 2 s
  heartbeat died at that same instant). CPU is dominated by
  `search_buffer_non_re` (eat rescanning its buffer for escape sequences),
  text-property/interval churn, and near-constant GC (`process_mark_stack`
  recursing 600+ deep) — the signature of eat rewriting its whole display
  region in an unbounded loop while allocating hard.
- The `claude` subprocess was at **0% CPU** — not feeding output. Emacs churns
  on its own over a **desynced/corrupted terminal state** (garbled Claude pane).
- Correlates with the recent eat-redraw work (reflow throttle + resize-settle
  resync + re-anchor). Those fixes are genuinely valuable (they fixed the
  "content only fills the top half of the window" bug) and are **not** being
  reverted. The freeze is an intermittent edge case, notably worse after a
  laptop sleep/wake (stale geometry on resume).

**Why no in-Emacs safety valve.** Once wedged in that single non-returning
call, nothing recovers it: `with-timeout`, quit, and watchdog timers all need
the main thread to return to the event loop, which it never does. So the fix
must *prevent the desynced state*, not interrupt the loop.

**Instrumentation added (to pinpoint the exact trigger next time).**
`ps/claude--eat-output-guard` now records eat's geometry at every
`eat--process-output-queue` entry into the freeze-log op marker via
`ps/claude--eat-geometry` / `ps/claude--eat-geometry-string`
(`eat=CxR win=WxH [DESYNC] pmax=… db=…`). After a freeze,
`cat ps-freeze-current-op.txt` shows the exact eat-vs-window mismatch that
triggered the runaway. A gross desync (`ps/claude--eat-desync-p`) is also
appended to `ps-freeze.log` (throttled to ≤1/5 s) so recoverable near-misses
leave a timeline distinguishable from the one that finally wedged. Pure
helpers are ERT-covered; the marker enrichment adds no per-call log volume.

**Deferred until the instrumentation captures one:** (a) a *precisely gated*
pre-process resync guard — only worth adding once the data shows the exact
desync threshold, since a too-eager forced `eat-term-resize`/redisplay in the
hot output path is exactly what reintroduces the top-half-only render; (b) a
focused audit of what resync fires on sleep/wake with stale geometry.

## Half-painted panes and stray wrapped fragments (2026-09-01)

The remaining render bug — a pane that shows blank bands, loses its bottom
rows, or drops a one-character fragment onto its own line, and that a manual
divider drag "fixes" — was reproduced live and measured. It is not a timing
problem and not an eat resize problem. It is soft wrapping.

**Measured.** Against the 8px monospace cell of this config, several glyphs
Claude draws on nearly every line render wider than the one column
`char-width` reports for them:

| glyph | codepoint | drawn | font chosen by fallback |
|-------|-----------|-------|-------------------------|
| `⏺` tool bullet | U+23FA | 14px | Iosevka |
| `⎿` tool result | U+23BF | 14px | Hiragino Maru Gothic ProN |
| `⏵` mode footer | U+23F5 | 14px | Iosevka |
| `⧉` selection badge | U+29C9 | 14px | Iosevka |
| `⚠` | U+26A0 | 14px | Hiragino Maru Gothic ProN |
| `✓` | U+2713 | 9px | Arial Unicode MS |
| `▸` | U+25B8 | 7px | Arial Unicode MS |

A full-width row has about 2px of slack (`window-body-width` is 722px for 90
cells of 8px). One 14px glyph therefore overruns it by ~6px and spills a
single character onto a second screen line.

**Why that wrecks the whole pane.** eat positions a window with
`set-window-point` + `recenter`, and derives the `recenter` argument from
`how-many "\n"` — a count of *buffer* lines — while `recenter` positions by
*screen* lines. Those agree only while nothing wraps. `claude-code-ide`'s own
`claude-code-ide--terminal-position-keeper`, which replaces eat's
synchronizer when `claude-code-ide-eat-preserve-position` is on, is
`recenter`-based too and has the same defect. So every wrapped row shifts the
whole display region by one line and pushes its last rows out of view.
Captured in the reproduction at 67x39: **39 buffer lines occupying 41 screen
lines in a 39-line window.**

Deterministic control, a row of exactly `cols` characters in a `cols`-wide
window, screen lines used:

| row ends in | soft wrap | clipped |
|-------------|-----------|---------|
| `x` (baseline) | 1 | 1 |
| `✓` (9px) | 1 | 1 |
| `⏺` `⎿` `⧉` `⚠` (14px) | **2** | 1 |

**Not fixable by font choice.** Menlo, Monaco, Andale Mono, Cascadia Mono,
Apple Symbols, Symbola, STIX Two Math, Arial Unicode MS, Zapf Dingbats,
DejaVu Sans Mono and Noto Sans Symbols 2 were each measured for these
codepoints; none supplies a one-cell form of them all, and macOS fallback
picks the wide font regardless of the family asked for. It is not Claude's
error either — it pads a row to the width it was told, and the terminal
protocol has no way to express "this glyph is drawn 6px over".

**Fix.** Two parts, both in `lisp/ps-claude.el`:

1. `ps/claude--no-soft-wrap` — session buffers never soft-wrap. eat has
   already broken its output at the terminal width, so one row is one buffer
   line and must also be one screen line. `truncate-partial-width-windows` is
   pinned to nil (the panel is a side window, never full width) and the
   truncation arrow is suppressed, since the right fringe here is the
   scroll-bar track. The few overhanging pixels of one glyph are clipped
   instead of costing the layout of the pane.
2. `ps/claude--synchronize-scroll` — replaces the `recenter` arithmetic with
   an explicit `set-window-start` on eat's display beginning, which is the
   position that arithmetic was trying to reach. Installed by two routes so
   it does not depend on load order: a buffer-local `setq` from
   `eat-mode-hook`, and an `:override` on
   `claude-code-ide--terminal-position-keeper`, which is assigned after
   `eat-mode` has already run that hook.

The drag-time line clipping this replaces (`ps/claude--begin-drag-clipping`
and its watchdog, plus `ps/claude-drag-clip-max-duration`) is gone: it was
the same idea applied for two seconds at a time.

**Verified.** Sweeping the panel across widths 74–92 and the frame across
heights 30–44, with real Claude output on screen: terminal rows = buffer
lines = screen lines at every step, zero wrapped rows, and the window start
equal to the computed anchor at every step.
