Emacs Planning System — Mode Line Redesign

Background

This Emacs configuration is not a general-purpose editor.

It is a dedicated planning system built around:

* Org files
* Org Agenda
* Treemacs (File View)
* Git synchronization

The user does not use:

* programming language modes
* LSP
* Flycheck/Flymake
* compilation
* shells
* email
* Git branches
* encoding indicators
* line-ending indicators
* major/minor mode lists

The goal is to redesign the mode line so that it communicates only information relevant to planning and navigation.

The design should feel closer to Obsidian, Logseq, or a dedicated planning application than a traditional Emacs editor.

⸻

Design Principles

1. Every item must justify its existence

Mode line space is valuable.

Information that is always obvious or rarely needed should be removed.

Examples to remove:

* Org mode indicator
* Projectile
* Ivy
* Which-Key
* Wrap
* Git branch
* Encoding
* Line endings
* Read-only indicators

⸻

2. Minimize duplication

Global information should not be duplicated in every window.

Example:

Git synchronization state is global.

Displaying it in every Org window wastes space.

Instead, display synchronization state in Treemacs/File View.

⸻

3. Prioritize navigation context

The mode line should answer:

* Which document am I viewing?
* Where am I in the document?
* Which section am I currently reading?

⸻

Org File Mode Line

Final Structure

Photo ▼ · L53 · 38% · Search Ranking > Dataset Cleanup

⸻

Component 1: File Selector

Example:

Photo ▼

Behavior:

* Hide “.org” extension.
* Clicking opens a menu.
* Menu shows the full plans hierarchy.
* Directories are shown as folders.
* Org files are shown as selectable entries.

Example:

Areas/
Health
Learning

Current/
Today
Inbox
Projects

Vision/
Goals
Ideas

This replaces old-school buffer cycling behavior.

⸻

Component 2: Position

Example:

L53 · 38%

Meaning:

* line 53
* 38% through file

Column number is intentionally omitted.

Reason:

Column position has little value in planning documents.

⸻

Component 3: Current Org Heading

Example:

Search Ranking > Dataset Cleanup

Purpose:

Provide context inside large Org files.

⸻

Truncation Strategy

The heading should be the first item truncated.

Priority order:

1. Preserve file selector.
2. Preserve position.
3. Truncate heading if necessary.

Example:

Photo ▼ · L53 · 38% · Search Ranking > Dataset Clea…

If still too long:

Photo ▼ · L53 · 38% · Search Ranking…

The filename should ideally never be truncated.

⸻

Navigation via Heading

Potential future enhancement.

Clicking:

Search Ranking

would open a menu of sibling headings.

Selecting an entry would jump to that section.

Status:

Deferred.

Not needed for version 1.

⸻

Save State Indicator

Decision:

Remove entirely.

Reason:

The system already:

* auto-saves Org buffers
* auto-reverts changed files

The save state therefore provides very little value.

This mirrors applications such as Obsidian.

⸻

Frame Title

Current:

Photo.org

Proposed:

Photo

Remove “.org” extension everywhere.

This applies to:

* frame title
* mode line
* menus

Extensions provide no useful information because every file is an Org file.

⸻

Agenda Naming

Current names:

Org Agenda
All

These names are implementation-oriented.

Use names based on purpose instead.

⸻

Dashboard

Main planning view.

Combines:

* scheduled items
* deadlines
* current tasks

Example mode line:

Dashboard

No position indicator.

Reason:

Dashboard is intentionally compact and focused.

⸻

Tasks

Full task list.

Example mode line:

Tasks · L120 · 64%

Position information is useful because this view can become long.

⸻

Treemacs / File View Mode Line

Purpose:

Display global planning-system status.

⸻

File Set Selector

Current:

[Focus ▼]

Question:

Should brackets remain?

⸻

Option A

[Focus ▼]

Pros:

* visually grouped
* resembles a control/widget

Cons:

* inconsistent with Org mode line

⸻

Option B (Preferred)

Focus ▼

Pros:

* cleaner
* matches file selector design
* more modern appearance

Recommendation:

Drop brackets.

⸻

Git Synchronization Status

Display after File Set selector.

Examples:

Focus ▼ · ✓ Sync

Focus ▼ · ↻ Syncing

Focus ▼ · ⚠ Sync Failed

Focus ▼ · ⊘ Sync Off

⸻

Compact Alternatives

Space may become limited.

Possible compact forms:

✓ Sync

↻ Sync

⚠ Failed

⊘ Off

⸻

Ultra-Compact Forms

✓

↻

⚠

⊘

Not recommended.

The user has already noted that icon-only states are difficult to remember.

Text should remain visible.

⸻

Last Successful Sync Time

Options:

Option A (Preferred)

Do not display.

Show only in tooltip/menu.

Example:

✓ Sync

Hover:

Last successful sync: 21:13

⸻

Option B

Display relative time.

✓ 3m

✓ 10m

Pros:

Compact.

Cons:

May create unnecessary visual noise.

⸻

Option C

Display absolute time.

✓ 21:13

Not recommended.

Consumes space without helping day-to-day workflow.

⸻

Consistency Rules

Use the same separator everywhere:

·

Examples:

Photo ▼ · L53 · 38% · Search Ranking > Dataset Cleanup

Tasks · L120 · 64%

Focus ▼ · ✓ Sync

Reason:

Clean and visually lightweight.

⸻

Summary of Current Recommendation

Org Files

Photo ▼ · L53 · 38% · Search Ranking > Dataset Cleanup

⸻

Dashboard Agenda

Dashboard

⸻

Tasks Agenda

Tasks · L120 · 64%

⸻

Treemacs / File View

Focus ▼ · ✓ Sync

Possible sync states:

✓ Sync
↻ Syncing
⚠ Sync Failed
⊘ Sync Off

⸻

Open Questions

Q1

Should the filename ever be truncated?

Current recommendation:

No.

Always preserve it.

⸻

Q2

Should Dashboard show position information?

Current recommendation:

No.

Dashboard is designed to be compact.

⸻

Q3

Should Git sync status display a timestamp?

Current recommendation:

No.

Keep status text only.

Expose timestamp via tooltip, popup, or menu.

⸻

Q4

Should heading navigation be implemented?

Current recommendation:

Not in version 1.

Display heading context only.

Add navigation later if needed.