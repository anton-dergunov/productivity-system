# Icons

Where the icons in the agenda, the file tree and the folder listing come from,
and how one set of per-vault maps feeds all three.

**Status:** built
**Code:** `lisp/ps-material-icons.el` (glyph to image), `lisp/ps-agenda-icons.el`
(agenda categories), `lisp/ps-file-tree-icons.el` (treemacs icon theme),
`lisp/ps-dired.el` (folder listing), `lisp/ps-schedule-icons.el` (scheduled and
deadline labels); `icons/` (codepoints list, fallback SVGs,
`update_material_symbols_codepoints.sh`); settings blocks
`** Material icons (ps-material-icons.el)` and `** Schedule/deadline icons
(ps-schedule-icons.el)`. User docs: `docs/Customization.org`.

## Problem

Plan files are grouped by what they are *for* (health, work, reading), and an
icon per category makes the agenda and the tree scannable. The first icons were
hand-made SVG files, one per category, which meant a new file for every new
category and a set that could not follow the user's own categories.

## Decisions

**Icons are glyphs from the Material Symbols font**, drawn into an in-memory SVG
`<text>` element and turned into an image (`ps/material-icons-svg`,
`ps/material-icons-image`). There are no per-icon files: any of the font's
thousands of names works. Names resolve to codepoints through the official
`material-symbols.codepoints` list shipped in `icons/`, refreshed by a script.
Going through an image, rather than inserting the glyph as text, gives icons
the same sizing and alignment as any other image.

**Colour follows the theme.** `ps/material-icons-color` is a face (its
foreground is used), a fixed colour, or a function returning either. The
default is `shadow`, the theme's muted text. `config.org` passes
`ps/icons-theme-face`, which picks `default` under Solarized, since Solarized's
`shadow` is too pale for icons, and `shadow` otherwise. The function is asked
against the theme loaded *now*, so the choice stays right while previewing
themes. A fill is baked into each image, so a theme change redraws the icons
already built (`ps/icons--on-theme-change` on `enable-theme-functions`), but
only when the colour actually changed: startup reloads the same theme once,
and that must not rebuild the file tree for nothing.

**Size follows the text** (`ps/material-icons-height` `auto`, from the default
font's height, with `ps/material-icons-height-scale`), so alignment holds
across fonts and machines.

**Three maps decide an icon**, all declared per vault in `workspace.org` and empty
in `config.org`, so a person's categories never enter this public repository:

- `ps/material-icons-category-map`: an Org file's base name to an icon;
- `ps/material-icons-folder-map`: a folder's own icon, at any depth;
- `ps/material-icons-folder-contents-map`: one icon for every file under a
  folder, which takes precedence over the category map, so a whole folder can
  be iconed without listing its files.

`ps/material-icons-add` merges into the category map from `workspace.org`, which
is why the maps are vault-scoped and reset on a switch
([vaults.md](../foundations/vaults.md)).

**Each view builds from the same maps:**

- the agenda's category column (`org-agenda-category-icon-alist`, built by
  `ps/agenda-icons-apply`);
- the file tree's icon theme, where `ps/file-tree-icons--collect` is a pure map
  from treemacs icon keys to glyph names and a separate step makes the images;
- the folder listing, which reuses the tree's folder and file icons rather than
  restating them ([opening-and-navigation.md](../files-and-windows/opening-and-navigation.md)).

**Without the font, things degrade rather than break.** The agenda keeps its
existing icons (the build is a no-op), and the file tree falls back to the
same-named SVGs in `icons/` (`ps/file-tree-icon-fallback-dir`).

**Scheduled and deadline labels become glyphs** (⏱ and ⚑) in Org buffers,
through a font-lock keyword appended after Org's own so its face wins. The
agenda's date badges use the same two glyphs, set separately in
`ps/agenda-layout-reldate-glyphs` ([agenda-layout.md](../planning/agenda-layout.md)).

## Constraints and traps

- **The tree needs an entry for the `org` extension key.** Nodes created after
  the icon walk (a file added from outside) fall back to that key; without it,
  treemacs's own icon appears, at the wrong height and spacing.
- **Tree icon keys** cover every node kind treemacs draws: `root-open` and
  `-closed`, the generic `dir-open` and `-closed`, `<dir>-open` and `-closed` for
  a folder with its own icon, `<file>.org` for a file, and `org` as the
  fallback. Folders and files are found by walking the whole vault, so any
  nesting works.
- **Hiding a line that carries an icon** needs its `display` property removed as
  well as `invisible` set, or the image stays on screen (`ps/file-tree--hide-line`).

## Not built yet

- **Semantic icons in place of the agenda's emojis.** The emoji column
  (`ps-agenda-emoji`, matched by sentence embeddings in
  `scripts/org_emoji_matcher.py`) is a stopgap, to be replaced by Material
  Symbols glyphs through this same pipeline.
