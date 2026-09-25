# Typography

Which fonts the configuration uses and for what, where a proportional font is
possible and where it is not, and what is still to do.

**Status:** partly built
**Code:** `lisp/ps-fonts.el`; settings block `** Fonts (ps-fonts.el)`;
`lisp/ps-prose-width.el` and `lisp/ps-line-numbers.el` for related display.
User docs: `docs/Customization.org` (fonts and font preview).

## The Emacs font model, and why `default` is special

A font is a *face attribute* (`:family`, `:height`, `:weight`, `:slant`), so
every face can carry its own family. There are three ways to vary it:

- **per face** — `(set-face-attribute 'org-level-1 nil :family "…")`
- **per buffer, all text** — `buffer-face-mode` / `variable-pitch-mode`, which
  is a buffer-local remap of `default`
- **per buffer, selectively** — `face-remap-add-relative`, or the `mixed-pitch`
  package: proportional everywhere *except* a list of faces pinned to
  `fixed-pitch`

The constraint that decides everything below: **the frame's `default` face
defines the frame's canonical character width**, and every measurement
expressed "in columns" uses that unit *regardless of the font the text is
actually drawn in* — window widths, `split-window`, margins, fringes,
`frame-char-width`, and `(space :align-to N)`.

So the safe architecture is: **keep `default` monospace so all geometry stays
exact, and remap individual buffers to proportional.** Column-based layout
keeps working. What breaks is only code that assumes *character count ≈ pixel
width*: `make-string N ?\s` padding, `format "%-24s"`, and `string-width`
budgets.

## Audit: which surfaces can go proportional

### Must stay monospace

| Surface | Why |
|---|---|
| Claude Code pane | `eat` is a terminal emulator — a character grid. The child `claude` process is told COLUMNS/LINES and paints assuming uniform cells; `ps-claude.el` syncs eat's size from window columns. Proportional means shredded diffs and a mispositioned cursor. (The VS Code Claude panel is a webview with HTML layout, not a terminal — not a counter-example.) |
| Schedule / Timeline | `ps-schedule-view.el` draws its ruler with `make-string N ?┄`, pins `┆` to an absolute column, and pads the time field to exactly 11 chars. Pure character-cell geometry — and text fonts lack U+2506/U+2504, so those glyphs fall back to another font mid-line anyway. |
| Availability / Conflicts / Timezone / blank-line report | `(make-string 78 ?─)`, `"%-42s %-20s"`, `"%-26s"` — space-padded columns throughout. |
| Org **tables**, anywhere | Aligned by character count. `valign` can fix it, at a cost; the docs reading view already loads it. |
| `#+begin_src` bodies, `config.org` | Code wants a grid. Also: src-block bodies are fontified by the *source mode's* faces, which do **not** inherit `fixed-pitch`, so they escape a naive mixed-pitch setup. |
| Mode line | `ps-mode-line.el` truncates by `string-width` against `window-width`. |

### Safe

**File tree.** Treemacs indentation is uniform strings (narrower but still
tidy); the header-line buttons use `:align-to (- right N)`, which is
canonical-char-based and stays exact; icons are SVGs sized from
`default-font-height`, which is frame-level and unaffected by a buffer remap.
Highest reward, lowest risk.

**Org plan files.** Scopable through `ps/org-files-in-scope-p` — the predicate
`ps-prose-width.el` already uses — so `config.org`, `workspace.org`, the
journal and every generated view stay monospace automatically.

### Middle case: the agenda list sections

`ps-agenda-layout.el` is closer to safe than expected, because it is built on
`(space :align-to COL)` rather than space padding. `:align-to` is absolute
positioning, so column *starts* stay exact even when the text between them is
proportional, and badge widths already go through `string-pixel-width` on
graphical frames. Three things would still misbehave:

- Title truncation budgets in `string-width` (character count). Proportional
  lowercase is narrower than a mono cell so it mostly under-fills, but a
  caps-heavy title can overflow — and overflowing past an `:align-to` target
  **collapses that separator to zero width**, so that row's right badge jumps
  left.
- `string-pixel-width` with one argument measures in a temp buffer under the
  *global* `default` face, so a buffer-local remap in the agenda would be
  mis-measured. Emacs 30 takes a BUFFER argument.
- Left margins built with `make-string N ?\s` shrink, since a space is
  narrower than a cell.

Real work on already-tuned code, for short task titles where proportional buys
the least. Deferred: see "Not built yet".

## Decisions

These were settled deliberately; change them only with a new reason.

- **The heading ramp stays tiny:** `1.04 / 1.03 / 1.02 / 1.01 / 1.0`. Nesting
  depth is a grouping artifact, not a signal of importance: the same content
  regrouped from four levels into two must not change size. Emacs's default
  ramp was rejected as wrong in principle and ugly in practice. Face heights
  are integers in tenths of a point that then round to whole pixels, so after a
  font change the ramp should be re-checked against the pixel heights it
  actually produces (the font preview shows them), keeping the steps as small.
- **`ps/prose-width-columns` stays at 180.** 120 read too narrow for content
  that is part prose, part plan.
- **No extra line spacing by default.** The current density is liked. Where a
  font needs more air, that belongs to the font: `ps/font-line-spacing` is keyed
  by family (Menlo gets 0.2), so auditioning a font brings its spacing with it.
