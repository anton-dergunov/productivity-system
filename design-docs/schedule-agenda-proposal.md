

## Iteration 7

In general I like the task representation now in agenda.
Both in Schedule view, as well as others task-based such as
Overdue, Scheduled earlier, etc.

My decision was to reserve space for different fields of the task

[category-icon] [TODO-state] [priority] [meaning-icon] [title] [metadata]

even if they are absent, so that the tasks read easier on the screen
and are all aligned in corresponding imaginary "columns".

Yes, the "Schedule" view also adds time, so it is not aligned with
other sections, but otherwise within this view all tasks are aligned.

One thing we really need to improve is to compact the spaces between these fields.
Because right now if say priority is missing, then there is too much space
between task state (such as TODO) and the meaning-icon and title text.

So let's reduce the space between:

1. category-icon & TODO-state. At least by half.
   Notice that the space between meaning-icon and title is quite small.
   I can position my cursor there, and I even see that cursor square is very narrow.
   We should use the same! And ideally all fields should share the same uniform
   narrow space between the fields.

2. TODO-state & priority. Should be same small space as before.
   But in this case if I position cursor on the gap and press left, then it moves
   to the priority green area. But there is a gap between this space and the green area
   which no character occupies. Remove this space entirely.
   Also it is very strange that when navigating TODO
   label, I actually navigate " TODO", but when navigating the priority, I actually
   navigate " #A ". So there is also extra space at the end.
   Even though TODO looks like has the same visual space at the end.
   Maybe that's just technicality. But if I am navigating with my keyboard, then this is not consistent.

3. The space between priority & meaning-icon is not too dramatic, but still
   decrease it just slightly by using the same smaller size space as between
   meaning-icon & title.

4. Priority right now is displayed visually as "#A". Let's reduce this to just "A"
   with the same green colour background (derived from thema).
   And in general think how to make this area smaller.
   This change should also affect how priority is displayed in org files!
   All of the changes that I propose must be consistent with org files representation of tasks,
   because essentially they are using the same org-modern mechanism there.

5. It is very strange, but these gaps for Schedule view are even more
   exhagerrated. It is very strange that the gap between TODO-state & priority
   is even more gigantic. Even much bigger. Why is that?
   The spaces between these fields shoudl be same in Schedule view.

Also neat picking, but right now the separator line in Schedule section
which is composed of chars "┆" looks a bit broken between the lines.
I guess there is some gap between the lines in agenda view, which is okay
(and probably even is very good!) but I would prefer that visually this line
reads a bit better visually if that's possible. List for me all the practical
solutions for this issue.

---


## Iteration 6

Let's fix these issues:

1. Issue 7 (that the font colour for tasks should be blue and basically
   derived from the org-scheduled colour) is still not fixed.

2. Make the font of "⚠ overlap" smaller. It must be the same as "⚑ 3w ago".

3. Report overlap only for the second task.
   You also mentioned O(n^2) algo for detecting overlap.
   I believe you can just do O(n) algo, because
   the tasks are always sorted in agenda view by start time, isn't it?
   Ah, wait, not quite... Because there could be these tasks:
   10:00-12:00
   10:15-10:30
   11:00-11:15
   So task 2 and 3 don't overlap. But task 1 overlaps with both 2 and 3.
   No worries, O(n^2) is not too bad, because the number tasks
   will be very small in Schedule view. But we need to report
   overlap only for the later task (which is displayed after).


---


## Iteration 5

Let's improve current implementation:

1. "overlap" text is not correctly aligned and positioned.
I see on the screen overla, and then the last p is not shown.
I think you are aligning this text with "4d ago" text in Overdue and other sections,
but this is wrong! This text has different width. So it should be positioned
independently.
But do you align these "4d ago" texts also on the same column? This might be okay,
but note that it might also be "11w ago", so this text could have different length.
So you need to take this into consideration.

2. The view in Schedule view is now displayed exactly taking all available window size.
But if you check other sections (such as Overdue, etc, so basically all other sections),
you would see that they have at least one char space from the left (beginning of line),
and also some gap from the right border (probably at least a char).

3. When refresh happens, you also need to respect which sections were hidden.
Right now I see that after refresh the sections are expanded.

