# Agenda View UI Redesign

## Context

The agenda (custom command `c`, "Super Agenda") shows the right *information* — the
user fine-tuned the `org-super-agenda` grouping deliberately — but the *layout* is
visually uneven. The root cause: `org-agenda-prefix-format` (config.org:558) only
controls the **left** part of each line (icon `%-3i`, category `%-15:c`, time,
scheduling info). The TODO keyword, `[#A]` priority, headline, and tags come **after**
the prefix from Org's `org-agenda-format-item` and are *not* column-controlled. Worse,
the `agenda` block carries an extra scheduling column that the `todo`/`tags` blocks
don't, so titles start at different columns *across* sections.

Goal: a calm, well-structured agenda where every data field lines up into clean
(border-less) columns, with rounded "pill" badges for state/priority like the user's
mockup, titles given maximum width (truncated + tooltip when they overflow), collapsible
sections, and no line numbers. Keep `org-super-agenda` for grouping; add our own
line-layout pass on top.

**Terminology note for the user:** the leftmost label ("Financial:", "Health:") is the
Org **category** (`%c`). Yours defaults to the file basename; you set `#+TITLE:` but no
`#+CATEGORY:`, so Org falls back to the filename — which happens to equal your title.

## Decisions (confirmed with user)

- **State labels:** full keywords (TODO / NEXT / INPR). The shared title column
  clears the widest pill present, so high-priority rows get a small gap before the title
  — accepted. (An optional `state-label` remap is provided but defaults to off.)
- **Schedule block:** implement **both** representations, switchable via a config var
  (`grid` and `compact`) so the user can experiment.
- **Scope:** all four parts in one plan.
- **Category column:** default **icon only**; configurable to `name` / `both` / `none`.

## Column model (the heart of the redesign)

Each task line is rebuilt into pixel-aligned columns (left → right):

```
[cat-icon] [STATE pill] [PRI pill] [emoji]  Title text … [tags]            [sched pill]
```

- Columns 1–5 are a fixed left zone; the **title column** starts at a single
  buffer-local pixel offset (`:align-to (TITLE_COL)`) computed per render as
  `left + category + max(state-pill width) + max(priority-pill width) + emoji + gaps`.
  Because `:align-to` is measured from line start and ignores the pixel width of
  preceding inline images, **all three list sections share the exact same title column**.
- Priority and emoji columns are **always reserved** (blank when absent) so titles never
  jump — including when emojis arrive asynchronously.
- The **scheduling pill** ("11d ago", "today", "in 3d") is right-aligned to the window
  edge via `(space :align-to (- right MARGIN))` — no dedicated column, as requested.
- **Tags** render inline immediately after the title in a small, dim style.

Mockup (default: category=icon, full keywords, schedule=grid; pills shown as text here,
but will be rounded SVG badges):

```
 Sunday   14 June 2026

▾ Schedule
   08:00   ·······································
   10:00   ·······································
   11:15   ── now ────────────────────────────────
   12:00   ·······································
   15:00   🧑  TODO          🧑 Interview test          –16:00
   18:00   ·······································

▾ Overdue
   🩺  TODO          ✳ Hepatitis A vaccination: 2nd dose       11d ago

▾ High priority
   🏦  NEXT          #A  ↗ Optimize current savings returns
   🩺  TODO          #A  🦷 Teeth cleaning
   🧑  TODO          #A  📄 Restructure my CV and include sabbatic…

▾ In progress
   💡  INPR   💻 Finish creating MVP for Anki card creation
   🤖  INPR   🎓 Course "Deep Reinforcement Learning Cours…
```

Titles in Overdue / High priority / In progress align to one column (clearing the widest
pill, INPR). The `▾`/`▸` glyph on each header is the collapse control.

## Schedule block — two modes (`ps/agenda-layout-schedule-style`)

- **`grid`** (default): keep Org's time ruler (faint), times right-aligned in a left
  gutter, the restyled "now" line, and real events rendered at their hour using the same
  pill+emoji+title columns with the end-time as a right pill. Schedule is an *outlier*
  (extra left time gutter) — accepted by the user.
