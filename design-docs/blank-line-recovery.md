# Blank-line recovery after edits in mobile apps

Internal design note. Not user documentation.

**Status: designed, not implemented.** Replaces `lisp/ps-blank-lines.el`
(`ps/blank-lines-reinsert`, F7), whose rule-based reinsertion recovers only a
small fraction of the blank lines that are actually lost.

## The problem

Org files are edited on the desktop (Emacs, occasionally VS Code) and on mobile
(Beorg, Orgzly). Desktop edits preserve blank lines exactly. Mobile edits do
not: both apps parse a heading into *(heading line, content string)* and trim
the content string's leading and trailing whitespace on write. Beorg can
reinsert blank lines from a small set of level-based settings; Orgzly reinserts
nothing.

The files reach the desktop through Dropbox, and the periodic git sync
(`lisp/ps-git-sync.el`) commits whatever is on disk. So the damage is recorded
in git — and so is the undamaged version that preceded it.

Blank lines carry real meaning in these files (paragraph breaks, section
separation) and their placement is deliberate and not fully rule-describable.
The goal is to recover *the blank lines that were actually there*, not to
re-derive them from a style rule.

## Evidence

All measurements below were taken on the live org repo
(`~/Library/CloudStorage/Dropbox/notes/org`, 35 `.org` files excluding
`Journal/`, `Archive/`, `init.org`, `workspace.org`).

### What the mobile apps actually destroy

Classifying every blank line removed by the seven pure-strip commits in history
(commits whose entire diff is blank-line deletions):

| position of destroyed blank | count |
|---|---|
| heading → its own first body line | 111 |
| last body line → next heading | 104 |
| strictly inside a body | 1 position (one run) |
| heading → heading | 0 |

Before/after on one file across a single strip commit (`e2fb13e`,
`Areas/Programming.org`):

| | before | after |
|---|---|---|
| blank between heading and its body | 10.0% (12/120) | **0.0%** |
| blank between two body lines | 0.6% (1/170) | 0.6% (unchanged) |
| blank before a heading | 9.7% (22/226) | 5.8% (13/226) |

**Conclusion: body interiors survive the round trip; the boundaries around them
do not.** This is what makes the block model below both correct and safe.

### Where blank lines sit in an undamaged file

P(blank) immediately before a heading, by the level of that heading:

| next heading | with blank | rate |
|---|---|---|
| `*` | 243/243 | **100%** |
| `**` | 339/1595 | 21% |
| `***` | 11/1456 | ~0% |
| `****` | 0/68 | 0% |

Levels 1, 3 and 4 are fully determined by the following heading. Level 2 — the
ambiguous 21% — is determined by what *precedes* it:

| boundary into `**` | with blank | rate |
|---|---|---|
| prev `*` **with** body prose | 147/173 | 84% |
| prev `*` no body (first child) | 0/99 | 0% |
| prev `**` with body (plain sibling) | 9/1110 | 0.8% |
| prev `**` no body | 5/24 | 20% (small n) |
| prev `***` | 173/184 | 94% |
| prev `****` | 5/5 | 100% (small n) |

Read as intent: a blank line marks **a change in outline shape** — a new
top-level section, a parent's prose handing off to its children, or a nested
block closing. Not between plain sibling tasks (the 1110-instance dominant
case, at 0.8%).

Blank lines strictly between two body lines:

| | with blank | rate |
|---|---|---|
| inside a heading's body | 28/784 | 3.6% |
| in the file preamble | 171/341 | **50.1%** |

Gap run lengths across the corpus: 823 × 1, 3 × 2, 1 × 3. Runs are almost
always a single line, but run length is preserved verbatim rather than
normalised, so the four exceptions survive.

### Measurement caveat — the corpus is post-damage

111 heading→body blanks and 104 boundary blanks were destroyed and never
restored. The working tree therefore *understates* exactly the gaps this
feature exists to recover. Concretely, "blank between a heading and its first
body line" measures 2/2977 (0.07%) in the working tree but was 10% in the same
file before the strip commit.

