# Agenda views

What each planning view is for, how the views are wired into `org-agenda`, and
the week and month options that were considered.

**Status:** built
**Code:** `config.org` → `*** Super agenda` (the custom commands and
`ps/agenda-day-super-groups`), `ps/show-agenda`, `ps/show-calendar`,
`ps/show-tasks`, `ps/calendar-follow-timestamp`; `lisp/ps-agenda-layout.el`
(view kinds, span controls); `lisp/ps-schedule-view.el` (auto-refresh). User
docs: `docs/Agenda.org`, `docs/Calendar.org`, `docs/Tasks-view.org`.

## Problem

Org's agenda is one machine that can answer several different questions, and
out of the box it answers them all in one mixed view. Two concrete gaps started
this work:

- There was no week or month view.
- Org's stock view (`C-c a a`) looked half-styled. The section grouping was
  bound only inside the custom Agenda command, but the styling modules run on
  `org-agenda-finalize-hook` for every agenda buffer. The stock view got icons
  and badges on top of Org's raw, ungrouped list.

## The views

Each view answers one question.

| View | How to open | Question | Shape |
|---|---|---|---|
| Agenda | `C-c p a`; dispatcher `c` | What should I focus on now? | Today's dated sections, then High-priority, In progress and Next up |
| Calendar | `C-c p c`; dispatcher `g` | What is on which date? | A flat list; day, week, month, year or any range |
| Tasks | `F9` | What is open at all? | Every open task, with Org's keyword selector |
| Situations | `C-c p S` | What can I do in this situation? | See [situations.md](situations.md) |

Availability and Conflicts are computed buffers rather than agenda views; they
are not covered here.

## Decisions

**The Agenda is not purely about dates.** Its pull sections (High-priority,
In progress, Next up) stay the same when you look at tomorrow. That is what
separates it from the Calendar. The name "Agenda" was kept over "Focus"
because it reads naturally ("what's on my agenda") and needed no renaming.

**The pull sections never repeat a task.** Their queries exclude each other,
with the precedence INPR > priority A > NEXT (hence the `/-INPR` and
`-PRIORITY="A"` restrictions). A task can still appear both in a dated section
and in a pull section; the two answer different questions. Note that
`-PRIORITY="A"` also matches tasks with no priority cookie, because Org gives
those the default priority.

**The day grouping is the global default.** `org-super-agenda-groups` is set
globally to `ps/agenda-day-super-groups`, not only inside the Agenda command.
Anything that calls `org-agenda-list` without its own grouping, such as the
stock `C-c a a`, then renders through the same pipeline. Views that want a flat
list bind the groups to nil locally: Tasks, the Calendar, and the Agenda's own
pull sections.

**Group order is match order.** org-super-agenda gives an item to the first
group that matches; `:order` only sorts where the sections are displayed.
`:scheduled today` matches timed tasks as well as untimed ones, so "Schedule"
(`:time-grid t`) must come before "Scheduled today", or timed tasks would leave
the timeline.

**The Calendar is a flat list for every span.** It has no sections and no time
grid, and its day view does not reuse the Schedule timeline. The timeline, the
now line and the minute refresh belong to the Agenda, the view about today. An
earlier build reused the Schedule timeline for the Calendar's day and grouped
longer spans into per-day buckets with org-super-agenda's `:auto-planning`; it
was replaced by the flat list. Longer spans now use Org's own per-day headers,
which the layout module turns into collapsible day sections under a span
header with **D W M Y** and **Range…** controls.

**The Calendar shows each item on its own date only.** `org-scheduled-past-days`,
`org-deadline-past-days` and `org-deadline-warning-days` are 0 inside it:
nothing is carried forward, warned about in advance, or shown as overdue.
Overdue work belongs in the Agenda.

**The Calendar skips work it never shows.** `org-agenda-entry-types` is limited
to deadlines, scheduled dates and timestamps, and `org-agenda-dim-blocked-tasks`
is off. That roughly halves the scan a year view needs. Weeks start on
`calendar-week-start-day`, `ps/show-calendar` aligns a week, month or year to
its boundary, and empty days are skipped (`org-agenda-show-all-dates` nil).