4. Besides after refresh I see multiple messages in Messages
"Rebuilding agenda buffer...done"
So every second I get this message. Let's suppress that. Otherwise the Messages buffer
would collect too much such lines! it is okay to group them like Emacs does
such as in this example message "next-line: End of buffer [6 times]".
Or just disable for this particular case, since we are updating the agenda automatically.

5. let's center the "now line" instead to the whole row.
Right now it is centered in the "content column", but this looks not properly aligned.
Instead, let's center it vertically in the whole line.

6. Strangely, the now line does not update the time.
I see that "Rebuilding" messages in Messages buffer appear, but time is exactly
as it was when I started Emacs.

6. I see that both timeline rows and task times and text use the exactly same font.
At least there is very little difference. Maybe that's because
What could be a good the current colour schema that I use (solarized) already uses
grayish colour for font front. Is that right? In this case let's try to draw
task times and task titles in blue colour. Exactly as it used for the previous
implementation with default org-super-agenda. Don't hardcode any colour,
but use the colour derived from schema or from any agenda packages
or whatever is suitable, so that it would work with other colour schemes.




---


## Iteration 4

We have recently updated the representation of tasks and many aspects of agenda view.

The initial design was described in agenda-ui-redesign.md.

This has affected a lot of sections in the current agenda view (org-super-agenda),
such as Overdue, Scheduled earlier, etc.
This included the change of the task show.

In the new design the tasks area shown with this structure:
[category-icon] [TODO-state] [priority] [meaning-icon] [title] [metadata]

and these columns are visually aligned now.
For example, task titles all start at exactly the same visual column.
And so do other "columns".

However, the design of the Schedule section was not changed.

Specifically, this is still different:
- Both category text and icon are displayed
- Text "Scheduled:" is displayed
- And overall the new style of the task representation is not applied
- The scheduled tasks are displayed in blue colour which as no meaning

Beyond that the time grid display is not quite effective for representation and visually noizy.

Mostly I would like to make use of space more on the agenda better.

Right now the display is this way:

```
 Schedule:
     Career:         8:00-8:15  Scheduled:  TODO Learn conflict resolution techniques
                     8:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Career:        10:00-14:00 Scheduled:  TODO Test new
                    10:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    12:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    14:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Career:        15:00 ┄┄┄┄┄ Scheduled:  TODO Test
                    16:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Career:        17:00-18:00 Scheduled:  TODO Improve code review quality
                    17:29 ┄┄┄┄┄ ← now ───────────────────────────────────────────────
     Career:        17:30-18:30 Scheduled:  TODO Practice clearer async communication
                    18:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    20:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
```

Instead, I would like to support two modes:
- Timeline
- List (compact)

I don't actually like these names, so please suggest better names.

It must be possible to switch between these two modes in the menu "Productivity".
Schedule View:
  • Timeline
  • List

The Timeline mode must display this:

```
08:00-08:15 ┆ 👜 TODO Learn conflict resolution techniques
08:00 ┄┄┄┄┄ ┆
10:00-14:00 ┆ 👜 TODO Test new
10:00 ┄┄┄┄┄ ┆
12:00 ┄┄┄┄┄ ┆
14:00 ┄┄┄┄┄ ┆
15:00 ┄┄┄┄┄ ┆ 👜 TODO Test
16:00 ┄┄┄┄┄ ┆
17:00-18:00 ┆ 👜 TODO Improve code review quality
┄┄┄┄┄┄┄┄┄┄┄┄┆┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ now · 17:29 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
17:30-18:30 ┆ 👜 TODO Practice clearer async communication          ⚠ overlap
18:00 ┄┄┄┄┄ ┆
20:00 ┄┄┄┄┄ ┆
```

Open question: should I have "┄┄┄┄┄" in this part "16:00 ┄┄┄┄┄"?
Maybe it is less visually heavy without.
On the other hand, I find it also rhythmic and probably easier to parse.

List view must display:

