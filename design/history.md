# History

The major changes of direction, in order, and why each happened. Emacs offers
several packages for almost everything, so much of this is a record of which one
was tried first, what went wrong with it, and what replaced it. Dates are when
the change landed on the main branch.

**Status:** a record; add an entry when a design decision is made or reversed.

## 2021–2024: a personal Emacs configuration

The repository began in May 2021 as an ordinary `init.el`, committed with
one-character messages. In August–September 2024 it became a literate
configuration (`config.org`, loaded by `org-babel-load-file`) and moved to
become `~/.emacs.d` itself. That autumn it gained what would grow into the
planning system: category icons in the agenda, org-modern, Magit, and a first,
rule-based reinsertion of the blank lines that Beorg strips out.

## Early 2026: Python scripts, then Elisp modules

Timezone shifting, free-time availability and scheduling conflicts started as
Python scripts (February–May 2026). On 2026-05-28 they were reimplemented as
Elisp modules with ERT tests, and the next day the first logic was extracted
from `config.org` into `lisp/`. That set the pattern still followed: logic in
tested modules with a `ps/` prefix, settings in one `* Settings` section of
`config.org`, and a Productivity menu over it all. Python remains only where it
earns its place (the emoji matcher's sentence embeddings).

## May 2026: git sync

Automatic git sync arrived on 2026-05-20: pull, commit and push on a timer. It
then grew self-healing, per-failure reporting, and in August coexistence with
Dropbox, once a cloud syncer replicating `.git` had corrupted a repository with
"conflicted copy" branches. The rule that only one syncer may own `.git` comes
from that incident ([data-safety.md](foundations/data-safety.md)).

## June 2026: Neotree to treemacs

The file sidebar had been Neotree since 2024. On 2026-06-10 it was replaced by a
treemacs-based tree with per-category icons, hidden configuration files and a
root at the notes folder. treemacs's view of the world is code projects, so
much of the work since has been bending it: hiding the root, drawing section
headers, following without expanding, holding its width, and four workarounds
for its internals ([file-tree.md](files-and-windows/file-tree.md)).

## June 2026: where the plan files live

The plan files first lived in a `Plans/` folder, renamed `Areas/` on
2026-06-10. On 2026-07-31 the privileged folder was dropped altogether: the
agenda now scans the whole notes folder recursively, so any layout works
([vaults.md](foundations/vaults.md)).

## June 2026: icons from a font

Category icons had been hand-made SVG files, one per category. On 2026-06-14
they switched to glyphs of the Material Symbols font, drawn as in-memory
images, with the category maps moved into a per-folder `workspace.org` so a
person's own categories stay out of this public repository
([icons.md](interface/icons.md)).

## June 2026: the agenda redesign

The agenda was redesigned in mid-June 2026 into aligned columns with reserved
slots, and the TODO keywords were renamed to four letters (`TODO NEXT INPR
WAIT MAYB DONE`) so the state badges stay narrow. The first build drew rounded
SVG pill badges from a module of its own, with colour lists per state. Two days
later, on 2026-06-16, those were replaced by org-modern's face badges: the same
look as the Org files, following the theme, and no colour lists. The Schedule
section became its own Timeline and Events views, the Calendar arrived on
2026-06-20 (first with sections, then as a flat list), and "Next up" joined the
Agenda in August ([agenda-layout.md](planning/agenda-layout.md),
[agenda-views.md](planning/agenda-views.md),
[schedule-view.md](planning/schedule-view.md)).

## June 2026: an LLM client inside Emacs, then Claude Code

From 2026-06-11 to 2026-06-21 a branch tried gptel as an in-Emacs LLM client,
with tools over the notes, several backends, and an evaluation of semantic
search. It was set aside: Claude Code in a side panel already sees and edits the
files, and shows its edits as diffs. The Claude Code integration merged on
2026-06-26, and most of the work since has been making its terminal behave
inside Emacs. How the assistant learns the notes' conventions went from a
generated block inside `AGENTS.md` (June) to a separate generated file (August)
([in-emacs-llm.md](ai/in-emacs-llm.md),
[claude-code-panel.md](ai/claude-code-panel.md),
[agent-context.md](ai/agent-context.md)).

## June 2026: the planning interface

A run of changes made Emacs look less like a code editor: the high-precision
multilingual typo checker (Jinx, 2026-06-12), the planning mode line
(2026-06-18), the user documentation set under `docs/` with a slim README
(2026-06-19), and the scroll indicator (2026-06-28). The scroll indicator went
from fringe scroll bars to a child-frame pill, then to a fading pill with an
activity-driven tick ([typo-checker.md](editing/typo-checker.md),
[mode-line.md](interface/mode-line.md),
[scroll-indicator.md](interface/scroll-indicator.md)).

## July–August 2026: the macOS freeze

From mid-July Emacs occasionally froze outright after going to the background.
The first suspects were this configuration's own code: saving on focus loss to a
cloud folder, and the scroll indicator's forced redraw. Logging every native
call they made showed neither was running when it froze. On 2026-08-02 the cause
was found in Emacs's macOS port: a lost wake-up event leaves its nested event
loop running forever. Two patches fix it, and the installation docs now build a
patched Emacs. The diagnostic logging was removed on 2026-09-05; the hardening
done along the way stayed ([macos.md](platform/macos.md)).

## August 2026: fonts, situations, vaults, clicks

- **Blank-line recovery from git history** (2026-08-08) replaced the rule-based
  reinsertion of 2024, which recovered only a fraction of what was lost
  ([blank-line-recovery.md](editing/blank-line-recovery.md)).
- **Situations** (2026-08-07): context tags as affordances and saved searches
  over them ([situations.md](planning/situations.md)).
- **Fonts by role** and a reading width for prose (2026-08-10 and 11), with
  tools to audition fonts in place ([typography.md](interface/typography.md)).
- **Vaults** (2026-08-15): several notes folders switchable at runtime,
  replacing a single path in `local.el` ([vaults.md](foundations/vaults.md)).
- **One-click links and back/forward** (July to 2026-08-16): a single dispatcher
  for opening files, links that follow on the press, and a trail across every
  kind of buffer ([opening-and-navigation.md](files-and-windows/opening-and-navigation.md)).

## Capture: from a pipeline here to a separate project

A capture methodology was designed in June 2026: one inbox, a Telegram bot, and
an LLM proposing where each item goes. The build went elsewhere: capture is now
the separate `info-triage` project, and this repository only hosts its review
queue (`ps-info-triage.el`).

## September 2026: design notes

The design notes, until then untracked scratch files beside the code, were
reorganised into `design/` by topic, with this history and the architecture
overview ([README.md](README.md)).
