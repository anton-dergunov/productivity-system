# Research: Task-visualization options in Org mode (beyond the current Day-agenda)

This is a research summary, not an implementation plan — no code changes are
proposed here. It answers: (1) why the default agenda dispatcher looks messy,
(2) what Org-mode/Emacs offers for week/month-style views, and (3) how a
week/month view would fit the existing architecture, plus a look at `calfw` as a
different-paradigm alternative. The concrete build that came out of this research
lives in `agenda-calendar-view.md`.

## Context

Three views are wired up today:
1. **Day-agenda** (`C-c p a` → `ps/show-agenda` → custom command `c`) — the daily
   driver: a time-grid/timeline of today's timed events, untimed "scheduled
   today/due/overdue" sections, plus cross-cutting **High-priority** (`[#A]`) and
   **In progress** (`INPR`) sections. Heavily styled by `lisp/ps-agenda-layout.el`,
   `ps-agenda-icons.el`, `ps-agenda-emoji.el`, `ps-schedule-view.el`,
   `ps-agenda-fold.el`.
2. **List of all tasks** — Org's stock dispatcher views (`t`/`m`/`s` etc. from
   `C-c a`), used rarely.
3. **File view** — browsing `Areas/*.org` directly via the treemacs file tree,
   organized by topic/category.

The question: what's missing for "week or month" visibility of both timed and
date-only tasks, and why the plain `Day-agenda (W25):` dispatcher view looks
inconsistent with the polished custom view.

## Why the stock dispatcher view looks messy

`C-c a` is bound to plain `org-agenda` (config.org:622), Org's generic
dispatcher. Pressing `a` there runs Org's **stock** day/week agenda — not the
custom command `c`. The two diverge structurally:

- `org-super-agenda-groups` (the Schedule/Scheduled-today/Due/Overdue/
  High-priority/In-progress sections) is **let-bound only inside the `c` command's
  parameters** (config.org:664-699). The stock dispatcher never sets it, so you
  get Org's raw, ungrouped list with its default header text — literally
  `Day-agenda (W<n>):` is Org's built-in header string for a one-day span.
- Several styling modules are attached globally via `org-agenda-finalize-hook`
  (`ps/agenda-layout-setup`, `ps/agenda-emoji-setup`, `ps/agenda-icons-apply`,
  `ps/agenda-fold-setup`, plus `org-modern-agenda`,
  `ps/conflicts--agenda-schedule-check`, `ps/agenda--single-blank-lines` — see
  config.org:711-733). These run on **any** agenda buffer, including the stock
  one.

So the stock view gets partial polish (icons, pills, emoji) layered onto Org's
raw structure (no sections, no custom timeline, default time-grid dashes) — a
visible mismatch between "styled" and "unstyled" parts in the same buffer. Not a
bug in the modules; only command `c` carries the full configuration.

## What Org mode / the Emacs ecosystem offer for week/month visibility

**Built into `org-agenda` itself:**
- `org-agenda-span` accepts `day`, `week`, `month`, `year`, or an integer N — the
  core lever. A custom command can let-bind its own span independent of the global
  `org-agenda-span 1`, exactly like `c` already let-binds its own grouping.
- For `week`/`month`/N>1 spans, Org **automatically** inserts a header line per
  day and lists that day's timed entries (with time) and date-only
  scheduled/deadline entries (no time) underneath — "both timed and untimed per
  day" is native once span > 1.
- `org-agenda-show-all-dates t` forces empty days to still show a header.
- `org-agenda-start-on-weekday` controls whether a week block starts Monday or
  follows the current day.
- `org-agenda-custom-commands` can hold **multiple named entries**; each can carry
  its own span, grouping, and header.