```
08:00-08:15 ┆ 👜 TODO Learn conflict resolution techniques
10:00-14:00 ┆ 👜 TODO Test new
15:00       ┆ 👜 TODO Test
17:00-18:00 ┆ 👜 TODO Improve code review quality
┄┄┄┄┄┄┄┄┄┄┄┄┆┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ now · 17:29 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
17:30-18:30 ┆ 👜 TODO Practice clearer async communication           ⚠ overlap
```

Ah, right, now if you look at it,
the only difference between Timeline and List view is if we overlay these fixed times.

Note that the "now" line must be centrally located.

And also as for the other agenda, as soon as I resize the window, this view must
be updated.
Tasks must be shortened in the same way with ... symbol as in the other agenda section.

I will later decide if I want to use symbols like ┄┄┄ and ┆, or maybe just
solve it using a font (I think that would be easier with font colour!)

So all the same, but the time grid is not shown.

In this case 👜 is the category icon.

Note that the tasks must use the same structure as before:

[category-icon] [TODO-state] [priority] [meaning-icon] [title] [metadata]

in the examples above I just didn't show [priority] [meaning-icon].
But do reserve space for them and make sure that task titles are still aligned.
As well as all the columns are aligned!
Except that metadata in this case is only for overlapping detection as shown in example above.

Note the now line is displayed for the current time.

We should add a config option and expose it also in the menu "Productivity"
which would allow customizing whether the agenda view will be refreshed
every minute to move this "now" line and move it accordingly.
Note that the timer must be exactly when the second is 0. So every minute, but when second is 0.
This setting must be on by default.
Some tasks might be marked as DONE. So they could disappear from the view.
But the view must preserve the current cursor position and current scroll position as much as possible.
Ideally the screen refresh should not be noticeable at all.

The use of colours:

the timeline outline, now line, any times without tasks -> gray (or whatever is set in the colour schema, muted colour)
lines with tasks including title -> normal foreground
TODO      -> current TODO face
priority  -> current priority face
overlap   -> orange/yellow or whatever colour would make sense for org agenda settings and colour schema (maybe even red)


---

# Iteration 3

This is great chat, I really like it. Let's continue with it!

I have integrated many of your suggestions.
So please critique this plan even more regarding this exact visual issues.
So I welcome all the tiny details for the visual representation aspect.
Let's make it perfect! It must really look very polished.

But the most important aspect of this is of course what you said
"you’re mixing two visual models".
And you have presented two great alternatives.

But I must say: I am now more or less satisfied with the list view.
I think I would find the information displayed in this format good to read.
yet of course the visual little things, let's adjust it.

But the whole timeline view is a big opportunity to improve.

So why it is too "engineering"-like design?
Because that's how org agenda displays this by default.
And I agree, initially it was very confusing, and I found it very
confusing personnaly for me.
I understand that it was just a simple thing, and probably practical,
and clear how to do. You just take the agenda timeline times listed in config.
Just display that and overlay tasks. Clear from the engineering perspective, but not clear visually at all.

But we need to take several aspects in consideration:

1. For me personally task durations are very important.
And the representation of the duration as you propose as metadata
08:00 │ 👜 TODO Learn conflict resolution techniques   15m
10:00 │ 👜 TODO Test new                               4h
is a great idea! But for me visually I may find it easier to parse it when
the end time is provided instead. In this case I would not have to do
mental arithmetic (especially for many tasks) to try to understand
how they span and if they overlap, etc.
08:00-08:15 ┆ 👜 TODO Learn conflict resolution techniques
10:00-14:00 ┆ 👜 TODO Test new

So kind of I can visually understand where are the gaps for me in this schedule.
Seeing gaps is important for me!
And this is why I would use the Timeline view.
If I didn't care about gaps, I would use the List view. It is more compressed as well.
I kind of want to see how long task takes and how it maps to the time.

2. We are constrained by the representation of the text mode.
Tools like Outlook don't have this problem, because timeline is drawn graphically.
Here I am using text mode to display it.
This of course brings the question: maybe then I should use graphical mode in Emacs?
Is this even possible? To display this as a picture then...
yet displaying as text looks kind of cool. So I may keep textual format as well.
For simplicity, testability, for practical purposes.
It is not often that I have too many things on my calendar. Just yet haha.

So on the one hand I like your suggestion like this:

