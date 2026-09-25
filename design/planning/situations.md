# Situations

Context tags and the saved searches built on them: "what is worth doing right
now, with what I have in my hands".

**Status:** built
**Code:** `lisp/ps-situations.el`; declared per vault in `workspace.org`;
settings block `** Situations (ps-situations.el)`; applied from `config.org` →
`*** Situations`, right after the `org-super-agenda` block. User docs:
`docs/Situations.org`.

## Problem

Free time arrives in awkward shapes: a minute between sets at the gym, a walk,
a plane with no signal. The agenda answers "what is due" and "what matters
most", not "what can I do *here*". Org's tags could answer it, but free-form
tags drift, and a tag per situation would mean re-tagging every task whenever a
new situation came up.

## Decisions

**A tag is an affordance**: a promise that the task works with *less than a
desk* (less screen, attention, time or energy). A task that needs a desk gets no
tags, so most tasks carry none, which is correct. Tags never describe what a task
needs *more* of: "requires deep focus" applies to almost everything and so says
nothing.

**A situation is a query over tags**, not a tag. A situation is a bundle of
capabilities ("on foot" means ears and thinking, but no screen), so tagging
situations directly would mean re-tagging everything for each new one. Tags
describe requirements; a new situation costs one line and no re-tagging.

**Two declarations, everything else derived.** `ps/context-tags` is the fixed
vocabulary (name, selection key, kind, meaning); `ps/situations` is the saved
`tags-todo` searches (key, name, hint, icon, query). From them:

- `org-tag-alist`, with fast-selection keys and a line break between kinds;
- one agenda command per situation, under the `s` dispatcher prefix
  (`ps/situations-key-prefix`);
- the `C-c p S` keymap, the Productivity menu entries and the mode-line view
  switcher;
- the tag and situation tables in the AI context
  ([agent-context.md](../ai/agent-context.md)), so an assistant tags tasks the
  same way.

**Both are declared per vault**, in `workspace.org`, and empty in `config.org`:
which tags exist is a property of a person's notes, not of the system. With no
tags declared, `org-tag-alist` is left alone and tags stay free-form. Both are
vault-scoped, so switching vaults resets them ([vaults.md](../foundations/vaults.md)).

**A situation view is its own view kind** (`situation`): the layout draws a plate
naming the query instead of a date header
([agenda-views.md](agenda-views.md)).

## Constraints and traps

- **Generate commands in block form**, `((tags-todo QUERY LPROPS))` with
  command-wide settings, even for a single block. Only `org-agenda-run-series`
  records the whole series as the redo command; a single-type command lets
  `org-tags-view` overwrite redo with itself, which drops the settings and loses
  the view's identity on every `g`.
- **Leave `org-agenda-overriding-header` unset**, so `org-tags-view` emits its
  own "Headlines with TAGS match" header, which the layout rewrites into the
  plate.
- **Register after `config.org`'s `setq org-agenda-custom-commands`.** That
  `setq` runs on the `org-agenda` load event, and `eval-after-load` forms run in
  registration order, so anything registered earlier (from `workspace.org`, some
  500 lines above) is silently replaced. That is why `ps/situations-apply` is
  called from `config.org` after the super-agenda block and not from
  `workspace.org`; before the fix, `C-c a s m` landed in Org's keyword search.
- **Claiming `s` shadows the dispatcher's built-in keyword search**, which
  remains on `M-x org-search-view`.
- **Not to be confused with `ps-tags.el`**, a display fix for tag pills
  ([org-display-fixes.md](../editing/org-display-fixes.md)).

## Rejected

- **Situations as tags** (above).
- **Tags that describe demands** rather than affordances (above).
