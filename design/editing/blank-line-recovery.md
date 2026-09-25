# Blank-line recovery

Recovering the blank lines that mobile Org apps strip out, by copying them from
the healthiest earlier version of the file in git.

**Status:** built
**Code:** `lisp/ps-blank-lines.el` (entry point, `ps/blank-lines-recover`,
F7), `-tree.el` (representation), `-engine.el` (matching and resolution),
`-git.el` (the only place git runs), `-review.el` (the only place files are
written); settings block `** Blank line recovery (ps-blank-lines.el)`. User
docs: `docs/Sync-and-backups.org` → "Recovering blank lines".

## Problem

Org files are edited on the desktop (Emacs, sometimes VS Code) and on the phone
(Beorg, Orgzly). Desktop edits keep blank lines exactly. The mobile apps do
not: both parse a heading into a heading line plus a content string and trim
the string's leading and trailing whitespace when they write it back. Beorg can
reinsert blank lines from a few level-based settings; Orgzly reinserts nothing.

The files reach the desktop through Dropbox, and git sync
([data-safety.md](../foundations/data-safety.md)) commits whatever is on disk.
So the damage is recorded in git, and so is the undamaged version before it.

Blank lines carry meaning in these files (paragraph breaks, section separation)
and are placed deliberately, not by a rule. The goal is to recover the blank
lines that were actually there, not to re-derive them from a style.

## Evidence

Measured on the author's own notes: 35 Org files, excluding the journal, the
archive and the two configuration files.

### What the mobile apps destroy

Every blank line removed by the seven commits in history whose whole diff is
blank-line deletions:

| position of the destroyed blank | count |
|---|---|
| heading → its own first body line | 111 |
| last body line → next heading | 104 |
| strictly inside a body | 1 run |
| heading → heading | 0 |

One file across one such commit:

| | before | after |
|---|---|---|
| blank between a heading and its body | 10.0% (12/120) | **0.0%** |
| blank between two body lines | 0.6% (1/170) | 0.6% (unchanged) |
| blank before a heading | 9.7% (22/226) | 5.8% (13/226) |

**Body interiors survive the round trip; the boundaries around them do not.**
That is what makes the model below both correct and safe.

### Where blank lines sit in an undamaged file

The chance of a blank line immediately before a heading, by that heading's
level:

| next heading | with blank | rate |
|---|---|---|
| `*` | 243/243 | **100%** |
| `**` | 339/1595 | 21% |
| `***` | 11/1456 | ~0% |
| `****` | 0/68 | 0% |

Levels 1, 3 and 4 are decided by the heading itself. Level 2, the ambiguous
21%, is decided by what comes before it:

| boundary into `**` | with blank | rate |
|---|---|---|
| after a `*` with body prose | 147/173 | 84% |
| after a `*` with no body (first child) | 0/99 | 0% |
| after a `**` with body (plain sibling) | 9/1110 | 0.8% |
| after a `**` with no body | 5/24 | 20% (small n) |
| after a `***` | 173/184 | 94% |
| after a `****` | 5/5 | 100% (small n) |

Read as intent: a blank line marks **a change in outline shape**. A new
top-level section, a parent's prose handing over to its children, or a nested
block closing gets one; plain sibling tasks, the dominant case, almost never do.

Between two body lines, a blank appears 3.6% of the time inside a heading's
body and 50.1% in the file's preamble. Runs are nearly always one line (823
single, 3 double, 1 triple); run length is preserved rather than normalised.

### The corpus is post-damage

The working tree has already lost the gaps this feature exists to recover. A
blank between a heading and its first body line measures 0.07% in the working
tree, against 10% in the same file before the strip. **So the fitted rule is
fitted on the ancestor versions the engine fetches, never on the working
tree**, or it would learn the damage.

## Requirements

**Content is never altered; only blank lines are inserted or removed.** This is
enforced twice:

1. *By construction*: body interiors are carried as opaque strings and never
   parsed, diffed or rewritten.
2. *By verification*: every proposal must satisfy
   `strip_blanks(proposed) == strip_blanks(current)` (same non-blank lines, same
   order, same count) before it is shown, and again before it is saved. A file
   that fails is dropped with a diagnostic, never offered.

Also:

- Recovery is an explicit command. Nothing rewrites files on its own.
- Every change is reviewed before it is written.
- The user never writes down their blank-line style. Any rule is measured from
  their own files at run time.
- Only read-only git commands run, enforced by an allowlist in `-git.el`
  (`log`, `show`, `rev-parse`, `cat-file`, `ls-tree`).

Out of scope: fixing the mobile apps; any whitespace other than blank lines
(trailing spaces, tag alignment, drawer formatting); non-Org files.