```
08:00 ├─ 👜 TODO Learn conflict resolution techniques
      │
10:00 ├─ 👜 TODO Test new
      │
12:00 │
      │
14:00 │
15:00 ├─ 👜 TODO Test
      │
17:00 ├─ 👜 TODO Improve code review quality
17:29 ├──────────── now
17:30 ├─ 👜 TODO Practice clearer async communication
18:00 │
20:00 │
```

But for me it has 2 problems:
a. Duration is not present (can be fixed by the duration column, but I find it harder to parse)
b. Visually I don't see the duration of tasks on this timeline...
And related to this: What if say I have lots of small tasks at between 15:00 and 17:00.
In this design above you kind of reserve a line per hour.
But things break if the task distribution is not even. Yes, I could kind of expand
the timeline in this region. That's okay.

On the other hand, I really don't like as well how Emacs is showing this now.
Take a look:

```
     Career:        10:00-14:00 Scheduled:  TODO Test new
                    10:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    12:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    14:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
```

A big task, yet there is no kind of visual clue.

Let's discuss this aspect in more and more details.
List me many options around this issue.

We have recently updated the representation of tasks and many aspects of agenda view.

The initial design was described in agenda-ui-redesign.md.

This has affected a lot of sections in the current agenda view (org-super-agenda),
such as Overdue, Scheduled earlier, etc.
This included the change of the task show.

In the new design the tasks area shown with this structure:
[category-icon] [TODO-state] [priority] [meaning-icon] [title] [metadata]

and these columns are visually aligned now.
For example, task titles all start at exactly the same visual column.
And so do other "columns".

However, the design of the Schedule section was not changed.

Specifically, this is still different:
- Both category text and icon are displayed
- Text "Scheduled:" is displayed
- And overall the new style of the task representation is not applied
- The scheduled tasks are displayed in blue colour which as no meaning

Beyond that the time grid display is not quite effective for representation and visually noizy.

Mostly I would like to make use of space more on the agenda better.

Right now the display is this way:

```
 Schedule:
     Career:         8:00-8:15  Scheduled:  TODO Learn conflict resolution techniques
                     8:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Career:        10:00-14:00 Scheduled:  TODO Test new
                    10:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    12:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    14:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Career:        15:00 ┄┄┄┄┄ Scheduled:  TODO Test
                    16:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Career:        17:00-18:00 Scheduled:  TODO Improve code review quality
                    17:29 ┄┄┄┄┄ ← now ───────────────────────────────────────────────
     Career:        17:30-18:30 Scheduled:  TODO Practice clearer async communication
                    18:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    20:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
```

Instead, I would like to support two modes:
- Timeline
- List (compact)

I don't actually like these names, so please suggest better names.

It must be possible to switch between these two modes in the menu "Productivity".
Schedule View:
  • Timeline
  • List

The Timeline mode must display this:

```
08:00-08:15 ┆ 👜 TODO Learn conflict resolution techniques
08:00 ┄┄┄┄┄ ┆
10:00-14:00 ┆ 👜 TODO Test new
10:00 ┄┄┄┄┄ ┆
12:00 ┄┄┄┄┄ ┆
14:00 ┄┄┄┄┄ ┆
15:00 ┄┄┄┄┄ ┆ 👜 TODO Test
16:00 ┄┄┄┄┄ ┆
17:00-18:00 ┆ 👜 TODO Improve code review quality
17:29 ┄┄┄┄┄┄┆┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ now ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
17:30-18:30 ┆ 👜 TODO Practice clearer async communication          ⚠ overlap
18:00 ┄┄┄┄┄ ┆
20:00 ┄┄┄┄┄ ┆
```

Open question: should I have "┄┄┄┄┄" in this part "16:00 ┄┄┄┄┄"?
Maybe it is less visually heavy without.
On the other hand, I find it also rhythmic and probably easier to parse.

List view must display:

```
08:00-08:15 ┆ 👜 TODO Learn conflict resolution techniques
10:00-14:00 ┆ 👜 TODO Test new
15:00       ┆ 👜 TODO Test
17:00-18:00 ┆ 👜 TODO Improve code review quality
┄┄┄┄┄┄┄┄┄┄┄┄┆┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ now · 17:29 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
17:30-18:30 ┆ 👜 TODO Practice clearer async communication           ⚠ overlap
```

