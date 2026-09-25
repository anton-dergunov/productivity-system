# Opening and navigation

What "open this file" means, how a single click follows a link, and
browser-style back and forward across every kind of buffer.

**Status:** built
**Code:** `lisp/ps-open.el` (the open policy and the click model),
`lisp/ps-nav.el` (back and forward), `lisp/ps-dired.el` (the folder listing),
`lisp/ps-links.el` (Obsidian links and URL insertion); settings blocks
`** Opening files (ps-open.el)`, `** Folder listing (ps-dired.el)` and
`** Navigation history (ps-nav.el)`. Window placement is in
[windows.md](windows.md). User docs: `docs/Files-and-navigation.org`.

## Problem

A vault holds more than plans: captured web pages, Markdown notes, PDFs,
images, audio with transcripts, the occasional archive. Opening any of these as
Emacs text is usually wrong (a 6 MB `.mp4` opened as text is a frozen frame and
a buffer to kill). Clicking a link took two clicks. And following a trail
through several kinds of buffer (a queue, an item's index, its folder, a file)
had no way back, because each Emacs history knows only one kind of thing.

## Decisions

### What opening a file does

**Opening is a policy, not one operation.** `ps/open-handlers` is an ordered
list of (regexp . handler), first match wins:

- `emacs`: visit it in Emacs (Org, Markdown, text formats, images);
- `browser`: render it as a page (`eww`), not its source (HTML);
- `external`: hand it to the system (`ps/open-external-command`; PDF, EPUB,
  video);
- `refuse`: decline and say why (audio, "the transcript beside it is the
  readable copy"; archives);
- or a function.

A file matching nothing is decided by **looking at it**: text opens, anything
else asks first. The content sniff is only the fallback, so a new capture format
that turns up one day fails safe instead of wedging the frame.

**One dispatcher for every click.** `ps/open-file` is what the file tree, the
folder listing, Org links and Markdown links all go through.

**No advice on `find-file`.** A global hook there would have to be right about
every internal caller, and `image-mode` and `archive-mode` visit binary files
legitimately. The policy sits on the paths a person clicks; `C-x C-f` with a
typed name is left alone, since whoever typed the whole name meant it.

**The folder listing shows what matters.** Dired's `ls -l` columns
(permissions, links, owner, group) are hidden, and a type icon and a readable
size are shown in front of each name:

- The icons are the file tree's own, referenced rather than restated, so the two
  views of one folder cannot drift. Every file gets the same icon: the
  per-category icons of plan files mean nothing in a folder of captured
  material.
- The columns are overlay `before-string`s, not inserted text, so Dired's
  commands that count columns keep working.
- The size comes from `file-attributes`, because the listing may be GNU `ls` or
  Emacs's own `ls-lisp`.
- `ps/dired-decorate` is a *global* `dired-after-readin-hook` entry, so it runs
  after `dired-omit-expunge` has removed the hidden lines.

### One click follows a link

**Act on the press, and never move point.** Both obvious ways to make one click
enough fail on a link whose displayed form is shorter than its text:

- `mouse-1-click-follows-link` turns a click into a follow only when the release
  is a plain `mouse-1`. Emacs calls the release a drag once the pointer moved
  more than `double-click-fuzz` pixels, which a hand on a trackpad does.
- Binding `mouse-1` directly fails in Org. The press is a command of its own
  that moves point, and its `post-command-hook` runs before the release is read.
  In an Org buffer that is where `org-appear` reveals the link's raw text, so
  the rest of the line slides right and the release lands somewhere else. That
  was the "first click reveals the syntax, second click opens" bug.

So `ps/open-down-click` on `down-mouse-1` follows the link at once, inside
`save-excursion`, and off a link falls through to `mouse-drag-region` as before.
The release commands (`ps/open-click`, `ps/open-drag-click`) then stand down if
the press followed something. `mouse-1-click-follows-link` is turned off
buffer-locally wherever this is installed; left on, it rewrote the release into
a `mouse-2`, which in the Info Triage queue opened the item a second time. A
link is anything with `mouse-face`, the one marker Org, Markdown and Dired all
put on exactly the clickable text.

### Back and forward

**One trail across every kind of buffer**, per window, with `‹ ›` on the mode
line (`ps/nav-back`, `ps/nav-forward`). Emacs has `pop-global-mark`,
`org-mark-ring-goto`, Dired's `^`, and histories in eww and Info, each knowing
one kind of thing; a trail from a queue to an item's index to its folder to a
file crosses three of them in four steps.

**The history lives in window parameters**, so two windows keep independent
trails and closing a window forgets its own.

**A place is where to reopen something, not what was open**: a file path, a
directory, or for a generated buffer the buffer itself. Paths are load-bearing:
`dired-kill-when-opening-new-dired-buffer` kills a folder listing as you
descend out of it, so the buffer is gone by the time you press back.

**The trail is recorded twice on purpose.** The window helpers call
`ps/nav-note-departure` as they navigate, which is synchronous;
`window-buffer-change-functions` catches everything else, but only at
redisplay. `ps/nav--push` collapses repeats, so the overlap costs nothing.

## Constraints and traps

- **Remember whether the press followed a link**, globally
  (`ps/open--press-followed`). Following a link usually replaces the buffer in
  that window, so by the time the release arrives, asking "was this press on a
  link?" asks the *new* buffer about the wrong text, gets no, and runs
  `mouse-set-region` across whatever just opened. Clicking Dired's `..` showed
  it every time.
- **The release bindings are global.** A release goes to whatever buffer is
  current by then, which after a follow is usually one with no bindings of
  ours: clicking a `.json` file in the listing set an active mark in the JSON
  buffer, and scrolling grew a region down the file.
- **A drag that never moved is a click.** Trackpad wobble turns a click into a
  zero-length drag, and `mouse-set-region` on one leaves an active empty region
  that opens up on the next scroll (`ps/open--event-stationary-p`).
- **Select the clicked window, don't wrap in `with-selected-window`.** Wrapping
  restored the old selection, so the pane you were reading was not the selected
  one, and `‹` walked some other window's trail.
- **`window-buffer-change-functions`' default value is called with a frame**,
  not a window; only a buffer-local entry receives a window. The recorder once
  checked for a window and so recorded nothing at all, leaving only the
  synchronous path working.
- **The nav buttons must be in both mode lines**, and outside the planning mode
  line's per-window cache; see [mode-line.md](../interface/mode-line.md).
- **After a vault switch the trails are forgotten**, or back would walk out of
  the new vault into the old one ([vaults.md](../foundations/vaults.md)).
- **Obsidian links carry their own keymap** (`ps/obsidian-link-map`), which
  predates the general click model and opens on the press the same way. It
  stays because it hangs off the link text rather than a mode.

## Rejected

- **Advising `find-file`** (above).
- **`mouse-1-click-follows-link`**, and **binding `mouse-1`** (above).
- **Recording the buffer rather than the path** (above).