## Model

### An explicit tree

A file parses into a **tree of nodes**, never into a flat list of lines with a
parallel list of gaps. The difference matters. Reordering headings changes
only their order, but reordering lines inside prose destroys it, so a node's
body is **one opaque string, internal blank lines included**: never split,
never aligned line by line, never reordered. Only whole bodies are compared or
swapped. The tree is also what makes the ownership rule below expressible,
since it depends on the levels of adjacent nodes.

Each node has exactly two gap slots:

- **`lead`**: the blank run immediately *after* the node's heading line,
  whatever follows (its body, or its first child's heading).
- **`sep`**: the blank run immediately *before* the node's heading line. It is
  `nil` when the node is the first thing inside its parent, because that gap is
  the parent's `lead`. So `sep` and `lead` never describe the same run.

The file adds `bof` (blanks before the first content) and `eof` (trailing
blanks). Together with the opaque bodies, these account for every blank line
exactly once, so `render ∘ parse` is the identity (asserted by the tests).

Two consequences remove machinery a flat model would need:

- **A blank line inside `#+begin_src` is unreachable.** It lives inside a body
  string. A flat model would see it as a gap between two lines and could
  resolve it to 0, deleting content.
- **Rendering cannot change content.** The engine writes only four kinds of
  integer; heading lines, bodies and child order are copied from the working
  tree.

### Who owns a gap

For a gap between content lines X and Y:

> **If X is a heading and Y is inside X's subtree** (Y is X's own body, *or*
> `level(Y) > level(X)`), the gap is **`lead(X)`**: part of block X, restored
> verbatim from the matched ancestor, travelling with X when it moves.
>
> **Otherwise** (X is a body line, or `level(Y) <= level(X)`), it is a
> **boundary gap**, keyed on the ordered pair (X, Y).

A boundary gap belongs to neither endpoint. It is stored in the `sep` of the
node after it, because that is where a blank run before a heading lives, but it
is resolved by looking up the pair. Endpoints are matched by block identity,
not raw text, so toggling `TODO` → `DONE` leaves both edges of a block intact.

The level test is load-bearing. Two cases show why.

**A reorder under a parent with no body.** `level(** 1) > level(* A)`, so the
blank belongs to A, not to the edge (A → 1):

```
ancestor          after the phone reorders 1 and 2      recovered
* A               * A                                   * A
                  ** 2                                  ← lead(A) = 1
** 1              ** 1                                  ** 2
** 2              ** 3                                  ** 1
** 3                                                    ** 3
```

Keyed on the edge (A → 1), the reorder would break that edge; the new edge
(A → 2) would fall to the rule, whose "first child under a bare parent" cell
(0/99) returns 0, silently deleting the blank.

**A closing separator.** `level(** 2) <= level(*** y)`, so the blank is not
`lead(y)`. It is a boundary gap and stays put if `y` moves:

```
** 1
*** x
*** y
          ← boundary gap (after *** → before **, 94%)
** 2
```

### The preamble

Text before the first heading is the body of a headless root node, so it is
opaque like any other body. Its paragraph breaks, the densest blank-line region
at 50%, are kept by never being touched. The mobile apps have not been seen to
damage it.

### Damage inside a body

Bodies are opaque, so blank lines lost *inside* one cannot be repaired line by
line, which would mean aligning prose. One safe case covers it: **if a matched
node's ancestor body and working-tree body have identical non-blank lines**, the
ancestor's body is adopted whole. The precondition is itself the proof that
content does not change. Otherwise the working-tree body wins.

## Algorithm

```
for each org file:
  1. select the healthiest ancestor version from git
  2. parse the ancestor and the working tree into trees
  3. match nodes on an identity score
  4. resolve every gap in the working-tree version
  5. check the strip invariant
  6. return a proposal with the reason for every changed gap
```

### 1. Ancestor selection

Walk back through the commits touching the file, within a window
(`ps/blank-lines-ancestor-max-commits` 5 and `-max-days` 1, whichever is
reached first; 0 days means any age). Score each candidate by how many gaps it
would recover, and take the best, ties going to the most recent. The defaults
come from use: a phone edit is one commit, and a damaged file is opened in
Emacs again the same day or the next.

No commit attribution is needed: the question is only which ancestor has the
richest gap structure, never who made a commit. Attributing by "files Emacs
saved" would have been wrong for VS Code edits, which are good edits Emacs
never sees.

### 2. Parsing

`org-element` locates the headlines and supplies their normalised titles
(`:raw-value`: stars, keyword, priority and tags removed). The slicing into
bodies, and the `lead` and `sep` counts, are computed from the lines
themselves. The output is never regenerated from the parse tree:
`org-element-interpret-data` rewrites content.