I will later decide if I want to use symbols like ┄┄┄ and ┆, or maybe just
solve it using a font (I think that would be easier with font colour!)

So all the same, but the time grid is not shown.

In this case 👜 is the category icon.

Note that the tasks must use the same structure as before:

[category-icon] [TODO-state] [priority] [meaning-icon] [title] [metadata]

in the examples above I just didn't show [priority] [meaning-icon].
But do reserve space for them and make sure that task titles are still aligned.
As well as all the columns are aligned!
Except that metadata in this case is only for overlapping detection as shown in example above.

Note the now line is displayed for the current time.

We should add a config option and expose it also in the menu "Productivity"
which would allow customizing whether the agenda view will be refreshed
every minute to move this "now" line and move it accordingly.
Note that the timer must be exactly when the second is 0. So every minute, but when second is 0.
This setting must be on by default.
Some tasks might be marked as DONE. So they could disappear from the view.
But the view must preserve the current cursor position and current scroll position as much as possible.
Ideally the screen refresh should not be noticeable at all.

The use of colours:

time      -> gray (or whatever is set in the colour schema, muted colour)
timeline  -> gray
title     -> normal foreground
TODO      -> current TODO face
priority  -> current priority face
overlap   -> orange/yellow
overdue   -> red








----

## Iteration 2


We have recently updated the representation of tasks and many aspects of agenda view.

The initial design was described in agenda-ui-redesign.md.

This has affected a lot of sections in the current agenda view (org-super-agenda),
such as Overdue, Scheduled earlier, etc.
This included the change of the task show.

In the new design the tasks area shown with this structure:
[category-icon] [TODO-state] [priority] [meaning-icon] [title] [metadata]

and these columns are visually aligned now.
For example, task titles all start at exactly the same visual column.
And so do other "columns".

However, the design of the Schedule section was not changed.

Specifically, this is still different:
- Both category text and icon are displayed
- Text "Scheduled:" is displayed
- And overall the new style of the task representation is not applied
- The scheduled tasks are displayed in blue colour which as no meaning

Beyond that the time grid display is not quite effective for representation and visually noizy.

Mostly I would like to make use of space more on the agenda better.

Right now the display is this way:

```
 Schedule:
     Career:         8:00-8:15  Scheduled:  TODO Learn conflict resolution techniques
                     8:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Career:        10:00-14:00 Scheduled:  TODO Test new
                    10:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    12:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    14:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Career:        15:00 ┄┄┄┄┄ Scheduled:  TODO Test
                    16:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Career:        17:00-18:00 Scheduled:  TODO Improve code review quality
                    17:29 ┄┄┄┄┄ ← now ───────────────────────────────────────────────
     Career:        17:30-18:30 Scheduled:  TODO Practice clearer async communication
                    18:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    20:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
```

Instead, I would like to support two modes:
- Timeline
- List (compact)

I don't actually like these names, so please suggest better names.

It must be possible to switch between these two modes in the menu "Productivity".
Schedule View:
  • Timeline
  • List

The Timeline mode must display this:

```
08:00-08:15 ┆ 👜 TODO Learn conflict resolution techniques
08:00 ┄┄┄┄┄ ┆
10:00-14:00 ┆ 👜 TODO Test new
10:00 ┄┄┄┄┄ ┆
12:00 ┄┄┄┄┄ ┆
14:00 ┄┄┄┄┄ ┆
15:00 ┄┄┄┄┄ ┆ 👜 TODO Test
16:00 ┄┄┄┄┄ ┆
17:00-18:00 ┆ 👜 TODO Improve code review quality
17:29 ┄┄┄┄┄┄┆┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ now ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
17:30-18:30 ┆ 👜 TODO Practice clearer async communication          ⚠ overlap
18:00 ┄┄┄┄┄ ┆
20:00 ┄┄┄┄┄ ┆
```

List view must display:

