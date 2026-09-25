# Architecture

How the pieces fit together: how the configuration loads, where code and
settings live, the order constraints that make startup work, and the principles
the modules share. Start here; the topic notes go deeper.

**Status:** built
**Code:** `early-init.el`, `init.el`, `config.org`, `lisp/` (48 modules),
`tests/` (ERT), `scripts/`, `patches/`. User docs: `docs/Developing.org`.

## What the system is

An Emacs configuration that turns Emacs into a planning application over a
folder of Org files (a vault): an agenda of what to focus on, a calendar, task
lists and situation views, a file tree, a planning mode line, and Claude Code in
a side panel, with automatic saving and git sync underneath. The same folder is
edited from phones and other machines. It is used for planning, not general
editing, and that shapes most decisions: what a mode line shows, what opening a
file does, how much of Emacs's editor chrome is hidden.

## How it loads

1. **`early-init.el`** runs before the first frame exists. Only settings that
   must beat frame creation belong there; today that is turning off the tool
   bar ([macos.md](platform/macos.md)).
2. **`init.el`** initialises packages, keeps Customize's output in a separate
   `custom.el`, turns the org-element cache off (below), and calls
   `org-babel-load-file` on `config.org`.
3. **`config.org`** is tangled to `config.el` and loaded, top to bottom:
   - `* Bootstrap`: package management, then **opening a vault**
     (`ps/vault-bootstrap`, before anything else reads the directory), then
     **loading the local modules** (`require` of each `lisp/ps-*.el`), then the
     auto-tangle hook.
   - `* Settings`: one block per module, `** <Feature> (ps-<module>.el)`,
     setting its user-facing options. This is the one place defaults are
     adjusted.
   - The feature sections (`* Editor & UI`, `* Org Mode`, `* Workflow`,
     `* Links & Capture`, `* Files & Navigation`, `* AI Assistant`,
     `* Keybindings & Menu`, `* Session & Backups`), which configure packages
     and call each module's setup function.
   - The very last call regenerates the AI context file, once every value it
     reads is set ([agent-context.md](ai/agent-context.md)).

**The startup tangle is guarded.** The org-element cache is turned off in
`init.el` *before* tangling, because parsing `config.org` with the cache on
could produce a broken, partially tangled `config.el`. The setting inside
`config.org` would come too late to protect that step. Org buffers turn the
cache back on locally, because `org-appear` queries it on every command.

**Saving `config.org` re-tangles it at once** (`ps/tangle-config-on-save`). The
live session tangles cleanly, and `config.el` then being newer than `config.org`
means the next start skips tangling and loads a known-good file. Saving does not
re-run anything: `ps/reload-config` (`C-c p R`) does.

## Where things live

| Place | Holds |
|---|---|
| `config.org` | Package setup, wiring, keybindings, and every module's settings |
| `lisp/ps-*.el` | Self-contained logic, one feature per module, with a `;;; Commentary:` header recording its load-bearing rationale |
| `tests/test-ps-*.el` | ERT tests, one file per module; `scripts/org_test.sh` runs them all |
| `<vault>/workspace.org` | A vault's own organisation: icons, file sets, context tags, situations |
| `<vault>/.ps/state.el`, `vaults.eld` | Machine-written state, read as data ([vaults.md](foundations/vaults.md)) |
| `scripts/` | The Python emoji matcher, the dev launcher, test and screenshot helpers |
| `patches/` | Patches to Emacs itself ([macos.md](platform/macos.md)) |
| `samples/realistic/` | A sample vault, used by the dev launcher and tests |
| `docs/`, `design/` | User documentation, and these notes ([README.md](README.md)) |

**Logic moves out of `config.org` over time**, one feature at a time, into a
module with tests. `config.org` keeps the wiring and the settings. A module is
named `ps-<feature>.el` with functions `ps/<feature>-...` (public) and
`ps/<feature>--...` (internal), and no `org-` in the prefix since everything
here is Org-related. Every user-facing `defcustom` gets a settings block in
`config.org`; the `defcustom` body is only a fallback.

