# Fonts

Where this config can use a proportional font, where it cannot, and the plan
for getting there. Written after an audit of every surface that lays text out
in columns.

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
the least. Deferred to Phase 4, and only if Phase 3 makes it feel worth it.

## Decisions taken (do not re-litigate)

- **The heading ramp stays tiny.** `1.04 / 1.03 / 1.02 / 1.01 / 1.0` is
  deliberate and hand-tuned. Nesting depth is a *grouping* artifact, not an
  importance signal: the same content regrouped from four levels into two must
  not change size. Emacs' default ramp was rejected as both wrong in principle
  and ugly in practice. Open question worth *measuring* (not changing): face
  heights are integers in ⅒pt that then round to whole pixels, so at 14pt it is
  plausible that levels 2–5 all land on one pixel size and only level 1 steps
  up. Worth showing the real pixel heights so the ramp can be re-tuned
  deliberately after a font change — with steps just as small.
- **`ps/prose-width-columns` stays at 180.** Hand-tuned; 120 read too narrow
  for content that is part prose, part plan. Re-tune *after* Phase 3 if at all
  — the pixel width will not change, but noticeably more words will fit per
  line.
- **`line-spacing` stays unset globally.** Current density is liked.
- **Claude Code pane stays monospace permanently.**

## Font shortlist (macOS, free, all available via Homebrew)

The trigger for changing the mono font: **Monaco ships Regular only** —
`fc-list "Monaco" : style` returns one style, where Menlo returns four. Every
bold heading, every org-modern badge and every `/emphasis/` is currently
*synthesized* by Core Text: smeared bold, mechanically sheared oblique. In a
config with a dedicated `ps-emphasis.el`, that is the single biggest quality
ceiling.

- **Mono** — JetBrains Mono (tall x-height, safest at 14), Commit Mono (more
  refined, lovely italics), Iosevka (narrow — buys real columns in the agenda's
  fixed budgets), IBM Plex Mono
- **Prose serif** — Literata (screen-first, "modern Times New Roman"), Charter
  (already installed; Matthew Carter, ages well), Source Serif 4, Spectral,
  Merriweather (big x-height, quite dark; wants a little more line-spacing),
  Newsreader
- **UI sans** — Inter, IBM Plex Sans
- **Matched pairs** — with a mono frame and a proportional tree, matched metrics
  make the UI read as one design rather than two fonts sharing a window. **IBM
  Plex** (Mono / Sans / Serif) is the option that works here: three real
  families, selectable by name. **Recursive is not**, despite being the obvious
  candidate on paper — it installs as a *single* family (`Recursive`) whose
  Mono Linear / Sans Linear / Casual variants are font *styles*, not families,
  so naming the family in a face reaches only its default instance (Sans Linear
  Light) and the monospaced half is unreachable. Verified with
  `fc-list "Recursive" family style`.

```bash
brew install --cask font-jetbrains-mono font-commit-mono font-iosevka font-ibm-plex-mono \
  font-recursive font-literata font-source-serif-4 font-spectral font-merriweather \
  font-newsreader font-inter font-ibm-plex-sans font-ibm-plex-serif font-charter
```

## Plan

### Phase 1a — robustness (useful regardless of any font change)

`lisp/ps-fonts.el`: fonts named by **role** (`ps/font-mono`, `ps/font-prose`),
each a *list* of candidates with the first installed one winning, plus
`ps/font-size` separated from the family. Sets `default`, `fixed-pitch` and
`variable-pitch` from those roles.

Three standing problems this fixes:

1. `ps/main-font` was a single `"Family-Size"` string — family and size
   inseparable, no weight/width, and a family that is not installed either
   signals or silently falls back to something arbitrary. Editing that setting
   to a font you do not have could break startup.
2. `fixed-pitch` and `variable-pitch` were never set, so they sat at macOS
   defaults (Courier and Helvetica). Not cosmetic: pinning faces to
   `fixed-pitch` is the *mechanism* Phase 3 uses for "tables and code blocks
   stay on the grid", and it only works if `fixed-pitch` is the right font.
3. No way to change size without restating the family.

Monaco stays first in the candidate list, so **Phase 1a has no visual effect**
beyond `fixed-pitch`/`variable-pitch` no longer being Courier/Helvetica.

### Phase 1b — the audition tooling (done)

- `ps/font-preview` (`C-c p P`) — a buffer rendering the *same* sample in every
  installed candidate: the heading ramp taken from the live `org-level-N` faces
  (not a copy of the numbers), a line of prose, an agenda row, the schedule
  ruler's box-drawing characters, a regular/bold/italic row, and two equal-length
  runs of `i` and `M` as a monospace check. Missing candidates are listed rather
  than drawn, so the list can name fonts not installed yet.