**Consequence for the design:** the fitted rule must be fitted on the
healthiest-ancestor versions the engine already fetches, never on the working
tree. Fitting on the working tree teaches the model the damage.

## Requirements

**Hard requirement.** Content is never altered. Only blank lines are inserted
or removed. Enforced two ways:

1. *By construction* — body interiors are carried through as opaque strings and
   are never parsed, diffed or rewritten.
2. *By verification* — before any proposed file version is shown or written,
   `strip_blanks(proposed) == strip_blanks(current)` must hold: identical
   non-blank lines, identical order, identical count. A file that fails is
   dropped from the run with a diagnostic, never offered.

**Other requirements**

- Recovery is an **explicit user action**. Nothing rewrites files automatically.
- Every change is **reviewed before it is written**, file by file, via ediff.
- The user never encodes their blank-line style. Any rule used is *measured*
  from their own corpus at run time.
- The command never runs a git write command — only `git log` and `git show`.

**Non-goals**

- Fixing the mobile apps, or negotiating with them.
- Preserving anything other than blank lines (trailing whitespace, tag column
  alignment, property drawer formatting are all out of scope).
- Running on non-Org files.

## Model

### The representation is an explicit tree

A file parses into a **tree of nodes** — never into a flat line sequence with a
parallel gap vector. The distinction is not cosmetic. Reordering headings changes
only their order, but reordering lines inside prose destroys its meaning, so a
node's body must be atomic: it is carried **verbatim as one opaque string,
internal blank lines included**, never split into lines, never aligned
line-by-line, never reordered. Only whole bodies are ever compared or swapped.

The tree is also what makes the ownership rule below expressible at all: it turns
on the *level relationship* between adjacent nodes, which a flat representation
does not have.

A node carries exactly two gap parameters:

- **`lead`** — the blank run immediately *after* this node's heading line,
  whatever follows: the node's own body, or its first child's heading.
- **`sep`** — the blank run immediately *before* this node's heading line.
  **`nil` when the node is the first content inside its parent**, because that
  gap is then the parent's `lead`. So `sep` and `lead` never describe the same
  blank run.

Plus two document-level slots, `bof` (blanks before the first content line) and
`eof` (trailing blanks). Between them, `lead`, `sep`, `bof`, `eof` and the opaque
bodies account for every blank line in a file exactly once.

`sep` is *stored* on a node but *resolved* on the edge — see the ownership rule.
Storage location and resolution key are different things.

Two consequences worth stating, because both remove machinery that a flat model
would need:

- **A blank line inside `#+begin_src` is unreachable.** It lives inside a body
  string. Under a flat model it would sit between two ordinary body lines, be
  classified as a boundary gap, and could be resolved to 0 — deleting a line that
  *is* content. Under the tree there is nothing to protect it *from*.
- **Rendering cannot alter content.** The engine writes only to `lead`, `sep`,
  `bof` and `eof`, which are integers. Heading lines, body strings and child order
  are copied from the working tree untouched.

### Gap ownership

For a gap sitting between content lines X and Y:

> **If X is a heading and Y is inside X's subtree** — Y is X's own body line,
> *or* `level(Y) > level(X)` — the gap is **`lead(X)`**: internal to block X,
> restored verbatim from the matched ancestor block, travelling with X when it
> moves, never rule-driven.
>
> **Otherwise** — X is a body line, or `level(Y) <= level(X)` — the gap is a
> **boundary gap**, keyed on the ordered pair `(X, Y)`.

A boundary gap is keyed on the **pair**, not on either endpoint: it is neither
"Y's leading gap" nor "X's trailing gap". Endpoints are matched by *block
identity from the tree alignment, not by raw text*, so a `TODO` → `DONE` toggle
leaves both of a block's edges intact.

A boundary gap is *stored* in the `sep` of the node that follows it — that is
simply the slot a blank run before a heading line lives in — but it is *resolved*
by looking up the ordered pair. Storing it on the node does not make it a
property of the node.