## Order constraints

Startup works because a few things happen in a fixed order. Each is recorded
where it lives; this is the list in one place.

- **The vault opens first**, before packages and modules, because most paths
  derive from it. So `ps-vault` has no dependencies and must not fail.
- **Vault defaults are captured just before the first `workspace.org` loads**
  (`ps/vault-capture-defaults`), so a vault switch can reset to them
  ([vaults.md](foundations/vaults.md)).
- **Fonts are applied after `face-font-rescale-alist`** is set, so fallback
  fonts are scaled first ([typography.md](interface/typography.md)).
- **Situations register after `config.org`'s `setq` of
  `org-agenda-custom-commands`**, which runs on the `org-agenda` load event and
  would otherwise replace them ([situations.md](planning/situations.md)).
- **The schedule view loads after the agenda layout**, and sets the flag that
  makes the layout skip the Schedule block
  ([schedule-view.md](planning/schedule-view.md)).
- **The mode line's finalize hook runs at depth -90**, before the emoji and
  layout passes.
- **The AI context is written last.**

## Principles

These recur across modules. None is enforced by a tool; they are how the code is
written.

- **Pure core, impure shell.** Logic that can be a function of explicit values
  is kept apart from the code that reads buffers, files, git or the window
  system, so it can be tested in batch without a GUI: the blank-line engine, the
  AI-context renderers, the icon key collection, the vault registry parsers,
  the overlap and availability computations. Several modules declare their
  package dependencies instead of requiring them, so they load and test under
  `emacs -Q`.
- **Declare once, derive many.** One declaration feeds every consumer:
  `org-todo-keywords` is the only list of keywords (kept to four letters so
  agenda badges stay narrow); `ps/context-tags` and `ps/situations` feed six
  places; the icon maps feed the agenda, the tree and the folder listing;
  `ps-org-files` is the only definition of which files are scanned, and
  `ps/org-files-in-scope-p` of what counts as a plan file.
- **Read the vault at call time.** The vault can change while Emacs runs, so a
  value derived from it at load time goes stale; either read it when needed, or
  have the vault switch re-derive it.
- **Derive colours from faces.** Prefer inheriting from Org and theme faces over
  hand-picked colours or per-theme overrides, so everything follows the theme.
  Where a theme needs a specific choice (Solarized, mostly), it is made against
  the theme actually loaded.
- **Never change the text of a generated view to style it** in a way that breaks
  navigation: the agenda copies back its navigation properties, the folder
  listing draws its columns as overlays, and alignment is measured by width.
- **Timers are quiet.** Debounced, single-shot idle timers on edits rather than
  polling; activity-driven rates; pause when unfocused; cancel on a vault
  switch; demote errors, since an error from a timer interrupts typing; never
  force a redisplay from a timer ([macos.md](platform/macos.md)).
- **Never write the user's text without a path back.** One save path that skips
  diverged buffers, no timer-driven prompts, and review before any wholesale
  rewrite ([data-safety.md](foundations/data-safety.md)).
- **Fix at the source, and record the workaround.** When a package misbehaves,
  prevent the bad state rather than repair it after the fact, keep the fix
  narrow, and list it with its removal condition
  ([upstream-workarounds.md](platform/upstream-workarounds.md)).

## Testing and verification

- **ERT for every module**, run by `scripts/org_test.sh` against the `emacs` on
  `PATH` (the patched build on macOS), and in CI (`.github/workflows/tests.yml`).
  `pytest` covers the Python scripts.
- **The real test is the running app.** Passing tests is necessary, not
  sufficient: `scripts/run_emacs_dev.sh` starts Emacs with this repository as
  its configuration and the sample vault, with git sync disabled so a dev run
  can never commit this repository. `PS_ORG_BASE` pins it to another folder
  without touching the saved vault list.