- `ps/font-try` / `ps/font-size-try` — the same without the buffer.
- Applying from either is an **audition**: `ps/fonts--apply-role` never writes a
  setting, and the echoed `setq` line (built by `ps/fonts--promote`, which keeps
  the existing fallbacks behind the new choice) is what makes it permanent.
  `ps/fonts-apply` is the way back.
- Also here: the heading-ramp diagnostic, printing each level's configured
  `:height` multiplier next to the pixel height it actually resolves to — the
  open question recorded above.

### Phase 1c — the swap (next)

- Pick a mono font from the preview; swap the default. Re-check the ramp's
  resolved pixel heights against the new metrics and re-tune the multipliers if
  the rounding moved, keeping the steps as small as they are now.
- **Fontsets** (`set-fontset-font`). Emacs picks a font per *character*; when
  the main font lacks a glyph (emoji, ✓, CJK, Material Symbols) it asks macOS,
  which answers with whatever it likes — sometimes a font with a taller line
  box, which is why `ps/font-rescale-alist` exists with six hand-tuned entries.
  This belongs with the swap, not later: changing the mono family changes which
  characters count as missing, so different fallbacks get selected and those six
  factors may end up tuned for fonts no longer in use.

### Phase 2 — file tree proportional (done)

`ps/fonts-ui-enable` on `treemacs-mode-hook`, applying the `ps/font-ui` role
through the shared `ps/font-ui-face` — a face rather than per-buffer restyling,
so changing the family updates every tree buffer at once and `u` in the preview
restyles the tree as you press it.

This mirrors how VS Code and Obsidian split their font settings; Obsidian's
"Interface Font" is explicitly the one used for the folder tree. On macOS both
resolve to the system UI font, so `SF Pro Text` heads the candidate list — it is
literally the font the VS Code explorer is drawn in here. It needs a `sudo`
`.pkg` install (`brew install --cask font-sf-pro`); until then the list falls
through to Inter, which is Obsidian's.

### Findings from surveying prose-first Emacs setups

Org users writing prose rather than code converge on a middle ground rather than
on full proportional, which matches what these files actually are — prose inside
an outline, with tags, not running text:

- **iA Writer Duo / Quattro** (OFL, built on IBM Plex) are built exactly for
  this. Duo widens only `m` and `w`; Quattro gives four widths and reads nearly
  as prose while keeping typewriter word spacing. Org users show up using
  "iMWritingDuoS Nerd Font" — the Nerd-patched Duo.
- **Monaspace** (GitHub, OFL) ships five monospaced faces on shared metrics, so
  they swap without anything moving. Xenon is a slab serif and Radon
  handwritten: monospaced faces that deliberately do not read as code, which is
  the axis this config cares about.
- **ETBembo** (from Tufte CSS) and **Spectral** are the recurring picks for
  those who do go fully proportional.
- The standard mechanism everyone uses is `variable-pitch` for prose with
  `fixed-pitch` pinned on tables and blocks — which is what Phase 1a set up and
  Phase 3 will use.

### Phase 3 — Org plan files proportional (done)

`ps/fonts-prose-enable` on `org-mode-hook`, scoped by `ps/org-files-in-scope-p`,
gated on `ps/font-prose-in-org` (default off) and toggled live by
`ps/font-prose-toggle`. `buffer-face-set 'variable-pitch` plus
`:inherit fixed-pitch` remaps over `ps/font-prose-fixed-pitch-faces`.

Two exclusions from the pin list are deliberate and easy to undo by accident:

- **`line-number`** — `ps-line-numbers.el` already remaps it with its own
  `:inherit`, and relative remaps stack, so a second one would fight it.
- **`#+begin_src` bodies** — fontified by the *source* mode's faces, not by any
  Org face, so they cannot be reached from a list of Org faces at all. This is
  the case `mixed-pitch` also gets wrong. Code in plan files therefore follows
  the prose font; that is the thing to check before turning this on for good.

Still open: re-tune `ps/prose-width-columns` after living with it. The pixel
width does not change, but noticeably more words fit per line.

### Phase 4 — optional

Pixel-correct measurement in `ps-agenda-layout.el` (truncation budgets in
pixels; `string-pixel-width` passed the agenda buffer). Prerequisite for ever
making the agenda's *title* column proportional while the schedule ruler stays
a grid.