- **`compact`**: hide the empty dotted filler rows entirely; show only real timed events
  with the **same left columns as the other sections** (so titles align everywhere) and
  the time range as the right-aligned pill, plus a single `▸ now HH:MM` marker.

```
▾ Schedule                          ▾ Schedule
   08:00  ··················            ▸ now 11:15
   11:15  ── now ───────────            🧑  TODO  🧑 Interview test      15:00–16:00
   15:00  🧑 TODO 🧑 Interview
          test           –16:00
   ── grid ──                       ── compact ──
```

Detection: a real event line has the `type` text property; grid filler / "now" lines do
not (verified in org-agenda source). Compact mode hides filler lines via an `invisible`
overlay; the "now" line is replaced by the compact marker.

## Scheduling-pill text (compact forms)

Computed by us from the deadline/scheduled time (via `org-hd-marker`) + the `type`
property, so we fully control wording:

| Situation | Text | Pill tint |
|---|---|---|
| deadline past | `11d ago` (`2w ago` past 14d) | amber/red |
| deadline today | `today` | accent |
| deadline future | `in 3d` | neutral |
| scheduled past | `3d ago` | amber |
| scheduled today | `today` | accent |
| timed event (schedule) | `15:00–16:00` | neutral |

Optional leading glyph (⚑ deadline / ⏱ scheduled) reusing `ps-schedule-icons` glyphs.

## Rounded pills (no new dependency)

`svg-lib`/`svg-tag-mode` are **not installed**, and Org/`org-modern` only do *square*
`:box` badges. We render rounded pills ourselves by extending the repo's existing SVG
pipeline (`ps/material-icons-svg` / `create-image … 'svg t :ascent center` in
`lisp/ps-material-icons.el`) — a `<rect rx=R ry=R fill=BG/>` + `<text fill=FG>`. New
helper module **`lisp/ps-agenda-pills.el`**:

- `ps/agenda-pills-image (label &key bg fg radius pad font)` → cached SVG image.
- `ps/agenda-pills-width (label …)` → pixel width (for computing the title column).
- Per-state / per-priority colors via defcustom alists (state pill default = gray, like
  the mockup; priority `#A` warm, `#B`/`#C` cooler; faces fall back to theme colors).

## Architecture

Reuse `org-super-agenda` for grouping (unchanged). Add a finalize-hook **layout pass**
that, for each item line, reads its text properties and draws an aligned overlay.

**Marker-safe rendering (key technique):** do **not** rewrite buffer text. For each item
line create one overlay over `[bol, eol]` with a `display` property holding the
constructed string (images + `(space :align-to …)` + truncated title + tags + right pill)
and a `help-echo` with the full title. Buffer text and the line-start
`org-marker`/`org-hd-marker` are untouched, so RET/navigation/bulk commands keep working.
This mirrors the proven overlay approach already in `ps/agenda-emoji--apply`
(`lisp/ps-agenda-emoji.el:162`). Overlays are recreated on every `org-agenda-redo`
(finalize re-runs on a freshly built buffer), so no cleanup bookkeeping is needed.

New / changed files:

- **`lisp/ps-agenda-pills.el`** (new) — rounded SVG pill builder + width measurement.
- **`lisp/ps-agenda-layout.el`** (new) — the finalize reformatter. Two-pass: (1) scan
  item lines to compute max pill widths → `TITLE_COL`; (2) build per-line overlays.
  Renders category icon (from `ps/material-icons-category-map` via `ps-material-icons`),
  state/priority pills (`ps-agenda-pills`), reserved emoji slot (filled from
  `ps-agenda-emoji` lookup), truncated title (+`help-echo`), inline tags, right-aligned
  scheduling pill. Handles both schedule modes. Pure, ERT-testable helpers:
  `ps/agenda-layout--reldate-string`, `--truncate`, `--state-label`, `--title-column`.
  Public: `ps/agenda-layout-setup` (registers hook), `ps/agenda-layout-refresh`.