The level test in the first clause is load-bearing. Two worked cases:

**Reorder under a bodyless parent.** `level(** 1) > level(* A)`, so the blank
belongs to A, not to the edge `(A → 1)`:

```
ancestor          after mobile reorders 1 and 2         recovered
* A               * A                                   * A
                  ** 2                                  ← lead(A) = 1
** 1              ** 1                                  ** 2
** 2              ** 3                                  ** 1
** 3                                                    ** 3
```

Had the blank been keyed on the edge `(A → 1)`, the reorder would break that
edge, the new edge `(A → 2)` would fall to the fitted rule, and the rule's
"level-2 first child under a bodyless level-1 parent" cell (0/99) would return
0 — silently deleting the blank.

**A closing separator.** Here `level(** 2) <= level(*** y)`, so the blank is
*not* `lead(y)` — it is a boundary gap that belongs where it is, and does not
wander off if `y` moves:

```
** 1
*** x
*** y
          ← boundary gap (prev *** → next **, 94%)
** 2
```

### Preamble

The text before the first heading is the body of a headless root node, and is
therefore opaque like any other body. Its paragraph breaks — the densest
blank-line region in the corpus at 50.1% — are preserved by never being touched,
rather than by being remembered and restored. The evidence says the mobile apps
do not damage it (the single destroyed body→body blank was inside a heading
body), so preservation is sufficient.

### Recovering damage inside a body

Because bodies are opaque, intra-body blank lines cannot be repaired
line-by-line — and should not be, since that would mean aligning prose. One safe
special case covers the residual:

> If a matched node's ancestor body and working-tree body have **identical
> non-blank lines** but differ in blank lines, adopt the ancestor's body string
> wholesale.

Content is provably unchanged (the non-blank lines are equal by the test itself),
nothing is reordered, and no line-level alignment is involved. This recovers the
one intra-body loss observed in the history, and the preamble too if it ever
turns out to be damaged. In every other case the working-tree body wins,
untouched.

## Algorithm

```
for each org file:
  1. select the healthiest ancestor version from git
  2. parse ancestor and working-tree version into block trees
  3. match blocks (fuzzy, on identity score)
  4. resolve every gap in the working-tree version
  5. verify the strip-invariant
  6. emit a proposed version + a per-gap provenance record
```

### 1. Ancestor selection

For each file, walk back the commits touching it within a window (default: 5
commits or 1 day, whichever comes first; a day limit of 0 means any age). Align each candidate to the
working-tree version and pick the one yielding the most recoverable gaps, ties
broken toward the most recent.

No commit attribution is needed — we never ask *who* made a commit, only which
ancestor has the richest gap structure. This is deliberate: attribution by
"which files Emacs saved" would have been wrong for VS Code edits, which are
good edits that Emacs never sees.

### 2. Parsing

Use `org-element-parse-buffer`. No custom parser.

Verified on Org 9.7.11 in this Emacs — `:pre-blank` on a headline **is**
`lead`, with exactly the semantics derived above, including the bodyless-parent
case:

```
input                    parsed
* A                      level=1  pre-blank=1   ← blank between A and its first child
                         level=2  pre-blank=0
** 1                     level=2  pre-blank=1   ← blank between "** 2" and its body
body of 1                level=3  post-blank=1  ← closing separator before "** 3"
                         level=2  pre-blank=0
** 2
...
```

`:post-blank` is the trailing gap, attached to the innermost preceding element.
We use org-element to *extract*, but not its `:post-blank` **ownership policy**:
that is pure trailing ownership, so a moved element would carry a boundary gap
away with it and a level-1 seam would silently lose its blank.

The ancestor version arrives as a string from `git show`; parse it in a temp
buffer:

```elisp
(with-temp-buffer
  (insert text)
  (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
  (org-element-parse-buffer))
```

**Never regenerate the file from the AST.** `org-element-interpret-data` would
rewrite content. The AST is used for structure, identity and positions only;
the output is produced by surgical blank-line inserts and deletes on the
working-tree text.