A whitespace-only line counts as blank, as in `org-element`. A file with mixed
line endings is refused rather than normalised.

### 3. Matching

| signal | weight | why |
|---|---|---|
| normalised title | high | survives keyword, priority and tag edits, the common mobile edit |
| body similarity (Jaccard over lines) | high | tells same-titled siblings apart; identical on a pure state toggle |
| outline path | medium | anchors a node within the tree |
| level | medium | a promote or demote should still match, at a cost |
| sibling index | low | tie-break only |

Keyword, priority and tags are left out of identity, since they are exactly
what mobile edits change. Matching is greedy best-first with a confidence floor
(`ps/blank-lines-match-floor`). A node below the floor counts as new and is
flagged in the report, so an uncertain match is visible, never silent.

### 4. Resolution

**`lead`** is copied verbatim from the matched ancestor node, with no ladder and
no rule.

**Boundary gaps** take the first rung that applies:

1. **Exact edge.** The same two nodes were adjacent in the ancestor: copy that
   gap, run length included.
2. **Half-edge.** The same predecessor was followed by a heading of the same
   level: adopt that gap. This covers "the block after X was swapped out". The
   predecessor is the right half, because level-2 seams are decided by what
   precedes them.
3. **Fitted rule** (below).
4. **Keep.** With no evidence, leave the gap as it is.

Rungs 3 and 4 fire only at seams made by a move, an insertion or a deletion: a
handful of gaps per file, often none. The last rung was first designed as "set
to 0"; keeping the gap proved better, since it never removes a blank line on no
evidence.

**`bof` and `eof`** are copied from the ancestor when the file matched at all;
`eof` is only ever raised, never lowered. **Bodies** stay as in the working
tree, apart from the whole-body swap above.

### 5. The fitted rule

Fitted at run time from the ancestor versions, corpus-wide: per-file rates were
not bimodal, so fitting per file is not justified. A boundary before heading H
falls into one of nine cells (`ps/blank-lines-rule-cell`):

| cell | when | rate in the corpus |
|---|---|---|
| `l1` | H is level 1 | 100% |
| `l3+` | H is level 3 or deeper | ~0% |
| `l2-after-preamble` | first heading in the file | — |
| `l2-parent-prose` / `-bare` | after the parent, with or without body prose | 84% / 0% |
| `l2-from-deeper-prose` / `-bare` | after a deeper heading closes | ~94% |
| `l2-sibling-prose` / `-bare` | after a level-2 sibling | 0.8% / 20% |

The body distinction is kept for every level-2 case because it is worth a
factor of 25 between siblings. A cell with fewer than
`ps/blank-lines-rule-min-samples` observations is not trusted, and the gap
falls through to "keep".

`ps/blank-lines-unknown-spacing` chooses whether rung 3 runs at all: `style`
(the default) or `leave-alone`, which restores only remembered spacing.
`leave-alone` costs exactly the most certain cases: a level-1 section moved or
typed on the phone lands with no blank before it, wrong every time by the
corpus.

### 6. Full restore, not insert-only

A proposal sets every managed gap to its resolved value, so blank lines are
sometimes **removed**: the ones Beorg inserts by its own level rules where the
user never had them. That still touches no content. Removals are counted
separately in the report so they are never a surprise.

## Detection

"Which files lost blank lines" is answered by running recovery as a dry run
and counting what it would change: one engine, one code path. A density
heuristic would miss Beorg, whose reinsertion makes level-1 spacing look
perfect while body and level-2 gaps are gone.

## Review

The command opens a **report** first: one row per file with something to
decide, how many blank lines it would restore and remove, and where they come
from.

- **Most files are decided from the report.** Each row already carries the
  reason for every change (one-word labels `edge`, `half`, `rule`, `kept`, `new`,
  with the full sentence in the tooltip), so `1` accepts a file, `2` dismisses
  it and `A` accepts all. Accepting writes via `replace-buffer-contents`, which
  keeps point, markers and folding.
- **Rows update in place.** Re-scanning after each decision would be
  authoritative but costs seconds per file and loses the user's place; `g`
  re-scans on demand.
- **Ediff is for the files that need a look**, one at a time from the report.
  Buffer A is the file and B the proposal: left is what you have, right is what
  you would get. Both stay editable, so `b` applies a change and `a` drops one.
  The review starts with everything accepted, since these are blank lines the
  user typed. `+` and `x` accept or drop everything by resetting both sides.
- **The report stays on screen** in a side window on the right (the file tree
  owns the left). Deciding a file from the report cancels any open review first:
  its diff asks a question that has just been answered elsewhere.