```
08:00-08:15 ┆ 👜 TODO Learn conflict resolution techniques
10:00-14:00 ┆ 👜 TODO Test new
15:00       ┆ 👜 TODO Test
17:00-18:00 ┆ 👜 TODO Improve code review quality
┄┄┄┄┄┄┄┄┄┄┄┄┆┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ now · 17:29 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
17:30-18:30 ┆ 👜 TODO Practice clearer async communication           ⚠ overlap
```

So all the same, but the time grid is not shown.

In this case 👜 is the category icon.

Note that the tasks must use the same structure as before:

[category-icon] [TODO-state] [priority] [meaning-icon] [title] [metadata]

in the examples above I just didn't show [priority] [meaning-icon].
But do reserve space for them and make sure that task titles are still aligned.
As well as all the columns are aligned!
Except that metadata in this case is only for overlapping detection as shown in example above.

Note the now line is displayed for the current time.

We should add a config option and expose it also in the menu "Productivity"
which would allow customizing whether the agenda view will be refreshed
every minute to move this "now" line and move it accordingly.
Note that the timer must be exactly when the second is 0. So every minute, but when second is 0.
This setting must be on by default.
Some tasks might be marked as DONE. So they could disappear from the view.
But the view must preserve the current cursor position and current scroll position as much as possible.
Ideally the screen refresh should not be noticeable at all.

The use of colours:

time      -> gray (or whatever is set in the colour schema, muted colour)
timeline  -> gray
title     -> normal foreground
TODO      -> current TODO face
priority  -> current priority face
overlap   -> orange/yellow
overdue   -> red






---


## Iteration 1


We have recently updated the representation of tasks and many aspects of agenda view.

The initial design was described in agenda-ui-redesign.md.

This has affected a lot of sections in the current agenda view (org-super-agenda),
such as Overdue, Scheduled earlier, etc.
This included the change of the task show.

In the new design the tasks area shown with this structure:
[category-icon] [TODO-state] [priority] [meaning-icon] [title] [metadata]

and these columns are visually aligned now.
For example, task titles all start at exactly the same visual column.
And so do other "columns".

However, the design of the Schedule section was not changed.

Specifically, this is still different:
- Both category text and icon are displayed
- Text "Scheduled:" is displayed
- And overall the new style of the task representation is not applied
- The scheduled tasks are displayed in blue colour which as no meaning

Beyond that the time grid display is not quite effective for representation and visually noizy.

Mostly I would like to make use of space more on the agenda better.

Right now the display is this way:

```
 Schedule:
     Career:         8:00-8:15  Scheduled:  TODO Learn conflict resolution techniques
                     8:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Career:        10:00-14:00 Scheduled:  TODO Test new
                    10:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    12:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    14:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Career:        15:00 ┄┄┄┄┄ Scheduled:  TODO Test
                    16:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Career:        17:00-18:00 Scheduled:  TODO Improve code review quality
                    17:29 ┄┄┄┄┄ ← now ───────────────────────────────────────────────
     Career:        17:30-18:30 Scheduled:  TODO Practice clearer async communication
                    18:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
                    20:00 ┄┄┄┄┄ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
```

Instead, I would like to support two modes:
- Full
- Compressed/compact

I don't actually like these names, so please suggest better names.

It must be possible to switch between these two modes in the menu "Productivity".

The full model must display this:

```
08:00-08:15 │ 👜 TODO Learn conflict resolution techniques
08:00 ┄┄┄┄┄ |
10:00-14:00 │ 👜 TODO Test new
10:00 ┄┄┄┄┄ │
12:00 ┄┄┄┄┄ │
14:00 ┄┄┄┄┄ │
15:00 ┄┄┄┄┄ │ 👜 TODO Test
16:00 ┄┄┄┄┄ │
17:00-18:00 │ 👜 TODO Improve code review quality
17:29 ┄┄┄┄┄ ├─────────────────────────────── now ────────────────────────────
17:30-18:30 │ 👜 TODO Practice clearer async communication    ⚠ overlaps 17:00
18:00 ┄┄┄┄┄ │
20:00 ┄┄┄┄┄ │
```




Compressed view must display:

