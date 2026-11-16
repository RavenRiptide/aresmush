---
toc: Pathfinder Second Edition - Advancement
tutorial: true
summary: Commands related to experience and advancement.
aliases:
- advance
- advancement
- xp
- listxp
---

# Experience and Advancement in Pathfinder Second Edition

As in most games, Pathfinder Second Edition uses Experience Points (XP) to determine character progression. Unlike D&D and Pathfinder First Edition, Pathfinder Second Edition doesn't need ever-larger XP totals to advance: gaining a level costs a flat 1000 XP, whether you are 1st level or 19th, and XP awards stay the same per encounter or plot no matter your level.

The wiki lists the XP awards for each plot. Your current XP total is at the top of your character sheet.

You can't use `advance` during an active encounter. Scenes are fine.

## General Advancement Commands

**Commands**:
`listxp`: Shows a history of the XP you've been awarded and spent.
`advance`: Starts a level-up. Your sheet doesn't change until you enter `advance/done`.
`advance/review`: Lists what this level gives you and the choices you still need to make. `adv/review` also works.
`advance/info <element>`: Lists the options for anything `advance/review` lists as outstanding. For an open feat slot, specify its slot type to list the feats you're eligible for, such as `advance/info skill`. Add `=<text>` to narrow a long list, such as `advance/info skill=cat`. For more information about feat slots, see `help advancefeats`. For more information about class feature and feat options, see `help advancefeatures`.
`advance/done`: Locks in your choices, ends the level-up, and updates your sheet.
`advance/reset`: Ends the level-up and discards all your choices.
`advance/undo`: Takes back your most recent choice this level, one step at a time, newest first.
`advance/redo`: Puts back the last choice you took back with `advance/undo`.
%t **Note:** Neither `advance/undo` nor `advance/redo` reaches past `advance/done`. Once you lock in a level, only staff can change it, using `admin/rollback`.

### Raising Attributes and Skills, and Learning Languages
For more information about raising attributes and skills and learning languages, see `help advanceskills`.

### Selecting Feats
For more information about selecting feats, see `help advancefeats`.

### Choosing Class Feature and Feat Options
For more information about choosing options for class features and feats, see `help advancefeatures`.

### Learning Spells
For more information about learning spells, see `help advancespells`.

### Picking Formulas
For more information about picking formulas, see `help advanceformulas`.

### Archetypes and Dedications
For more information about archetypes and Dedication feats, see `help advancearchetypes`.