- **`lisp/ps-agenda-fold.el`** (new) — collapsible sections.
- **`lisp/ps-agenda-emoji.el`** (refactor) — keep the async matcher + on-disk cache, but
  stop creating right-aligned overlays. Expose `ps/agenda-emoji-lookup (title)`; on async
  completion call `ps/agenda-layout-refresh` so the reserved emoji slots fill in (titles
  don't shift — emoji column is fixed-width).
- **`config.org`** — settings blocks for the new defcustoms (in `* Package Management`,
  right after `** Load Local Modules`, per project convention); simplify
  `org-agenda-prefix-format` to a minimal stub (the layout pass rebuilds from properties,
  not from the prefix); **remove `org-modern-agenda` from `org-agenda-finalize-hook`**
  (keep `org-modern` for editing buffers) so our rounded pills own the agenda and aren't
  double-rendered by org-modern's square boxes; add `org-agenda-mode` to
  `ps/display-line-numbers-exempt-modes` (config.org:408-415); set `truncate-lines` via
  `org-agenda-mode-hook`; call `ps/agenda-layout-setup` and `ps/agenda-fold-setup`.

## Collapsible sections (`lisp/ps-agenda-fold.el`)

`org-super-agenda` already tags group-header lines with `org-super-agenda-header` and a
per-line keymap; overriding-header blocks (High priority / In progress) carry
`org-agenda-structural-header`. Both are detectable at bol.

- Bind `TAB` and `mouse-1` on header lines to a toggle command that covers
  `[body-start, next-header-start)` with an `invisible` overlay and flips the header's
  `▾`/`▸` indicator. Boundary detection reuses the same property tests Org's own
  `org-super-agenda--hide-or-show-groups` uses.
- `collapse-all` / `expand-all` commands (bind to keys, mirroring `ps-done`'s
  collapse/expand pair).
- Persist collapsed header labels in a buffer-local set and re-apply inside the finalize
  pass so state survives `org-agenda-redo`.

## Config options (defcustoms; each gets a settings block in config.org)

- `ps/agenda-layout-enabled` (default t)
- `ps/agenda-layout-category-display` — `icon` (default) / `name` / `both` / `none`
- `ps/agenda-layout-state-labels` — keyword→label alist (default nil = verbatim)
- `ps/agenda-layout-schedule-style` — `grid` (default) / `compact`
- `ps/agenda-layout-truncate` (default t) + ellipsis string
- `ps/agenda-layout-emoji-reserve` (default t)
- pill appearance: radius, padding, font scale, per-state bg/fg alist, per-priority
  bg/fg alist, scheduling-tint alist
- `ps/agenda-fold-default-collapsed` — list of section names collapsed on open (default nil)

## Tests (ERT, per repo convention)

- `tests/test-ps-agenda-pills.el` — image returned, cached, width measurement monotonic.
- `tests/test-ps-agenda-layout.el` — feed a temp buffer with mock lines bearing the real
  text properties; assert `--title-column` math, `--truncate` (ellipsis + boundary),
  `--reldate-string` for each `type`/day-delta, `--state-label` remap, and that each item
  line gets exactly one layout overlay with a `display` and `help-echo`.
- `tests/test-ps-agenda-fold.el` — header detection, toggle adds/removes one `invisible`
  overlay over the correct region, collapse/expand-all, redo-persistence.

## Verification

1. `EMACS_BIN="/Applications/Emacs.app/Contents/MacOS/Emacs" ./scripts/org_test.sh`
   (full ERT suite green).
2. `./scripts/run_emacs.sh`, open the agenda (`c`). Confirm:
   - titles align to one column across Overdue / High priority / In progress;
   - rounded state/priority pills; reserved priority + emoji columns; emojis fill in
     after the async pass without shifting titles;
   - long titles truncate with `…` and show the full title on hover (tooltip);
   - right-aligned compact scheduling pills (`11d ago`, etc.);
   - no line numbers; `TAB`/click collapses & expands sections; redo (`g`) preserves
     collapse state.
3. Toggle `ps/agenda-layout-schedule-style` between `grid` and `compact` (and
   `ps/agenda-layout-category-display`) and `g` to redo — both schedule representations
   render correctly.
