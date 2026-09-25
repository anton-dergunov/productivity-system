# Typo checker

High-precision spell checking for Org files written in several languages at
once: which engine, which dictionaries, and how false alarms are kept rare.

**Status:** built
**Code:** `lisp/ps-typo.el`; settings block `** Typo / spell checking
(ps-typo.el)`. User docs: `docs/Customization.org` → "Typo / spell checking"
(setup, including `enchant`).

## Problem

These Org files mix languages within the same buffer and even the same
paragraph (English, Russian, Spanish, occasional copy-paste of other languages),
and are full of special terms, code, `=verbatim=`/`~code~` markup, file names
and links. The checker must:

1. **Only flag a word when it is *really* wrong** — high precision; low recall
   is acceptable. A flagged word should almost always be a genuine typo.
2. **Respect every language in use** — `calor` is a typo in English but a valid
   Spanish word, so it must not be flagged.
3. **Skip anything that is code or markup** — src blocks, `=verbatim=`, `~code~`,
   links, file names, and "things that look like code".
4. **Underline mistakes subtly** — a non-intrusive wavy underline.
5. **Offer correction** from the word at point (`M-$`).
6. **Be cheap on CPU and use no LLM** — dictionary-based, word-level only, no
   grammar analysis.

## The central design decision

There are two independent axes:

- **The spell engine** (what underlines words and suggests fixes): Flyspell,
  spell-fu, or **Jinx**.
- **The language strategy** (which dictionaries decide "is this a word?"):
  **static multi-dictionary union** vs. **automatic per-region language
  detection**.

The most important finding: **for high precision, auto-detecting the language is
*worse*, not better.** A word is flagged only if it is absent from the accepted
dictionaries, so:

- **Union of all your languages as the accepted set** → the bar to flag a word
  is "wrong in *every* language at once." This is the most precise possible rule.
  `calor` passes (valid ES), Cyrillic words pass (valid RU); only words no
  language recognises are flagged. The cost is recall — a real English typo that
  happens to be a valid Spanish/Russian word slips through — which is exactly the
  trade-off we accept.

- **Detect a region's language, then check only against that language** → this
  *narrows* the accepted set, which raises recall but lowers precision, and adds
  a new failure mode: misdetection. Detection is unreliable exactly where Org
  content lives — short headlines and one-line TODOs are too short for n-gram
  language ID, and a mixed-language line has no single answer. Because below a
  confidence threshold the only safe fallback is "accept all languages" (i.e. the
  union), detection can only ever *remove* languages relative to the union, and
  removing languages can only create false positives. **So detection can never be
  more precise than the union; it only trades precision for recall.**

Conclusion: use the **static multi-dictionary union** for flagging. Language
detection still has one *safe* role — ordering correction suggestions once a word
is already flagged — which never affects precision.

## Spell engines compared

| Engine | Speed / CPU | Multi-dictionary (union) | Skips Org code/markup | Underline | Correction | External deps |
|---|---|---|---|---|---|---|
| Flyspell (built-in) | Poor — subprocess per region; laggy | No — one dictionary at a time | Weak | Plain underline | `M-$` / mouse | aspell/hunspell |
| Flyspell + wucuo | Better — throttled to visible/changed | Still no | Via manual predicates | Same | Same | aspell/hunspell |
| spell-fu | Good — font-lock over visible text | Yes | Face exclusion | Customizable | Weaker (defers to ispell) | aspell + generated word lists |
| **Jinx** ✔ | **Excellent** — only the visible window, idle timer, compiled `enchant` module | **Yes, native** (`jinx-languages`, union) | **Face + regexp exclusion**, code-aware defaults | **Wavy underline** by default | **`M-$` → `jinx-correct`** | `enchant` lib + dictionaries |
| Custom from scratch | Reinvents an engine | — | — | — | — | — |
| LSP: ltex-ls / Harper | Heavy / grammar-level / English-centric | — | — | — | — | Rejected |

**Why Jinx wins:** native union multi-language solves the `calor` problem out of
the box; it checks only the visible window (near-zero CPU); it excludes code and
markup by face and regexp, driven by Org's own fontification; its default
`jinx-misspelled` face is a subtle wavy underline; and `M-$` correction (with
"add to personal dictionary") matches the desired UX. `enchant` is cross-platform
(Linux `libenchant`/`enchant-2`, Windows via MSYS2), though macOS is the primary
target here. spell-fu is the fallback if the `enchant` module is ever undesirable.

## Reaching "only flag when really sure"

These layers all live as the thin, testable glue in `lisp/ps-typo.el` and are
cheap:

1. **Skip code/markup via Org's own fontification.** Exclude text whose face is
   `org-code`, `org-verbatim`, `org-block`, `org-meta-line`, `org-link`, etc.
   Native `#+begin_src` blocks carry the language's own faces (not `org-block` on
   every character), so common `font-lock-*` code faces are excluded too. Faces
   are merged into Jinx's defaults (`ps/typo-exclude-faces`). Excluding text can
   only reduce recall, never cause a false positive, so we are generous here.
2. **Skip "looks like code" tokens by regexp** — camelCase, snake_case, dotted /
   slashed / `::` tokens and paths, `@handles`, `#tags`, `$vars`, `\commands`,
   plus Jinx's own defaults (ALL-CAPS, versions/numbers, URLs, emails). Configured
   via `ps/typo-exclude-regexps`; matched case-sensitively.
3. **Personal dictionary** — `M-$` lets you save a recurring special term so it is
   never flagged again. This is the main lever that keeps the checker quiet.
4. **Minimum length** (`ps/typo-min-length`, default 3) — skip one/two-letter
   tokens where typos and abbreviations are indistinguishable.
5. **Near-miss gate** (`ps/typo-near-miss-gate`, default **off**) — flag an
   unknown word only if the engine offers a suggestion within
   `ps/typo-near-miss-max-distance` edits, i.e. it looks like a misspelling of a
   real word rather than a name/term with no near neighbour. An extra precision
   notch you can A/B.

## How it is put together

- **Engine:** Jinx, backed by `enchant`, in Org buffers only.
- **Languages:** the static union of `ps/typo-languages` (English, Russian and
  Spanish by default). Language detection never decides whether a word is
  flagged.
- **Correction:** `M-$` runs `jinx-correct` on the word at point; the same
  prompt can add the word to the personal dictionary.
- **Look:** `jinx-misspelled` is themed to a subtle wavy underline.
  `ps/typo-underline-color` set to `auto` derives a muted colour from `shadow`.
- **Suggestion order** (`ps/typo-order-suggestions-by-language`, on by
  default): `guess-language` detects the surrounding paragraph's language and
  lists that language's suggestions first. This is the one safe use of
  detection, since it only reorders suggestions for a word already flagged. It
  is skipped silently if `guess-language` is missing.
- **Read-only buffers are not checked:** `ps/typo-inhibit-predicate` turns the
  checker off in the documentation reading view, where nothing can be edited.

All coupling to Jinx is confined to `ps/typo-setup`. The pure helpers (the
regexp set, the near-miss decision, language ordering, the face-exclusion merge)
therefore load and are tested under a bare `emacs -Q` without Jinx installed
(`tests/test-ps-typo.el`).