### 3. Block identity and matching

org-element supplies the identity fields already normalised — no hand-rolled
stripping of keywords, priorities or tags:

| property | use |
|---|---|
| `:raw-value` | headline text with stars, TODO keyword, priority cookie and tags removed |
| `:level` | structural |
| `:todo-keyword`, `:priority`, `:tags` | excluded from identity (they are what mobile edits change) |
| `:contents-begin` / `:contents-end` | body extracted verbatim as a string |

Similarity score, using the built-in `string-distance` (Levenshtein):

| signal | weight | rationale |
|---|---|---|
| normalised title (`:raw-value`) | high | survives TODO/priority/tag edits, the common mobile edit |
| body similarity (line-set Jaccard) | high | disambiguates same-titled siblings; byte-identical on a pure state toggle |
| outline path (parent chain of `:raw-value`) | medium | anchors within the tree |
| level | medium | a promote/demote should still match, but cost something |
| sibling index | low | tiebreak only |

Greedy best-match with a confidence floor. Blocks below the floor are treated as
new, fall to the fitted rule, and are flagged in the review summary — an
uncertain match is visible, never silent.

Treating the block as the matching unit is what makes the body *evidence*
rather than something to align. A `TODO` → `DONE` toggle changes one word of
the title and leaves the body byte-identical, which is a near-certain match.

### 4. Gap resolution

**`lead(B)`** — copy verbatim from the matched ancestor block. Unambiguous, no
ladder, no rule. Travels with the block unconditionally.

**Boundary gaps** — ladder, first match wins:

1. **Exact edge.** The ancestor had X immediately followed by Y (by matched
   identity) → copy the gap verbatim, including run length.
2. **Predecessor half-edge.** The ancestor had X with some trailing gap → adopt
   it. Handles "the block that followed X was swapped out". The *predecessor* is
   the right half to use: level-1 seams are 100% regardless of predecessor, and
   level-2 seams are determined by the predecessor (84% / 94% / 0.8%).
3. **Fitted rule** (below).
4. **0.**

Steps 3 and 4 are the only rule-driven paths in the whole design, and they fire
only at seams created by a move, an insertion or a deletion. On a typical mobile
session — toggle some states, add a task, add a note — that is a handful of gaps
per file, sometimes zero.

**`bof` / `eof`** — copy verbatim from the ancestor when the file matched at all;
otherwise keep the current value.

**Bodies** — the working-tree body wins, except for the identical-non-blank-lines
swap described above.

### 5. The fitted rule

Fitted at run time from the healthiest-ancestor versions, not hand-written and
not fitted on the working tree (see the measurement caveat). Fitted corpus-wide;
the per-file rates were not bimodal, so per-file fitting is not justified.

For a boundary before heading H, with `L = level(H)`, `P = level of the nearest
preceding heading`, `body = ` whether prose intervened:

```
L = 1                    → gap 1        (243/243, 100%)
L >= 3                   → gap 0        (11/1524, ~0%)
L = 2 and P < L and body → gap 1        (147/173, 84%)
L = 2 and P < L, no body → gap 0        (0/99, 0%)
L = 2 and P > L          → gap 1        (173/184, 94%)
L = 2 and P = L          → gap 0        (14/1134, ~1%)
```

Exposed as `ps/blank-lines-new-edge-strategy`: `learned` (default) or `zero`
(never guess; return 0 at new edges). `zero` costs exactly the cases where the
answer is most certain — a level-1 section moved or newly typed on mobile would
land with no blank before it, wrong 100% of the time by the corpus.

### 6. Full restore, not insert-only

The proposed version sets every managed gap to its resolved value, which means
blank lines are sometimes **removed** — specifically the ones Beorg reinserts
from its own level rules where the user does not want them. This still satisfies
the hard requirement (no content is touched). Removals are counted and displayed
separately in the summary so they are never a surprise.

## Detection

"Which files were edited externally with blanks removed" is answered by
**running the recovery in dry-run mode and counting proposed changes**. One
engine, one code path.

