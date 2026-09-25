# Multilingual, high-precision typo checker for Org files

This document records the design rationale behind the Org typo checker
(`lisp/ps-typo.el`). For setup instructions see the **Typo / Spell Checking**
section of [README.md](../README.md); for the knobs see the **Settings → Typo /
spell checking** block in `config.org`.

## Goals

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

## What was built

- **Engine:** Jinx (`enchant`-backed), enabled in Org buffers only.
- **Language strategy:** static multi-dictionary **union** (`ps/typo-languages`,
  default `en_US ru_RU es_ES`). Auto-detection never gates flagging.
- **Correction:** `M-$` → `jinx-correct` on the word at point (plus add-to-personal
  -dictionary from the same prompt).
- **Appearance:** the `jinx-misspelled` face themed to a subtle wavy underline
  (`ps/typo-underline-color`, `auto` derives a muted colour from `shadow`).
- **Suggestion ordering** (`ps/typo-order-suggestions-by-language`, default on):
  `guess-language` detects the surrounding paragraph (trigram scan, sub-millisecond)
  and lists that language's suggestions first. It never affects whether a word is
  flagged, and falls back silently if `guess-language` is unavailable.

The module keeps engine coupling inside `ps/typo-setup`, so the pure helpers (the
regexp set, the near-miss decision, language/dict ordering, the exclusion merge)
load and unit-test under a bare `emacs -Q` without Jinx installed. Tests:
`tests/test-ps-typo.el`.

## How to verify

1. `./scripts/run_emacs.sh`, open `samples/realistic/Play/Languages.org` — Org
   loads cleanly and words are checked.
2. Type `calor` and a Cyrillic word in prose → not flagged. Type `teh` /
   `recieve` → flagged with a subtle wavy underline.
3. Put typos inside `=verbatim=`, `~code~`, a `#+begin_src` block, a link target
   and a file path → none flagged.
4. `M-$` on a flagged word lists suggestions and can save the word permanently.
5. Scroll a large file → only the visible region is checked; no lag.
6. `EMACS_BIN=… ./scripts/org_test.sh` passes, including `tests/test-ps-typo.el`.
