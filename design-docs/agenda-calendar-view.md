# Calendar view + agenda wiring fixes

Design note for the build that came out of `agenda-views-research.md`. Two distinct
views with different jobs, plus wiring fixes.

> **v3 correction (the first build was wrong).** The Calendar is now a *plain
> ungrouped list* for every span — no super-agenda sections, no time grid, no
> timeline. The day view does NOT reuse the Schedule timeline; that and the
> now-line/auto-refresh belong to the Agenda only. Concretely the `g` command
> sets `(org-super-agenda-groups nil)` + `(org-agenda-use-time-grid nil)`; the
> minute auto-refresh timer in `ps-schedule-view.el` is gated to run only when
> the `*Org Agenda*` buffer's `ps/agenda-layout--view-kind` is `agenda` (so it
> never rebuilds Calendar or Tasks). The sections below describe the original
> (superseded) timeline-based Calendar day; read them with that correction.

## The two views

1. **Agenda** — the existing custom command `c`, **name unchanged**. Today's
   Schedule timeline + Scheduled-today/Due/Overdue/Scheduled-earlier/Due-soon +
   cross-cutting High-priority/In-progress. Answers "what should I focus on";
   explicitly *not* purely date-bound (High-priority/In-progress don't change as
   you peek at tomorrow). "Agenda" was kept over "Focus" because it reads
   naturally ("what's on my agenda today") and costs zero rename churn.
2. **Calendar** — new custom command `g`. A purely date/time-bound view,
   switchable Day/Week/Month/Year *and* an arbitrary day-count span, with no
   cross-cutting sections. Day renders as a full timeline (reusing the existing
   Schedule-section rendering verbatim). Week/Month/Year render as compact per-day
   buckets, timed entries first with a leading time column, untimed after in
   default order.

## Keys

- `C-c p a` → Agenda (`ps/show-agenda`, unchanged).
- `C-c p c` → Calendar prefix keymap: `C-c p c c` opens Calendar (default Day),
  `C-c p c d`/`c w`/`c m`/`c y` jump straight to a span.
- Dispatcher: Agenda stays `c`; Calendar is `g`. (`a` in the dispatcher is Org's
  built-in "Agenda for current day/week" and cannot be reused by a custom
  command.)

## How little new rendering code is needed

- The Schedule-section timeline rendering (`ps-schedule-view.el`) is keyed off the
  super-agenda **group name** matching `ps/agenda-layout-schedule-group` (default
  `"Schedule"`, via `ps/agenda-layout--header-schedule-p`). Any group named
  `"Schedule:"` gets the full timeline treatment for free.
- Calendar's **Day** uses groups `'((:name "Schedule:" :time-grid t) (:name
  "Scheduled today:" :scheduled today))` — Agenda's own first two groups — so Day
  renders identically to Agenda's Schedule section, no new code.
- Calendar's **Week/Month/Year** use `'((:auto-planning t))` for per-day buckets.
  Org's default `org-agenda-sorting-strategy` (`time-up priority-down
  category-keep`) already puts timed entries first by time, untimed after — so
  sorting is free.
- The **one genuinely new rendering piece**: the leading-time-column "events" look
  (`ps-schedule-view.el`'s `events` style) only applied to groups literally named
  `"Schedule:"`. It is generalized so a date-bucket group whose items have a
  time-of-day also gets the leading time column, rather than the generic
  right-aligned pill.

## Calendar custom command

```elisp
("g" "Calendar"
 ((agenda "" ((org-agenda-overriding-header "")
              (org-super-agenda-groups
                (if (memq org-agenda-span '(day nil 1))
                    '((:name "Schedule:" :time-grid t)
                      (:name "Scheduled today:" :scheduled today))
                  '((:auto-planning t))))))))
```

Settings forms are Lisp, re-evaluated on every redo (including when
`org-agenda-week-view` etc. changes `org-agenda-span` and redoes), so one command
adapts as the span changes in place — no separate per-span commands.

## Global-default promotion fixes the "messy stock view"

```elisp
(setq org-super-agenda-groups
      '((:name "Schedule:" :time-grid t)
        (:name "Scheduled today:" :scheduled today)))
```

Stock `C-c a` → `a` and org-file timestamp clicks call
`org-follow-timestamp-link` → `org-agenda-list` directly (confirmed in Org's
`org.el`), with no group override — so they pick up this default and render
through the styled pipeline instead of raw. Agenda (`c`) is unaffected: its own
let-bound 6-group list takes precedence inside that command.

## Span-switch / range header (in `ps-agenda-layout.el`)

The existing date-header bar (`ps/agenda-layout-date-prev`/`-date-next`/
`-date-refresh`) gains:
- Day/Week/Month/Year buttons calling stock `org-agenda-day-view`/`-week-view`/
  `-month-view`/`-year-view` (switch span in place, keep anchor date).
- An arbitrary day-count control (prompt for N → `org-agenda` with integer span);
  `org-agenda-goto-date` (`j`) already covers arbitrary anchor-date entry via the
  minibuffer/mini-calendar.
- `+`/`-` buttons that read the buffer's current span (coercing to integer
  day-count), increment/decrement by 1, and redo with that explicit span.

Buttons appear for the **Calendar** view only, gated by a buffer-local
view-kind marker set by each custom command's settings list (mirrors the existing
`ps/schedule-view-override` coordination-flag pattern).

Watch-out: switching to month/year view does not become Org's "sticky" default the
way day/week does — verify against `ps/schedule-view-auto-refresh` (fires
`org-agenda-redo` every minute) so Month/Year Calendar views aren't bounced back.

## Window-placement fix

```elisp
(add-to-list 'display-buffer-alist
             '("\\*\\(Org Agenda\\|Agenda Commands\\)\\*"
               (display-buffer-at-bottom)
               (window-height . fit-window-to-buffer)
               (dedicated . t)))
(setq org-agenda-window-setup 'other-window)
```

Mirrors the existing `*Calendar*` fix. Default `org-agenda-window-setup`
(`reorganize-frame`) bypasses `display-buffer-alist` with ad-hoc logic — the root
cause of the "sometimes splits, sometimes replaces" behavior.

## Deferred to follow-ups

- **Projects view** — a heading with no TODO keyword that has ≥1 TODO-keyword
  descendant (matches existing files, zero migration). Needs a new
  `lisp/ps-projects.el`, grouped-by-category display, its own command/key/menu.
  Org's stock `#` stuck-projects heuristic doesn't match this convention.
- **Blocked/Waiting view** — small (`todo "WAIT"` custom command + wrapper +
  menu item, mirroring `ps/show-tasks`).
- **Effort/capacity** and **org-ql-backed Task-list filtering** — discussion only.