A separate density-based heuristic would miss Beorg entirely: Beorg's
reinsertion makes level-1 conformance look perfect while body and level-2 gaps
are gone.

## User-facing surface

```
Productivity → Recover blank lines from history

  → scan  → summary buffer:
       Work/Programming.org   21 restored, 0 removed   (from HEAD~14, 2026-07-18)
       Areas/Inbox.org         3 restored              (from HEAD~2)
       Areas/Piano.org         — no changes
  → d / RET  → ediff current vs. proposed, one file at a time
  → on quit: write if accepted, skip if not, advance to next file
```

### Deciding from the report

Ediff is for the cases that need looking at, not the common path. Each row
already carries the reason for every blank line it would restore, so `1`
accepts a whole file, `2` dismisses it, `A` accepts everything — and accepting
advances to the next row, so a report is worked through with `1 1 1`. That path
does not open ediff at all; it writes via `replace-buffer-contents`, which
keeps point, markers and folding and touches only the lines that differ.

Rows are updated **in place**. Re-scanning after each decision would be
authoritative but costs seconds per file and destroys the user's place in the
report they are working through; `g` is there for when the authoritative state
is wanted.

### The ediff review loop

**Buffer A is the file, buffer B the proposal — left is what you have, right is
what you would end up with, the diff-review convention.** Both are editable, so
both of ediff's copy keys mean something: `b` applies a change into the file,
`a` drops one from the proposal. The review therefore starts from **everything
accepted** — the right default, since these are blank lines the user already
typed — while still supporting the change-at-a-time reading.

What gets written is decided by `ps/blank-lines-review--outcome`: a
hand-modified A wins, otherwise B. `+` (accept everything) and `x` (drop
everything) reset *both* sides, precisely so that question cannot arise after
them. Both keys come from what stock ediff leaves free; `!` is *not* free
(`ediff-update-diffs`). `ediff-mode-map` is `ediff-defvar-local`, so none of
this escapes the session.

**Neither side may be made read-only.** It was tried, and it fails twice over:
ediff's copy commands bind `inhibit-read-only`, so the flag does not stop them
and the key would have to be disabled separately; and `buffer-read-only` is
commented out of `ediff-protected-variables`, so ediff restores
`mode-line-format` but not the read-only flag, stranding the user with a file
buffer they cannot type in. More simply, a read-only left side makes
change-at-a-time review impossible, which is the reading it exists to support.

**There is no review-all queue.** One file at a time, opened from the report by
`d`, `RET` or clicking the name. Walking every file was more machinery than the
report needs — the report is where files are chosen and where the answer goes
back — and the advance-to-next-file step was the part users could not see
working.

Two things ediff does that the session has to undo:

- It opens with **no difference selected** (`ediff-current-difference` is -1),
  so `a` and `b` fail with "Bad diff region number, 0" until the user presses
  `n`. The session calls `ediff-jump-to-difference 1` so it opens ready to act.
- On a graphical display it defaults to **frames of its own** and to stacking A
  above B. The review sets `ediff-setup-windows-plain` and a horizontal split
  for the duration and restores both afterwards. They have to be set globally,
  not buffer-locally: `ediff-setup-windows` does read the setup function out of
  the control buffer, but the first layout runs inside `ediff-buffers`, before
  that buffer exists to configure. The file tree is hidden first because
  `ediff-setup-windows-plain-compare` calls `delete-other-windows`.

The report stays on screen throughout by living in a **side window** — the one
kind `delete-other-windows` leaves alone, so it survives every session in the
queue without a custom window-setup function. Two window parameters carry that:
`no-delete-other-windows`, and `no-other-window` so ediff's `(other-window 1)`
cannot drop buffer A into the report. A main window must be selected before
ediff runs, since `delete-other-windows` signals an error on a side window.

