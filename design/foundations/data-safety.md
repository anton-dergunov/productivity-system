# Data safety

Why edits are not lost when the same notes are written by Emacs, a phone, other
laptops, Claude Code and git, all without the user ever pressing save.

**Status:** built
**Code:** `lisp/ps-org-save.el` (the one save path), `lisp/ps-git-sync.el`
(background sync), `lisp/ps-file-notify.el` (a file-watch fix), the auto-revert
block in `config.org` → `*** Auto-save org buffers + auto-revert on disk
change`, the Claude revert fast path in `lisp/ps-claude.el`; settings blocks
`** Org saving (ps-org-save.el)` and `** Git sync (ps-git-sync.el)`. User docs:
`docs/Sync-and-backups.org`, `docs/Dropbox-and-git.org`.

## Problem

A vault is written from many places:

- Emacs, which saves automatically;
- a phone app, whose edits arrive through Dropbox, sometimes a day late when a
  laptop wakes;
- other laptops with the same vault;
- Claude Code, which writes files and then visits them again;
- git sync, which pulls other machines' commits into the working tree.

Each of these is safe alone. Together, the ways to lose text are: saving an old
buffer over a newer file, a question asked by a timer and answered by the next
keystroke, a revert that discards unsaved edits, and two syncers corrupting
each other.

## The rules

**Org buffers are saved from exactly one function**
(`ps/org-save-all-org-buffers-quietly`), called on idle (`auto-save-hook`), when
Emacs loses focus (which is how Claude Code and other editors see the latest
text), just before exit, and by git sync before it commits. The user never saves
by hand, and the mode line needs no "modified" mark for plan files.

**A buffer that is modified *and* whose file changed on disk is skipped, not
saved.** Auto-revert rightly refuses to discard unsaved edits, so the buffer and
the file have diverged; an unconditional save would write the older text over
the newer. The skipped files are reported once and listed in *Show Files Out of
Sync* (`ps/org-save-show-stale`), where the user compares the two and keeps one.

**No save asks a question**, except on quit. Three of the four save paths run
from timers, where a yes-or-no prompt arrives mid-keystroke, with no way to see
what differs, and gets answered by whatever was being typed. On quit, a skipped
buffer is simply left modified, and Emacs's own "Save buffer?" question is the
right one.

**Unmodified buffers follow the disk.** `global-auto-revert-mode` reverts on
file-system notifications, not a polling timer (`auto-revert-avoid-polling`,
which also keeps timer-driven redisplay down; see
[macos.md](../platform/macos.md)). `revert-without-query` matches every file, so
visiting a file that changed on disk rereads it without asking. It applies only
to *unmodified* buffers, so a buffer with edits still asks before discarding
them. Claude Code's entry points revert a stale unmodified buffer first, closing
the window before the notification arrives
([claude-code-panel.md](../ai/claude-code-panel.md)).

**Git sync commits what is on disk**, every `ps/git-sync-interval` seconds:
`git pull && git add -A && commit if anything is staged && git push`, in one
asynchronous shell process with a timeout and a watchdog for a hung or vanished
run. It saves first through the same function, so it never commits over a newer
file either. After a pull that brought something in, it refreshes the file tree.
A vault syncs only when it is itself a repository
([vaults.md](vaults.md)); `PS_GIT_SYNC_DISABLE` turns it off for a session,
which the development launcher sets so a dev run never commits this repository.

**Failures are reported without getting in the way.** A sync retries every
minute and an outage lasts many, so:

- Git's output is reduced to one reason line before it is shown anywhere. The
  raw output is dozens of progress lines, and `message` with it resizes the echo
  area to cover the frame.
- The echo area is used once per *distinct* failure, and once on recovery. A
  repeating failure is already visible in the mode line.
- A failure that will clear itself (server error, no network) shows as
  `retrying`; one that needs the user (conflict, credentials, rejected push,
  missing repository) as `failed`. Neither is `off`, which means the user turned
  sync off; conflating them made a GitHub outage look like "sync is off".
- Only the failures that must be acted on before syncing can continue
  (`ps/git-sync--pausing-classes`: a merge conflict, or conflicted copies inside
  `.git`) pause the sync and open a buffer. Everything else goes to the sync
  log.

**Only one syncer may own `.git`.** A cloud folder replicates `.git` like any
other folder, and when two machines have both written to it, it keeps both
versions as "conflicted copy" files. Inside `.git/refs/heads/` such a copy is a
branch, and every git command then fails with `bad object`; copies of the index
or object store can lose commits quietly. The user docs give two fixes: tell
Dropbox to ignore `.git` on every machine, or keep the repository outside the
cloud folder with a `.git` file pointing at it. The second is recommended
because a machine where the step was skipped fails loudly (git reports the
missing repository) instead of silently corrupting it.

**Conflicted copies of notes are made harmless.** Two machines editing the same
file still produce a copy beside it. The vault's `.gitignore` keeps it out of
history, the agenda does not scan it, and the sync reports it
(`ps/git-sync-cloud-copy-regexp`, shown as "Conflicted Copies"), so it is an
inconvenience, never a duplicate of every task.

**Nothing writes a file without review.** Blank-line recovery, the one feature
that rewrites notes wholesale, proposes changes, shows them, and checks that
only blank lines changed before saving
([blank-line-recovery.md](../editing/blank-line-recovery.md)).

## Constraints and traps

- **Match git's failures case-sensitively.** Git writes `CONFLICT` in capitals
  and Dropbox names its files "conflicted copy"; folding case made every Dropbox
  casualty look like a merge conflict and sent the user to Magit to resolve a
  merge that never happened.
- **Failure patterns are ordered, most specific first**
  (`ps/git-sync--failure-patterns`). A push rejected by a server error mentions
  both, and a repository damaged by a cloud syncer usually also reports a
  rejection.
- **A missing repository is `failed` but does not pause.** With the repository
  kept outside the cloud folder, a machine that never set it up has a `.git`
  file pointing nowhere. That will not fix itself, but it may be a volume not
  yet mounted, which does.
- **A file replaced on disk can trip filenotify.el.** On macOS one kqueue event
  can carry both "deleted" and "changed"; handling the first removes the watch
  and clears its callback, and the second then calls nil ("Symbol's function
  definition is void: nil"). The revert has already happened, so the only
  damage is the error, but `ps/file-notify-setup` makes the handler skip a watch
  whose callback is gone. `tests/test-ps-file-notify.el` asserts the bug is
  still present, so the suite shows when it can go.
- **Focus-loss saves are bounded**: skipped when nothing is modified or Emacs
  has been idle a long time, run under a timeout, and never allowed to raise
  into the other focus handlers ([macos.md](../platform/macos.md)).

## Rejected

- **Prompting on a diverged buffer** during automatic saves (above).
- **Polling for file changes** instead of notifications (above).
- **Letting the cloud folder sync `.git`**, even carefully (above).

## Not built yet

- A passive "lost blank lines" indicator lit after a sync pulls changes; see
  [blank-line-recovery.md](../editing/blank-line-recovery.md).
