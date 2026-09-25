# Agenda line layout

How each agenda line is rebuilt into aligned columns with badges, and why.

**Status:** built
**Code:** `lisp/ps-agenda-layout.el` (the layout pass), `lisp/ps-agenda-fold.el`
(collapsible sections), `lisp/ps-agenda-emoji.el` (emoji data only),
`lisp/ps-agenda-icons.el` (category icons); settings blocks
`** Agenda layout (ps-agenda-layout.el)`, `** Agenda fold (ps-agenda-fold.el)`
and `** Agenda emoji matcher (ps-agenda-emoji.el)`. User docs:
`docs/Agenda.org` → "Reading a line".

## Problem

`org-agenda-prefix-format` controls only the left part of an agenda line. The
TODO keyword, priority, title and tags come after it, from
`org-agenda-format-item`, and are not laid out in columns. The `agenda` block
also carries a scheduling column that `todo` and `tags` blocks lack, so titles
start at different positions in different sections. No prefix format can fix
this, so the layout is a separate pass on `org-agenda-finalize-hook`.
org-super-agenda still does the grouping; the layout only changes how each line
is drawn.

## The line

```
[category icon] [STATE] [PRI] [emoji]  Title…  [tags]            [date badge]
```

## Decisions

**Every field has a reserved slot.** A slot is kept whether or not the task has
that field, so titles line up across all sections and the list can be scanned
without re-reading each line's shape. The emoji slot is reserved too, so emojis
that arrive later do not shift titles. The title gets all the remaining width;
a title that overflows is truncated with `…` and shown in full in a tooltip.

**Widths are measured, and every gap is one space.** The badges render in a
condensed face (`org-modern-label`), so a character count overstates their
width. Each column's width is the rendered pixel width (`string-pixel-width`)
divided by the character width. That keeps every gap at exactly one space, as
in an Org file, while columns still align:

- The state column is as wide as the widest keyword in `org-todo-all-keywords`.
  Keywords are kept to four characters so this column stays narrow.
- The priority column collapses to nothing when no task in scope has a
  priority. The Schedule section and the rest are checked separately
  (`ps/agenda-layout--scope-has-priority-p`).
- On a text terminal, widths fall back to character counts, which also keeps
  the tests deterministic in batch mode.

**Badges are faces, not images.** State, priority, tags and the date badge use
org-modern's faces (`org-modern-todo`, `-done`, `-priority`, `-tag`,
`org-modern-label`), so the agenda looks like the Org files, follows the theme,
and needs no colour lists. Only the category icon is an image.

**Priority reads " A "**, the same in the agenda and in Org files (via the
`org-modern-priority` mapping), and a badge moves as a single character because
its padding lives in a `display` property.

**The category is an icon by default** (`ps/agenda-layout-category-display`:
`icon`, `name`, `both` or `none`). The icons come from the vault's category map;
see [icons.md](../interface/icons.md).

**The date badge is worded by the layout**, from the heading's scheduled or
deadline date: `today`, `in 3d`, `11d ago`, and weeks from 14 days on, with
optional ⚑ and ⏱ glyphs (`ps/agenda-layout-reldate-glyphs`). Right-hand badges
are aligned by their pixel width, because the condensed label face is shorter
than its column count.

**The line text is replaced, and its navigation properties are copied back.**
`ps/agenda-layout--replace-line` deletes the line, inserts the display string,
then re-applies org-agenda's own properties (`org-marker`, `org-hd-marker`,
`type`, `todo-state`, …) across the whole new line. RET, TAB, bulk actions and
`org-get-at-bol` therefore work anywhere on it. Overlays are used only to hide
lines.

**Line types are recognised by their properties**, the same way in the layout
and the fold module. An item has an `org-marker`; grid filler and the now line
have `time-of-day` but no marker; section headers carry
`org-super-agenda-header` or `org-agenda-structural-header`.

**Each module owns one part of the line:**

- The emoji module owns the data: an async matcher (`scripts/org_emoji_matcher.py`),
  a persistent cache keyed by title, and `ps/agenda-emoji-lookup`. When a
  batch arrives it calls `ps/agenda-layout-refresh`. The layout owns all
  drawing.
- The Schedule section belongs to [schedule-view.md](schedule-view.md) whenever
  `ps/schedule-view-override` is set; the layout then skips that block.

**Folding survives a refresh.** Collapsed sections are remembered per agenda
buffer, keyed by header text, and re-applied on every render, so
`org-agenda-redo` keeps them folded (`ps/agenda-fold-default-collapsed` sets the
initial state).

**The agenda has no line numbers and truncates lines**, so the right-hand badge
is always on screen.

## Rejected

- **Rounded SVG pills.** The first build drew state and priority as rounded
  image badges, from a dedicated module with per-state colour lists. They
  looked different from the Org files, needed colours picked per theme, and
  were replaced by the face badges above.
- **Drawing each line as an overlay over untouched text.** This was the
  original plan; the build replaces the text instead, as described above.
- **Taking `org-modern-agenda` off the finalize hook.** Also planned, and not
  needed once the copied properties leave out the keyword regexps (see below).
- **Shortened state labels.** Full keywords are shown;
  `ps/agenda-layout-state-labels` can remap them but is off by default.

## Constraints and traps

- **Never copy `org-todo-regexp` or `org-not-done-regexp` onto the new line.**
  `org-modern-agenda` is still on the finalize hook. If those properties are
  present, it finds the keywords again and restyles badges the layout has
  already drawn, which shows as uneven spacing.
  `ps/agenda-layout--strip-display-props` removes them along with the display
  properties.
- **`ps/agenda-layout-schedule-style` (`grid` / `compact`) is inert** while the
  schedule view is loaded. Those were the layout module's own first Schedule
  styles, before [schedule-view.md](schedule-view.md) replaced them.

## Not built yet

- Emojis are a stopgap. The plan is to replace them with Material Symbols
  glyphs drawn through the same pipeline as the category icons.
- The title budget is counted in characters. A proportional font in the agenda
  would need pixel measurement throughout; see
  [typography.md](../interface/typography.md).