Opening the report has the mirror-image problem, and it produced the worst bug
this feature has had: pressed from the file tree, F7 appeared to do *nothing*,
and the next press worked. A side window is dedicated with the value `side`,
not `t`, and `switch-to-buffer` refuses only the latter — so `ps/window-show-here`
quietly rendered the report inside the tree's own narrow slot, and the next
press cleared it away via `ps/blank-lines--drop-stray-windows` and then had a
content window selected. The fix belongs in `ps/window--select-main`
(`ps-window.el`), not here: every view opened that way had the same bug.

It sits on the **right**, where the report already was: the file tree owns the
left, so the diff opening on the left is the diff taking the *tree's* place,
not the report's. Its width is measured *before* the tree is hidden and passed
through, or the report visibly grows into the freed columns just as the user
starts reading the diff beside it.

Deciding a file from the report (`1`/`2`) cancels any review first. The diff on
screen asks a question that has just been answered elsewhere; leaving it up
would show a comparison that no longer describes anything, and its highlights
would point at differences that no longer exist.

The report itself is `truncate-lines`, and its rows are sized for a narrow
window: paths relative to the Org directory rather than the git root, and
one-word provenance labels (`edge`, `half`, `rule`, `kept`, `new`) with the
full sentence on the line's `help-echo`. Wrapping turned the table into a wall
in the side window; widest row is now 55 columns. The header counts only the
files with something left to decide — the number scanned is a fact about the
scan, not about the work.

Two report-level traps, both found by use rather than by reading:

- **`push-button` does not move point on a mouse click.** It locates the button
  from the event and calls the action; point stays where it was. An action that
  reads the row "at point" therefore acts on whatever row the user last moved
  to, so clicking one file opened another's diff and the following `1` accepted
  that other file. The action must take its result from `(button-start button)`
  and move point there.
- **Every write path must bind `inhibit-read-only`.** An Org buffer can be
  read-only for reasons that have nothing to do with recovery, and an accepted
  proposal must not come back as "Buffer is read-only".

`-`/`+` step the ancestor window through `ps/blank-lines-ancestor-steps`, a
ladder of (commits . days) rungs; `c`/`y` set either number outright. A ladder
rather than a scale factor, because halving could not land on every value that
matters — a file edited once on the phone is exactly one commit — and was not
reversible, so `-` `-` `+` `+` left the window somewhere the user never chose.
Both limits still move together on a step, on purpose: git ANDs `-n` and
`--since`, so raising only `ps/blank-lines-ancestor-max-commits` does nothing
whenever `-max-days` is the binding one, and a control that silently does
nothing is worse than none. Typing an exact number is the escape hatch from
that coupling, and `y 0` drops `--since` entirely.

The proposal buffer runs `org-mode` with its hooks — not under
`delay-mode-hooks` — so the right pane is fontified and prettified like the
file beside it. A review is a comparison; the two sides have to be comparable.

**The exit ordering is load-bearing and was verified, not assumed.**
`ediff-really-quit` runs, in order:

| step | | still alive |
|---|---|---|
| `ediff-cleanup-hook` | | A, B, control |
| `ediff-janitor` | may kill *unmodified* variants | |
| `ediff-quit-hook` | local entries first, then global `ediff-cleanup-mess` | A, B, control |
| `ediff-after-quit-hook-internal` | buffer-local part only | nothing |

`add-hook … nil t` puts an entry in the local value ahead of the `t` that
stands for the global one, so a local `ediff-quit-hook` entry is the last point
at which both buffers exist — that is where the save goes. Advancing to the
next file must wait for `ediff-after-quit-hook-internal`, since the previous
session is not torn down until then. `ediff-keep-variants` is set
buffer-locally in the control buffer because `ediff-janitor` reads it there;
without it, a user who has customized it away from `t` gets a prompt about
killing their own file buffer in the middle of the exit path. A modified
file-visiting buffer A survives janitor regardless, which is exactly the accept
case.

### Three guards before the disk

1. **Staleness.** A file whose buffer is modified, or whose text no longer
   matches what the scan read, is skipped rather than reviewed — a proposal
   describes one specific version, and applying it to a newer one would revert
   whatever came in between. This is the guard that matters most in practice,
   because the sync can pull mid-review.
