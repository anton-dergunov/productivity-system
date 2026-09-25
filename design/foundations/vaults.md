# Vaults

Several Org folders ("vaults"), exactly one open at a time, switched at runtime
without one vault's settings or timers leaking into the next.

**Status:** built
**Code:** `lisp/ps-vault.el` (registry, per-vault state, scaffolding),
`lisp/ps-vault-switch.el` (the switch), `lisp/ps-vault-welcome.el` (the screen
when no vault is open), `lisp/ps-org-files.el` (which files in a vault are
scanned); called first from `config.org` → `* Bootstrap` → `** Open a vault`;
settings block `** Vault (ps-vault.el)`. User docs: `docs/Vaults.org`.

## Problem

Everything the system shows (agenda, file tree, journal, situations, the AI
context) comes from one directory, `my-org-base-directory`. Until August 2026 that was
one path named in `local.el`, read at startup. Wanting a second folder of
notes, or a sample one to try things in, meant editing a file and restarting,
and a dozen values derived from the path at startup (the journal folder,
`default-directory`, the file tree's root, the git-sync directory) were never
reconsidered.

## Decisions

**A vault is one folder, and exactly one is open.** There is no merging of
vaults. `my-org-base-directory` may also be **nil**, on a first install or when
the folder a vault named has gone; every feature that reads the directory
guards with `ps/vault-configured-p`, and the welcome screen offers to create a
vault or open a folder of Org files.

**The vault is scanned recursively, with no privileged folder.** `ps-org-files`
walks the whole vault, so any layout works: flat, one level of topics, or
arbitrary nesting. It is the single source of truth for which files the agenda,
the conflict check and availability see, and its predicate
`ps/org-files-in-scope-p` is what "a plan file" means to the mode line, reading
width and task count. Two name-matched lists keep things out: whole directories
(dotted ones, `Journal`, `Archive`) and single files (`init.org`,
`workspace.org`, and cloud "conflicted copy" files). This replaced a fixed `Plans/` and then `Areas/` folder.

**Three places hold settings, split by who writes them and what they describe:**

| where | holds | written by |
|---|---|---|
| `config.org` → `* Settings` | how things look and behave: fonts, theme, layout, the agenda | the user, once for all vaults |
| `<vault>/workspace.org` | how this vault's content is organised: category icons, file sets, order, context tags, situations, sync override | the user, per vault |
| `<vault>/.ps/state.el` | what the interface toggled: the active file set, whether it filters the agenda | Emacs |

Vault settings travel with the folder, so copying a vault to another machine
brings them along. What stays with Emacs and is shared by all vaults: history,
the kill ring, recent files, theme and fonts. Each vault gets its own restored
session (`ps/vault-desktop-setup`, a desktop file named by a hash of the vault's
path), because a session restores buffers by absolute path.

**Machine-written files are read as data, never loaded.** The registry
(`vaults.eld` in the config directory) and each vault's `.ps/state.el` are
parsed with `read`. Loading a machine-written file would make it arbitrary
code; parsing a plist can only produce data. Both parsers are total, so a
truncated or garbled file costs the settings it held, never a working Emacs,
and both keep keys they do not recognise, so an older Emacs does not discard a
newer one's settings.

**`ps-vault` has no dependencies** beyond `cl-lib`, `seq` and `subr-x`, because
`config.org` needs it before packages are initialised and before the other
modules are on the load path. That also keeps it testable under `emacs -Q`.
`ps/vault-bootstrap` must not fail: any error falls back to what `local.el`
names, and failing that the vault is nil.

**`local.el` is only a first-run seed.** When no registry exists yet, the path
it names becomes the first vault, and from then on the registry decides.
`PS_ORG_BASE` pins a session to a folder without touching the registry, which
is how the development launcher and the tests run against the sample notes.

**Whether a vault syncs is detected, not configured.** A vault syncs exactly
when its folder is itself a git working tree (`ps/vault-git-repo-p`). The test
is for `.git` on disk, not `git rev-parse`: that climbs to an *enclosing*
repository, so a vault kept inside a larger checkout would commit and push that
outer repository. It uses `file-exists-p`, since in a worktree or submodule
`.git` is a file. `ps/vault-git-sync` in `workspace.org`, or the state file,
can override the detection (`ps/vault-git-sync-setting` decides; the state file
wins).

### The switch

Changing `my-org-base-directory` is one `setq`. `ps/vault-apply` is the ordered
sequence that makes everything else agree with it, in place, without a restart:

1. Save the outgoing vault's buffers and its state.
2. Cancel one-shot timers that would act on the wrong vault; stop git sync.
3. Kill the generated views, then the outgoing vault's file buffers; forget
   the back/forward trails.
4. Reset the vault-scoped settings to their defaults.
5. Move the directory, the journal folder and `default-directory`; record the
   vault as current; apply its state.
6. Re-derive: load `workspace.org`, validate the file set, re-apply icons and
   situations, refresh the agenda files, re-root the file tree, start git sync
   if the vault syncs, regenerate the AI context.

## Constraints and traps

- **Reset, don't overwrite.** `workspace.org` is additive and partial:
  `ps/material-icons-add` merges into the icon maps, and its plain `setq`s run
  only if the incoming vault sets the same variable. Without a reset, the old
  vault's categories, file sets, tags and situations survive into the new one.
  Every global a `workspace.org` can contribute to must be listed in
  `ps/vault-scoped-variables`.
- **Capture defaults, don't restate them.** `ps/vault-capture-defaults` records
  the scoped variables' values at load time, immediately before the first
  `workspace.org` is loaded, so the reset values cannot drift from
  `* Settings`.
- **Anything read from the vault must be read at call time**, as
  `ps/org-files-root` does, or be re-derived by the switch. A value computed
  from the directory at load time goes stale on the first switch.
- **Kill generated buffers before file buffers.** The agenda and similar views
  hold markers into the file buffers; killing a file buffer first makes the
  views' cleanup signal partway through.
- **Cancel timers before the directory moves.** The AI-context timer renders
  from whatever `my-org-base-directory` holds when it *fires*, so a timer armed
  by the outgoing vault would write that vault's content into the new vault's
  `.claude/`. Buffer-local timers (the DONE refade) are cancelled too, since a
  timer outliving its buffer errors on every tick.
- **Forget navigation trails after killing buffers.** Trails record paths, and
  the old vault's files are still on disk, so back would otherwise walk out of
  the new vault.
- **Every step is wrapped** by `ps/vault--step`, which turns an error into a
  message. A switch that reports one failed step is recoverable; one that
  aborts halfway leaves the agenda, tree and journal disagreeing about where
  they are.
- **The file tree re-roots asynchronously.** treemacs renders directories in
  subprocesses, so its setup is re-run over a few seconds
  (`ps/vault-file-tree-init-delays`), and those timers carry a generation number
  so two quick switches cannot let the first one re-add the old root. The
  re-renders are what triggered the deferred-annotation error guarded in
  [file-tree.md](../files-and-windows/file-tree.md).
- **The welcome screen opens through `ps/window-show-here`**, which selects a
  content window first; drawn into the file tree's side window, it looked as if
  nothing had happened. Its buttons carry their target, because `push-button`
  does not move point on a mouse click.

## Rejected

- **Loading the registry and state files as Lisp**, for the reason above.
- **Detecting a repository with `git rev-parse`**, for the reason above.
- **Keeping `local.el` as the place the vault is named.** It remains only as
  the seed for a first run.
