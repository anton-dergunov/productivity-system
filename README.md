# Org-mode planning system for Emacs

[![Tests](https://github.com/anton-dergunov/productivity-system/actions/workflows/tests.yml/badge.svg)](https://github.com/anton-dergunov/productivity-system/actions/workflows/tests.yml)

A minimalist Emacs configuration for planning your work and life in plain-text
[Org Mode](https://orgmode.org/) files. The workflow is inspired by
[Getting Things Done](https://en.wikipedia.org/wiki/Getting_Things_Done): you
keep tasks and notes in a handful of Org files, and a clean, visual **agenda**
shows what matters today — schedule, deadlines, high-priority work, what's in
progress, and what to pick up next.

It doubles as a complete `~/.emacs.d`, so you can use it as your whole Emacs
setup or borrow pieces for your own.

<p align="center">
  <img src="screenshots/solarized-light.png" alt="The agenda under the Solarized Light theme" width="820">
</p>

## Highlights

- **A visual agenda** — your day at a glance: a real timeline, deadlines,
  overdue items, high-priority, in-progress and next-up tasks, with category
  icons and compact status/priority/date pills.
- **A schedule view** — see the day as a timeline or a compact event list, with
  a live now-indicator that refreshes every minute.
- **Situations** — saved searches named by circumstance ("a spare minute", "on
  foot", "screen in hand, offline"), so an awkward gap in the day has an answer
  ready instead of turning into a scroll.
- **Planning tools** — find free slots (availability), detect scheduling
  conflicts, and shift timestamps between timezones.
- **A file tree with icons** — browse your Org areas, switch between named file
  sets, and optionally scope the agenda to the set you're viewing.
- **Vaults** — keep several Org folders (work, personal, a shared project) and
  switch between them from the file tree, Obsidian-style. Each vault carries its
  own icons, file sets and situations, and syncs to its own Git remote.
- **Capture and link** — quick capture, journaling, Obsidian-style links, and
  one-key insertion of a web link with its page title fetched automatically.
- **Many themes** — switch the entire look with one setting, or audition themes
  live.
- **Modern scrollbars** — an auto-hiding, theme-coloured scroll-position
  indicator, plus smooth pixel scrolling.
- **Selection you can see** — selected text is tinted instead of repainted, so
  headings and TODO pills keep their colours, and it stays visible in a paler
  shade when you move to another window.
- **Blank-line recovery** — mobile Org apps throw away the blank lines you put
  in your files. One command puts them back from your Git history, shows you
  what it would restore and why, and saves only what you accept — never a
  character of your text.
- **Quiet quality-of-life touches** — multilingual typo checking, faded/folded
  DONE tasks, live-preview markup that hides `*`/`/`/`[[]]` until you edit it,
  a centred reading-width column for your plan files on wide windows, and
  automatic background Git sync of your Org files.
- **Back and forward** — every window keeps its own trail, with `‹ ›` on the
  mode line. Files open the way each kind deserves: Markdown and HTML render
  inside Emacs, PDFs and video go to the system, and nothing is ever opened as
  raw bytes.
- **An optional capture inbox** — review the articles, papers and clips you
  forwarded yourself during the day as one list, look inside any of them without
  leaving Emacs, throw away what is not worth keeping, and hand the rest to the
  AI assistant to file into your plans. Needs the separate `info-triage`
  project; invisible without it.
- **An optional AI assistant** — a side-window helper (on your Claude
  subscription) that reads and edits your notes, aware of what you have selected,
  with its changes shown as diffs. Guide it with an `AGENTS.md` in your Org
  folder; your TODO keywords and what each plan file is for are passed to it
  automatically.

## Quick start

> Full, per-OS instructions are in [docs/Installation.org](docs/Installation.org).

1. Install [Emacs](https://www.gnu.org/software/emacs/download.html) (29+) and
   [ripgrep](https://github.com/BurntSushi/ripgrep) (used for searching). On
   macOS, read [the note below](#macos-build-emacs-with-the-freeze-fix) first.
2. Clone this repo as your Emacs config directory:
   ```bash
   git clone https://github.com/anton-dergunov/productivity-system.git ~/.emacs.d
   ```
   (On Windows this is usually `C:\Users\<USER>\AppData\Roaming\.emacs.d`.)
3. Start Emacs. Packages download on first launch, then it offers to create a
   **vault** — the folder your Org files live in. To explore first, open the
   bundled `samples/realistic/` example instead.
4. Press **`C-c p a`** to open the agenda.

For the prettiest result, also install the **Material Symbols** icon font — see
[docs/Installation.org](docs/Installation.org).

### macOS: build Emacs with the freeze fix

On macOS, stock Emacs 30 can freeze outright — the window stops accepting input
and only Force Quit gets you out — and this config's background Git sync makes
it likely. The bug is in Emacs itself; two patches in [`patches/`](patches/) fix
it, and [emacs-plus](https://github.com/d12frosted/homebrew-emacs-plus) builds
Emacs with them applied. The recipe, and a check that the fix is in, are in
[docs/Installation.org](docs/Installation.org).

## Documentation

Start here: **[docs/Index.org](docs/Index.org)** — a guided table of contents.

Jump straight to:

- [Installation](docs/Installation.org) — set it up on macOS, Linux, or Windows
- [Emacs basics](docs/Emacs-basics.org) — new to Emacs? essential editing and
  navigation keys
- [Planning setup](docs/Planning-setup.org) — your Org files, task states, and
  the keys for editing tasks
- [The Agenda](docs/Agenda.org) — the heart of the system
- [Situations](docs/Situations.org) — context tags and the saved searches over
  them
- [Vaults](docs/Vaults.org) — several Org folders, switching between them, and
  which settings belong to which
- [Customization & appearance](docs/Customization.org) — themes, fonts, icons,
  and settings
- [AI integration (Claude Code)](docs/AI-integration.org) — the optional
  assistant and how to guide it with `AGENTS.md`
- [Keybindings](docs/Keybindings.org) — every shortcut on one page
- [Dropbox & Git together](docs/Dropbox-and-git.org) — keeping your notes in a
  cloud folder *and* in Git: the one setup step that stops the two from
  corrupting each other

## Developing

Run Emacs straight from this repo (no install), run the tests, and extend it
with new modules — see [docs/Developing.org](docs/Developing.org).