2. **Modification.** Nothing is written unless the review left buffer A
   modified, so quitting without accepting anything is a no-op.
3. **Strip invariant, again.** Before saving, the buffer is compared to the
   scanned text with blank lines removed. Equal means only blank lines changed.
   Unequal means the review edited content — never saved without an explicit
   `yes-or-no-p`, because that can only have come from the user's own typing.

Every proposed version passes the strip-invariant before it is shown. Each
change carries provenance in the summary — `from HEAD~14` / `rule: parent prose
→ first child, 84%` / `uncertain match` — so a wrong proposal can be understood,
not just rejected.

Replaces the current F7 binding and menu entry.

**Passive indicator (follow-up, not part of the core).** The same dry run, in a
background process, triggered *only when a sync has pulled changes* — never on a
timer — lighting a mode-line badge. Cached by file hash.

## Source of truth: git history, no sidecar

A sidecar written from `after-save-hook` goes stale exactly when the user edits
in VS Code, and a later mobile edit would then be recovered against an outdated
snapshot, silently. Git sync commits whatever is on disk regardless of which
editor produced it, so git history is the only source that captures all good
edits. Not used even as a cache — the cost of a stale cache here is wrong
output, and the git read is cheap.

## Testing

The command never runs a git write, so testing is safe with sync off (which it
already is in `scripts/run_emacs_dev.sh`, deliberately — otherwise the dev run
would commit this repo rather than the org files).

**Pure core (ERT, `tests/test-ps-blank-lines.el`).** `parse → match → resolve →
render` as string-in/string-out functions with no I/O. Fixtures:

| fixture | asserts |
|---|---|
| pure strip, no content change | every gap restored |
| strip + a content edit in the same commit | gaps restored, edit preserved |
| `TODO` → `DONE` toggle | block still matches; both its edges stay exact |
| new task added on mobile | falls to the fitted rule, gap 0 next to a sibling |
| subtree moved within the file | interior verbatim; only the two seams recomputed |
| subtree promoted / demoted | match survives the level change |
| **`* A` / `** 1 ** 2 ** 3` reordered** | `lead(A)` stays with A — the named case above |
| sibling reorder under a parent *with* body | predecessor half-edge, then rule |
| `*** y` moved out from a closing separator | separator stays; not carried off as `lead(y)` |
| Beorg over-insertion | spurious blanks removed, counted separately |
| body lines reordered inside a node | body byte-identical in the output |
| blank line inside a `#+begin_src` block | untouched; never surfaces as a gap |
| body damaged in blanks only | whole-body swap fires; content equal |
| block deleted on mobile | neighbouring seam resolved, no orphan gap |
| preamble paragraphs | restored verbatim |
| gap run of length 2 | preserved, not normalised to 1 |
| BOF / EOF gaps | preserved |
| no trailing newline / CRLF | not corrupted |

Every fixture additionally asserts the strip-invariant on its output.

**Git layer (ERT).** Tests `git init` a repo in the scratchpad, commit fixture
files, commit a synthetic strip, and exercise ancestor selection against it. No
network, no remote, nothing near the real repos.

**Manual playground.** A dev script copies `samples/realistic/` *out* of this
repo into the scratchpad, `git init`s it there, and synthesises a history
including strip commits; dev Emacs then runs with `my-org-base-directory`
pointed at that copy. This also removes a standing hazard: the samples currently
live inside the config repo, so a sync during a dev run would touch the wrong
repo. The sample files need realistic blank lines added for this to be
meaningful.

## Decisions