- **The ancestor window is adjustable from the report**: `-` and `+` step
  through `ps/blank-lines-ancestor-steps`, a ladder of (commits . days) pairs,
  and `c` and `y` set either number exactly (`y 0` removes the day limit).

How the ediff session is set up and torn down (selecting the first difference,
the layout, the side-window parameters, where in ediff's exit sequence the save
happens) is recorded in `ps-blank-lines-review.el`, next to the code it
explains.

Two traps in the report, both found by use:

- **`push-button` does not move point on a mouse click.** It finds the button
  from the event and runs the action with point where it was, so an action that
  reads "the row at point" acts on the last row the keyboard visited. Actions
  take their row from `(button-start button)` and move point there.
- **Every write path binds `inhibit-read-only`.** An Org buffer can be read-only
  for unrelated reasons, and an accepted proposal must not fail with "Buffer is
  read-only".

### Three guards before anything is written

1. **Staleness.** A file whose buffer is modified, or whose text no longer
   matches what the scan read, is skipped. A proposal describes one version;
   applying it to a newer one would revert whatever came in between. This one
   matters most, since sync can pull in the middle of a review.
2. **No-op.** Nothing is written unless the review changed something.
3. **The strip invariant, again**, against the scanned text. If it fails, the
   review edited content, which can only be the user's own typing; saving then
   needs an explicit yes.

## Source of truth: git history, no sidecar

A sidecar file written on save goes stale exactly when the user edits in VS
Code, and a later mobile edit would then be recovered against an old snapshot,
silently. Git sync commits whatever is on disk, whichever editor wrote it, so
git history is the only record of every good edit. It is not used even as a
cache: a stale cache here means wrong output, and reading git is cheap.

## Rejected

- **A flat line model with a list of gaps.** It cannot keep bodies atomic and
  has no levels for the ownership rule.
- **`org-element`'s `:post-blank` ownership.** It attaches every gap to the
  element before it, so a moved element would carry a boundary gap away with it.
- **Regenerating the file from the parse tree**, which rewrites content.
- **A sidecar snapshot**, and **commit attribution** (both above).
- **A density heuristic for detection** (above).
- **A read-only side in ediff.** Ediff's copy commands bind `inhibit-read-only`,
  so the flag does not stop them, and ediff restores the mode line on exit but
  not `buffer-read-only`, leaving a file the user cannot type in. It would also
  rule out reviewing one change at a time.
- **A queue that walks every file through ediff.** The report is where files
  are chosen and where the answer goes back; the extra machinery bought nothing.
- **A scale factor for the ancestor window.** Halving cannot land on every value
  that matters (a phone edit is one commit) and is not reversible, so `- - + +`
  ended somewhere the user never chose. Both limits still move together on a
  step because git ANDs `-n` and `--since`, so raising one alone often does
  nothing.
- **Insert-only restore**, which cannot undo Beorg's extra blank lines.

## Known behaviour: an oscillation

Accepting a recovery and scanning again can propose the exact inverse, if the
pre-recovery spacing is also a commit in history. The healed file makes the old
commit look like the best ancestor, and it "restores" what the recovery removed.
This needs a history with two deliberately different spacing styles. The sample
notes in this repository have one (a commit restyled them wholesale), so they
oscillate; real mobile damage only ever removes blank lines, so a real scan
settles at zero. A non-zero removal count is the tell. It is left as is,
because the fix would be insert-only restore, which was rejected above.

## Testing

The pure core (parse, match, resolve, render) is tested as text in, text out in
`tests/test-ps-blank-lines-tree.el`, `-engine.el`, `-review.el` and
`test-ps-blank-lines.el`. Every case also asserts the strip invariant. Named
cases include: a pure strip; a strip together with a content edit; a
`TODO` → `DONE` toggle; a new task typed on the phone; a subtree moved,
promoted or demoted; the `* A` reorder above; the closing separator above;
Beorg over-insertion; body lines reordered; a blank inside a source block;
damage only in a body's blank lines; a deleted block; runs of two; BOF and EOF;
no trailing newline and CRLF.

`scripts/make_blank_line_playground.sh` copies the sample notes out of this
repository, synthesises a history with strip commits, and points a dev Emacs at
the copy, so recovery can be driven end to end without touching a real repo.

## Not built yet

- A **passive indicator**: the same dry run in the background, triggered only
  when a sync has pulled changes (never on a timer), lighting a mode-line badge.
- **Faster ancestor selection.** Nearly all of a scan's time (about 20 seconds
  for 35 files) is one `git show` per candidate; `git cat-file --batch` would
  cut that.
- `ps/blank-lines-match-floor` (0.55) is still the original guess; nothing has
  argued against it yet.
- Whether the preamble path ever fires in practice. If it never does, it can be
  dropped.
