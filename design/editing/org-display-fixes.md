# Org display fixes

The fixes that make an Org buffer look like a quiet document rather than
marked-up source: markup revealed only where you type, heading bullets that
survive half-typed stars, whole tag pills, faded DONE tasks, a tinted
selection, a muted gutter and a reading width. They all work through
font-lock, display properties or face remapping, and they can break one
another.

**Status:** built
**Code:** `lisp/ps-appear.el`, `lisp/ps-heading-stars.el`, `lisp/ps-tags.el`,
`lisp/ps-emphasis.el`, `lisp/ps-done.el`, `lisp/ps-selection.el`,
`lisp/ps-line-numbers.el`, `lisp/ps-prose-width.el`; wired in `config.org` →
`* Org Mode` (notably `*** Show formatting markup only at point (=org-appear=)`)
and `* Editor & UI`; settings blocks `** Done tasks (ps-done.el)`,
`** Selection (ps-selection.el)`, `** Line numbers (ps-line-numbers.el)` and
`** Reading width (ps-prose-width.el)`. User docs: `docs/Customization.org`,
`docs/Planning-setup.org`.

## Problem

The look is Obsidian-like: emphasis markers hidden (`org-hide-emphasis-markers`),
raw syntax revealed only at point (`org-appear`), bullets drawn over heading
stars (org-modern and org-superstar), tags as pills, done work faded. Each
piece is a display trick layered on font-lock, and the interactions between
them, and with the typo checker, produced visible glitches while typing.

## The fixes

**Raw markup stays revealed while you type inside it** (`ps-appear`). Without
this, the reveal collapsed on every keystroke inside `*bold*` or a link, and you
edited text whose syntax you could not see. The cause is an interaction with the
typo checker. `jinx` registers a jit-lock function that returns nil, so
`jit-lock--run-functions` marks only the *intersection* of what its functions
report, which is the requested region rather than the whole-line region
font-lock actually fontified. `org-appear` refontifies just the element before
revealing, so the rest of the line stays unfontified, the redisplay right after
the keystroke fontifies it, and `org-do-emphasis-faces` hides the markers again
after the reveal. The fix re-asserts the reveal at the end of every font-lock
region pass, inside that pass, so the collapsed form is never drawn. It hooks
the region pass rather than `org-do-emphasis-faces`, so one hook covers every
element type `org-appear` toggles and runs once per region rather than per
match.

**Half-typed heading stars stay literal** (`ps-heading-stars`). Org refuses to
treat heading stars as bold only for a *complete* headline (`"^\\*+ "` needs the
space). A half-typed `**` is not one, so its stars were parsed as emphasis: a
long run showed its middle stars bold, and a bare `**` paired across the newline
with the next headline, putting bold and `invisible` on *its* stars and hiding
its bullet. Two let-bound tweaks around `org-do-emphasis-faces`:

1. a line of nothing but stars counts as headline stars, so emphasis cannot
   open on it;
2. an emphasis body may not continue onto a line that starts with stars, so an
   unterminated `*` on a heading cannot close on the next headline's stars.

The fix prevents the mis-parse rather than repairing it afterwards. A repair
cannot work: Org matches emphasis with an unbounded `looking-at` that reaches
past the refontified region into the next line, while any cleanup is bounded by
that region.

**Tag pills stay whole when a headline wraps** (`ps-tags`). org-modern pads each
pill with a literal space inside a display string, and `word-wrap` treats a
display string starting with a space as a break opportunity, so a wrapped
headline could break between pills and strand the padding as an empty grey box.
Replacing those spaces with no-break spaces makes the tag group atomic, so the
only break left is before the tags. It is a font-lock keyword appended after
org-modern's own, so it rewrites what org-modern just produced.

**Emphasis is rendered in generated buffers** (`ps-emphasis`). The agenda copies
headings as plain text, so markers arrive literally. `ps/emphasis-render` drops
the markers and applies the faces from `org-emphasis-alist`. The markers are
*deleted*, not made invisible, because `string-width` counts invisible
characters and the agenda lays out columns by width. It approximates nesting
and is not an Org renderer.

**DONE tasks fade** (`ps-done`): overlays over each DONE subtree, with commands to
fold and unfold them. The colour is `ps/done-fade-color`; `auto` derives it from
the theme's `shadow` face. The fade is rebuilt on a
debounced idle timer after edits, after a revert and after a state change,
never on every keystroke.

**The selection tints rather than repaints** (`ps-selection`):

- It stays visible, dimmed, in windows that are not selected, through an
  overlay (`ps/selection-inactive`). `highlight-nonselected-windows` is the
  wrong fix: it draws the region at full strength everywhere.
- Its colour is derived from the theme's `region`, washed toward the page
  background, neutralised (a washed colour keeps its hue, and Solarized's
  blue-grey over cream reads green), and stripped of the foreground that made
  headings, links and pills turn inside out. It is re-derived on theme change
  and works on dark themes.
- org-modern's TODO and priority pills use `:inverse-video`, which paints the
  text in whatever background is in effect, so inside a selection the letters
  vanished. `ps/selection--flatten-face` resolves the inversion into a plain
  foreground and background; giving the face its background alone was not
  enough, since the selection still won the merge.

**The line-number gutter is quieter in Org buffers** (`ps-line-numbers`): smaller
digits and muted colours, through buffer-local face remapping, since there is no
per-buffer setting and `display-line-numbers` looks its faces up through
`face-remapping-alist`.

**Prose has a reading width** (`ps-prose-width`): plan files are capped at
`ps/prose-width-columns` and centred with `visual-fill-column`, as Obsidian
does, and the margins shrink to nothing once the window is narrower.

## Constraints and traps

- **The DONE fade scan must walk `org-outline-regexp-bol`, never
  `org-heading-regexp`.** The latter's title is optional, so a lone `*` (a
  half-typed heading) matches it though Org does not consider it a headline;
  `org-get-todo-state` then signals "Before first headline" in a file with no
  headline yet, which surfaced from the idle timer mid-typing.
- **The idle rebuild must demote errors** (`ps/done--refade-now`). An error from
  a timer interrupts whatever the user is typing.
- **Put the gutter's height on `line-number` only.** `line-number-current-line`
  inherits from it, and `:inherit` resolves through the remapping too, so a
  height on both multiplies (0.8 × 0.8) and the current line's number shrinks.
  The colour goes on both, since a theme's explicit foreground on the current
  line would otherwise win.
- **Scope the reading width and the planning look to plan files**
  (`ps/org-files-in-scope-p`), not every Org buffer: `config.org`,
  `workspace.org`, the journal and the generated views stay as they are. Ediff
  sessions are excluded explicitly, since a split frame usually, but not always,
  leaves each pane narrower than the threshold.
- **An async edit must clear `org-appear`'s cached element.** When a URL's title
  arrives and replaces the placeholder link (`ps/org-insert-link-async`), the
  cached element still points at the deleted text, and the reveal fix above
  would re-reveal that stale region.
- **Point must stay visible in the selected window**, so scrolling far past an
  active region drags its end along. That is an Emacs display invariant, not
  fixable here, and it is why the Claude panel remembers the last region
  ([claude-code-panel.md](../ai/claude-code-panel.md)).
- **Order of font-lock keywords matters.** The tag and schedule-icon keywords
  are appended after org-modern's and Org's own, so they see and win over what
  those produced.

## Rejected

- **Repairing mis-parsed stars after the fact** (above).
- **`highlight-nonselected-windows`** (above).
- **Hiding emphasis markers with `invisible` in generated buffers** (above).