- **The Claude Code pane stays monospaced**, permanently.
- **Fonts are named by role, each role a list of candidates.** `ps/font-mono`,
  `ps/font-prose` and `ps/font-ui` each hold families in preference order, and
  the first one installed wins. A family that is not installed is skipped, so
  the worst case is "looks like the default", never a failed startup. Size
  (`ps/font-size`) is separate from the family. This replaced a single
  `"Family-Size"` string, where the two could not be changed apart and a
  missing family could break startup.
- **`fixed-pitch` and `variable-pitch` are set explicitly** from the roles.
  Left alone they were Courier and Helvetica, and pinning faces to `fixed-pitch`
  is the mechanism that keeps tables and code on the grid in proportional
  buffers.
- **The file tree uses the interface font** (`ps/font-ui`, through the shared
  `ps/font-ui-face`), as VS Code and Obsidian use a separate interface font for
  their folder trees. A face rather than per-buffer restyling means one change
  restyles every tree at once.

## Findings

- **Monaco ships Regular only.** Every bold heading, every org-modern badge and
  every italic is synthesized by Core Text: smeared bold, mechanically slanted
  italic. That is the main reason to change the monospaced font. Menlo has all
  four styles.
- **IBM Plex is the matched set that works:** Mono, Sans and Serif are three
  real families, selectable by name, on shared proportions, so a monospaced
  frame with a proportional tree reads as one design.
- **Recursive does not work here**, although it is the obvious candidate on
  paper. It installs as a single family whose Mono, Sans and Casual variants are
  styles, not families. Naming the family reaches only its default instance,
  and the monospaced half cannot be selected.
- **Prose-first Org setups settle on a middle ground**, which fits plan files
  (prose inside an outline, not running text): iA Writer Duo and Quattro widen
  only a few letters; Monaspace ships five monospaced faces on shared metrics,
  two of which deliberately do not read as code; ETBembo and Spectral are the
  usual picks for going fully proportional. The common mechanism is
  `variable-pitch` for prose with a list of faces pinned to `fixed-pitch`, which
  is what `ps-fonts` does.
- **Shortlist** (macOS, free): mono — JetBrains Mono, Commit Mono, Iosevka
  (narrow, buys columns in the agenda), IBM Plex Mono; prose — Literata,
  Charter, Source Serif 4, Spectral, Merriweather, Newsreader; interface —
  Inter, IBM Plex Sans, SF Pro Text.

## How it is built

- `ps/fonts-apply` sets `default`, `fixed-pitch` and `variable-pitch` from the
  roles, after `face-font-rescale-alist` so fallback fonts are scaled first.
  The size conventions are in the module's Commentary.
- **Auditioning never saves a setting.** `ps/font-preview` (`C-c p P`) draws the
  same sample in every candidate (the live heading ramp with its pixel heights,
  prose, an agenda row, the schedule's box-drawing characters, regular, bold and
  italic, and a monospace check), with controls for size, scale and line
  spacing. `ps/font-try`, `ps/font-size-try` and `ps/font-scale-try` do the same
  without the buffer, and `ps/font-cycle` (`C-c p M` for the editing font,
  `C-c p U` for the tree) steps through `ps/font-favourites`. Each echoes the
  `setq` line that would make the choice permanent; `ps/fonts-apply` goes back.
- **Proportional plan files** are available but off (`ps/font-prose-in-org`,
  toggled live with `ps/font-prose-toggle`). When on, only files the agenda
  scans are affected (`ps/org-files-in-scope-p`), so `config.org`,
  `workspace.org`, the journal and generated views stay monospaced. Tables,
  code and indentation are pinned to `fixed-pitch` through
  `ps/font-prose-fixed-pitch-faces`.
- `ps/fonts-ui-setup` restyles buffers that already exist as well as adding the
  mode hook. A mode hook only runs when a buffer is created, so a tree restored
  from the session would otherwise keep its old font, which looks like the
  setting having no effect.

## Constraints and traps

Two faces are left out of the `fixed-pitch` pin list on purpose, and are easy
to add back by accident:

- **`line-number`**: `ps-line-numbers.el` already remaps it, and relative
  remaps stack, so a second one would fight it.
- **Source-block bodies**: they are fontified by the source language's own
  faces, not by any Org face, so a list of Org faces cannot reach them. This is
  the case `mixed-pitch` also gets wrong. With proportional plan files on, code
  inside plan files follows the prose font; check that before turning it on for
  good.

## Not built yet

- **Swapping the monospaced font.** Pick one from the preview, then re-check the
  heading ramp's pixel heights against the new metrics.
- **Fontsets** (`set-fontset-font`), done together with the swap. When the main
  font lacks a glyph (emoji, ✓, Material Symbols), macOS picks a fallback,
  sometimes one with a taller line box; `ps/font-rescale-alist` compensates with
  hand-tuned factors. Changing the monospaced family changes which characters
  fall back, so those factors may end up tuned for fonts no longer in use.
- **Deciding on proportional plan files**, and then re-tuning
  `ps/prose-width-columns`: the pixel width stays the same, but more words fit
  on a line.
- **Pixel-correct agenda measurement**: truncation budgets in pixels, and
  `string-pixel-width` given the agenda buffer. It is needed before the agenda's
  title column could ever be proportional (see the middle case above).
