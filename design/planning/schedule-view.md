# Schedule view

The Agenda's Schedule section, today's timed tasks, drawn as a timeline or a
list of events instead of Org's time grid.

**Status:** built
**Code:** `lisp/ps-schedule-view.el`; settings block
`** Schedule view (ps-schedule-view.el)`; menu Productivity → Schedule View.
User docs: `docs/Agenda.org` → "The schedule view".

## Problem

Org's time grid is a column of ticks with tasks laid over it:

- A 10:00–14:00 task looks the same as a ten-minute one, with no sign of its
  length.
- The category name and the word "Scheduled:" repeat what the section already
  says.
- Its colours carry no meaning.
- It does not share the column layout of the other sections (see
  [agenda-layout.md](agenda-layout.md)), so it has to be read differently.

## Decisions

**The task body is the same as in every other section**, shifted right by a
time prefix:

```
HH:MM-HH:MM ┆ [category icon] [STATE] [PRI] [emoji]  Title…
```

Because of that prefix, the Schedule's columns do not line up with the other
sections. That was accepted. The section also has slightly narrower margins
than the rest (`ps/schedule-view-extra-margin-cols`).

**Times show start and end, not a duration.** There is no arithmetic to do, and
gaps and overlaps are visible at a glance. Seeing the free time between tasks
is the reason the Timeline style exists.

**There are two styles** (`ps/schedule-view-style`, or switched from the menu):

- **Timeline** shows a row for each grid time (`org-agenda-time-grid`) between
  the tasks.
- **Events** shows only the timed tasks. It was first called "List";
  "Events" says what the rows are.

**It stays text.** Drawing the day as a graphic was considered and turned down:
text keeps the view testable and in the same style as the rest of the
interface. A row per hour was also turned down, since it shows no duration and
breaks down when tasks cluster.

**The `┆` bar is drawn as an image.** As a glyph it looked broken between rows.
Every row now carries a one-character dotted SVG line as tall as the tallest
row, which draws a continuous line and gives all rows the same height
(`ps/schedule-view--draw-bars`; tune with `ps/schedule-view-bar-ascent`). On a
text terminal the plain glyph is kept.

**The now line spans the whole row.** Its time label comes from the real clock,
not the `time-of-day` Org stamped on the line when the agenda was built. After
midnight, within `org-extend-today-until`, it moves to the bottom, since the
day shown is still yesterday.

**Only the later task of an overlap is flagged** (`⚠ overlap`). The task that
was already running when the clash begins gets no mark.
`ps/schedule-view--find-overlaps` checks every pair; a day's timed tasks are
few, so the simple form is enough.

**Every colour comes from an existing face:**

- grid, ticks and the now line: `shadow`
- times: `org-scheduled-today`
- overlaps: `org-warning` with `org-modern-label`

No colour is picked by hand, so the view follows the theme.

**The view refreshes itself every minute**, exactly on the minute
(`ps/schedule-view-auto-refresh`), to move the now line and drop tasks that were
marked DONE:

- It keeps point, scroll position and folded sections.
- It is silent: the "Rebuilding agenda buffer" message is suppressed.
- It runs only while the buffer holds the Agenda. See the view kind in
  [agenda-views.md](agenda-views.md).
- It runs only while the agenda is shown in a live window. `org-agenda-redo`
  calls `recenter`, which needs that window selected; rebuilding without one
  risked writing the agenda into whatever buffer was selected.

**The layout module steps aside.** `ps/schedule-view-setup` sets
`ps/schedule-view-override`, so `ps-agenda-layout` skips the Schedule block. The
schedule view reuses the layout's column geometry for the task body.

## Rejected

- A graphical drawing of the day, and a row per hour (see above).
- Showing durations instead of start and end.
- The layout module's own first Schedule styles, `grid` and `compact`
  (`ps/agenda-layout-schedule-style`). This module replaced them, and the
  setting no longer has any effect.