**Clicking a date in an Org file opens the Calendar** at that date, and a date
range opens that many days. `ps/calendar-follow-timestamp` overrides
`org-follow-timestamp-link`, which would otherwise open Org's stock agenda.

**Each view tags its buffer with a view kind.** The custom commands let-bind
`ps/agenda-layout-view-kind` (`agenda`, `calendar` or `situation`), and the
layout copies it into the buffer-local `ps/agenda-layout--view-kind` so it
survives a re-layout after a resize. The view kind decides three things:

- Only the Calendar draws span controls.
- Only a Situation view draws the plate naming its query.
- Only the Agenda is rebuilt by the minute refresh. Rebuilding the Calendar
  made it jump back to today and made month and year views sluggish.

**The dispatcher keys are `c` and `g`.** `a` in Org's dispatcher is its
built-in agenda and cannot be taken over by a custom command.

**Views take over the selected window.** `org-agenda-window-setup` is
`current-window`, so opening a view leaves the other windows alone. Around
that:

- `ps/window--split-if-alone-advice` on `org-agenda` and `org-todo-list` splits
  first when the selected window is the only content window.
- `ps/window--inhibit-split-advice` on `org-agenda-redo` makes a refresh rebuild
  in place instead of splitting again.
- The dispatcher (` *Agenda Commands*`) appears as a bottom strip through
  `display-buffer-alist`, with `delete-other-windows` suppressed while it is up
  (`ps/agenda-dispatcher-keep-frame`), so choosing a view does not collapse the
  frame.

Org's default, `reorganize-frame`, bypasses `display-buffer-alist` with its own
logic, which is why the agenda sometimes split and sometimes replaced a window.
The general window rules are in [windows.md](../files-and-windows/windows.md).

## Rejected

- **calfw / calfw-org** as the week and month view. It is maintained (a 2.0
  rewrite in 2025) and draws a real calendar grid, but it is a separate
  rendering pipeline: none of the agenda styling carries over. Its cells are
  date-level, with no timeline within a day, and it is a new dependency. Worth
  revisiting only if a literal month grid is ever wanted.
- **org-ql blocks** for the date views. They suit a rolling "next 7 days"
  rather than a calendar week, and add a dependency. They reuse the
  org-super-agenda group syntax (`:super-groups`), so they remain an option for
  query-based task lists.
- **Reusing the day groups for longer spans.** org-super-agenda selectors such
  as `:scheduled today` are evaluated per entry across the whole span, not per
  day, so a week grouped this way mixes its days together.
- **One command per span.** The Calendar is one command whose span is switched
  in place (`org-agenda-day-view` and friends, or `ps/agenda-layout-span-range`).

## Constraints and traps

- `org-agenda-redo` calls `recenter`, so a refresh needs the agenda's window to
  be selected. The minute refresh therefore does nothing when the agenda has no
  live window.
- Situation commands are appended to `org-agenda-custom-commands` after this
  block's `setq`, or the `setq` silently replaces them; see
  [situations.md](situations.md).
- Tasks binds `org-super-agenda-groups` to nil. Otherwise the global day
  grouping lumps every undated task under "Other items".

## Not built yet

- A **Projects** view: a heading with no TODO keyword that has at least one
  task below it. That matches how the files are already written; Org's
  stuck-projects view uses a different convention.
- A **Waiting** view for `WAIT` tasks.
- Effort and capacity planning.

## Sources

- [org-super-agenda](https://github.com/alphapapa/org-super-agenda) (selectors,
  `:auto-planning`, `:auto-ts`)
- [emacs-calfw](https://github.com/kiwanami/emacs-calfw)
- [org-ql](https://github.com/alphapapa/org-ql)
- [Org manual: Agenda commands](https://orgmode.org/manual/Agenda-Commands.html)
- [Worg: custom agenda commands](https://orgmode.org/worg/org-tutorials/org-custom-agenda-commands.html)