**`org-super-agenda` nuance for multi-day spans — resolved:** the section
selectors used today (`:time-grid`, `:scheduled today`, `:deadline past`, etc.)
are evaluated per-entry across the whole span, not per-day, so reusing the current
group list verbatim against a week span would mix days together. However,
`org-super-agenda` ships exactly the selector for this: **`:auto-planning`**
groups items "by their earliest of scheduled date or deadline" and **`:auto-ts`**
groups by "the date of their latest timestamp anywhere in the entry" — both format
the bucket label via `org-super-agenda-date-format` and both work directly inside
`org-agenda-custom-commands`, no extra package needed. A week/month custom command
can set `org-agenda-span 'week` and `org-super-agenda-groups '((:auto-planning t))`
to get genuine per-day buckets, still benefiting from `ps-agenda-layout.el` since
the buffer is a normal agenda buffer.

(Other `:auto-*` selectors: `:auto-category`, `:auto-group`, `:auto-tags`,
`:auto-todo`, `:auto-priority`, `:auto-parent`, `:auto-outline-path`,
`:auto-property`, `:auto-map`, `:auto-dir-name` — none date-related.)

**Other native dispatcher views** (via `C-c a`): `#` stuck projects, `m`/`M`
tags/property match, `s`/`S` text search — the "filter by field" tools. Column
view (`org-columns`, `C-c C-x C-c`) is a spreadsheet-like rollup of properties
across a subtree — file/project-oriented, complements the File view.

**Query-based blocks (`org-ql` / `org-ql-block`):** a separate package where a
block is defined by a Lisp/SQL-like query (e.g. "scheduled or deadlined in the
next 7 days, regardless of which day"), independent of Org's native per-day
blocking. Useful for a rolling-window "next 7 days" framing rather than a
calendar-aligned week, at the cost of a dependency. Reuses the same
`org-super-agenda-groups` DSL via `:super-groups`, so it's a query layer, not a
competing grouping mechanism. ~5x faster than native blocks for aggregate queries
in one benchmark; ships ready-made "this week"/"next week" saved views.

## `calfw` / `calfw-org` as an alternative

`calfw` (with the `calfw-org` bridge) renders an actual calendar **grid**: month,
1-week, 2-week, and day views, as a literal grid of day cells — closer to
Outlook/Google Calendar visually. `calfw-org-create-source` pulls events from Org
files.

Status (verified June 2026): **actively maintained** — a new maintainer (Al
Haji-Ali) shipped a **version 2.0** rewrite, last updated 2025-11-03, requiring
Emacs ≥28.1 and Org ≥9.7. A live, current option, not legacy-only.

Trade-offs versus extending the current architecture:
- **Different visual paradigm** — good for spotting density/gaps across a month,
  genuinely a grid-of-cells look a scrolling agenda can't give.
- **Separate buffer/major-mode** with its own rendering pipeline. None of the
  existing polish (`ps-agenda-layout`'s aligned columns, category icons, emoji,
  fold state, org-modern pills) carries over.
- Time-of-day display per grid cell isn't clearly documented as a strength —
  cells are date-level, so it likely shows "this day has N events" rather than an
  intraday timeline. Explicitly no click-and-drag date-range selection.
- A genuine new dependency rather than reusing `org-agenda-custom-commands` (this
  repo's established pattern).
- Doesn't replace day-level detail well — typically still paired with a regular
  agenda for "what exactly happens today."

**Practical read:** credible for a literal month grid specifically, but a parallel
system — none of the existing styling transfers. Extending
`org-agenda-custom-commands` with `:auto-planning` keeps week/month consistent
with the Day-agenda, no new dependency. Reserve `calfw` only if month view
specifically feels better as a true grid than a scroll of day-blocks.

## Sources

- [org-super-agenda README (selectors, :auto-planning, :auto-ts)](https://github.com/alphapapa/org-super-agenda)
- [emacs-calfw (kiwanami/Al Haji-Ali) — views, version, maintenance](https://github.com/kiwanami/emacs-calfw)
- [org-ql (alphapapa) — query language, org-ql-block, saved week views](https://github.com/alphapapa/org-ql)
- [org-ql examples.org — date-range and :auto-ts query examples](https://github.com/alphapapa/org-ql/blob/master/examples.org)
- [Org Manual — Agenda Commands](https://orgmode.org/manual/Agenda-Commands.html)
- [Worg — Custom Agenda Commands tutorial](https://orgmode.org/worg/org-tutorials/org-custom-agenda-commands.html)