```
08:00-08:15  👜 TODO Learn conflict resolution techniques
10:00-14:00  👜 TODO Test new
15:00        👜 TODO Test
17:00-18:00  👜 TODO Improve code review quality
─────────────────────────────── now · 17:29 ─────────────────────────────────
17:30-18:30  👜 TODO Practice clearer async communication    ⚠ overlaps 17:00
```

So all the same, but the time grid is not shown.

In this case 👜 is the category icon.

Note that the tasks must use the same structure as before:

[category-icon] [TODO-state] [priority] [meaning-icon] [title] [metadata]

in the examples above I just didn't show [priority] [meaning-icon].
But do reserve space for them and make sure that task titles are still aligned.
As well as all the columns are aligned!
Except that metadata in this case is only for overlapping detection as shown in example above.

Note the now line is displayed for the current time.

We should add a config option and expose it also in the menu "Productivity"
which would allow customizing whether the agenda view will be refreshed
every minute to move this "now" line and move it accordingly.
Note that the timer must be exactly when the second is 0. So every minute, but when second is 0.
This setting must be on by default.
Some tasks might be marked as DONE. So they could disappear from the view.
But the view must preserve the current cursor position and current scroll position as much as possible.
Ideally the screen refresh should not be noticeable at all.




---

## Initial question

Propose a better UI design specifically for the "Schedule" part of my agenda in Emacs. I am using planning in org files. And I am using org-super-agenda to break the tasks into separate sections. Basically breaks the current tasks of the day into user defined sections. Don't worry too much about that package itself too much. I have already customized it to my liking. So as you can see I split my tasks into Overdue, Scheduled earlier, High-priority, In progress and other tasks. Now I am going much further than what this package provides. Right now my goal is to customize how tasks inside these sections are represented. You can see that right now all the tasks in these sections (except for Schedule) are displayed nicely and uniformly. Firsts, I display an icon which shows the category of the task. Then the task state (as in org mode), for example TODO, INPR (meaning in progress), WAIT, etc. Then optionally a task priority (as defined in org files), then (optionally) an icon representing the task visual meaning quickly, then the task name (with tags if they are present), then also optionally overdue markers like "2d ago" right at the very right edge. The important design consideration for these sections was to have a shared column layout for these fields of tasks. So right now task titles are all displayed in the same column visually, as well as all other fields. Even if a task does not have a priority assigned, I still reserve some space for it. This design decision was made so that I could quickly scan the tasks without spending extra energy just to parse a different layout all the time. And also I have tried to compact the view and information, so that as much space is provided (vertically on each line) for each task title as possible. Because task title is the most important part here! That's why for example I have removed the task category from this view and replaced that with icon (but in the Schedule section I still display both the icon and the category name). So the design of these sections is more or less complete. I would appreciate your comments and critique about this design, but my big question to you right now is about the Schedule section. This section shows the time-bound tasks for this particular day. You can see the day of the agenda at the top of this view. And so Schedule display tasks which have a particular time assigned (and not just only a date) and planned for this particular day. That's why the built in methods org support in Emacs display time grid (or whatever it is called; what is the correct term for it here?) and the tasks are displayed bound to the particular time. The problem is that I still need to customize the display of tasks here, so that the space is effectively used, I am able to scan the tasks quickly and so that it is now consistent with my design of representation with other sections. So definitely I would remove task category names ("Career" in the screenshot) and will only leave the icon. I would also remove the word "Scheduled: ", because this has no purpose now. They are all scheduled tasks. But let's go further than that! Your task is to propose for me the real great UI designs for this "Schedule" section. It would be great if you can produce for me great ideas in text for UI improvements to this section, but please also draw how tasks can be represented in this section (and the time grid as well). So output for me both text and pictures for UI design. So that it looks modern, functional, minimalistic, consistent, practical, clearly visible, but not distracting. Probably the blue colour has no meaning there. Or has it? (For "overdue" tasks I can justify the red colour as something related to urgency.) I am also constrained by what is possible in Emacs and its org system. So the design also must be realistic and grounded in this text-editor-based representation. But please don't consider the implementation of that just yet. Focus on the design (and don't let the implementation details restrict your imagination and your designs). So the main task for you is the designs of this Schedule section (I would appreciate comments on other parts of the UI if they are easy to spot, but the main focus is on that Schedule section).