| decision | rationale |
|---|---|
| Explicit command only, never automatic | External edits are infrequent; unreviewed rewriting of prose files is not worth the risk |
| Review every file via ediff before writing | Matches the user's existing review workflow |
| Full restore (insert **and** remove) | The only way to fix the Beorg half of the problem; still touches no content |
| Memory beats rules at surviving edges | Preserves the 16% of cases that contradict the fitted rule |
| Gaps keyed on the ordered pair, not an endpoint | Neither endpoint alone predicts the gap (100% by successor at level 1; by predecessor at level 2) |
| `lead` is a block property, decided by level | Otherwise a sibling reorder under a bodyless parent silently deletes the blank |
| Block = heading + opaque body | Mobile apps damage only the boundaries; makes the hard requirement true by construction inside bodies |
| Explicit tree, not lines + a gap vector | Reordering headings is meaning-preserving; reordering prose lines is not, so bodies must be atomic. The ownership rule also turns on adjacent node *levels*, which a flat model does not have |
| Exactly two gap slots per node (`lead`, `sep`) + `bof`/`eof` | Accounts for every blank line once, with no overlap and no ambiguity at render time |
| Intra-body damage fixed only by whole-body swap | Repairs the residual case without ever aligning prose line-by-line; content equality is the precondition, so it cannot change content |
| All files per run | Catches damage committed days ago; revisit if slow |
| Rule fitted corpus-wide, at run time, from ancestors | Per-file rates were not bimodal; the working tree is post-damage |
| git history, no sidecar | A save-hook sidecar goes stale on VS Code edits |
| No commit attribution | Not needed, and it would have been wrong for VS Code edits |
| Dry run in background only after a sync pulls | Avoids a polling timer |

## Open questions

- Confidence floor for block matching — needs tuning against the fixtures once
  the matcher exists.
- ~~Ancestor window defaults (50 commits / 30 days) are guesses; measure on the
  real repo.~~ Settled from use: a phone edit is one commit, and a mangled file
  is opened again in Emacs the same day or the next, so 5 commits / 1 day.
- Whether the preamble path ever fires in practice. If it never does after some
  months of use, it can be dropped.

## Follow-up work

- Passive mode-line indicator (above). Not started.
- Ancestor selection costs ~22.7s for 37 files, all of it `git show` per
  candidate. `git cat-file --batch` is held in reserve if that becomes annoying
  now that the command is used for real.
- `ps/blank-lines-match-floor` (0.55) is still the original guess. Nothing has
  argued against it yet.

## A known oscillation, and why it is not a bug in recovery

Applying a recovery and then re-scanning can propose the exact inverse, if the
pre-recovery spacing is *also* in history as a commit. Ancestor selection
scores a candidate by how many blank lines it would restore, so once the
working tree has been healed, the commit holding the old spacing "restores"
whatever the recovery removed, wins, and proposes reverting.

This needs a corpus whose history contains two *deliberately different*
spacing styles. Measured:

| corpus | scan | after accepting | again |
|---|---|---|---|
| real damage (playground) | `+25 −0` | `+0 −0` | `+0 −0` |
| `samples/realistic` in this repo | `+47 −20` | `+20 −47` | `+20 −47` |

The samples oscillate because the commit that restyled them wholesale is in
this repo's history alongside the pre-restyle commits; real mobile damage only
ever *removes* blank lines, so there is no competing style to flip back to and
the scan settles at zero. The `−N` count is the tell in both cases: a healthy
run against real damage has no removals at all.

Left as is, because the fix would be to make recovery insert-only, and *full
restore* was chosen deliberately (§6) — Beorg's rule-based reinsertion puts
blank lines where the user never had them, and removing those is real
recovery.

## Verification record

- Elisp suite: 816 tests green.
- Replay of the 7 real strip commits in the author's org repo: 6/7 byte-exact,
  the 7th differing only by one trailing blank at EOF — the deliberate
  consequence of the ladder keeping unknown gaps rather than zeroing them.
- Playground (`scripts/make_blank_line_playground.sh`): the scan finds exactly
  the 4 damaged files, `+25 −0`, each attributed to the last healthy commit,
  matching the blank lines the script destroyed file for file. Driving the real
  review loop with accept-all restores 3 of them **byte-identical** to the
  pre-damage commit; the 4th differs only by the two siblings the script
  reordered afterwards — correctly preserved, with its blank-line count back to
  the pre-damage 9. A second scan then proposes nothing.
