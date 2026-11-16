---
toc: Pathfinder Second Edition - Advancement
summary: Commands related to advancement and class feature options.
aliases:
- advancefeatures
- advanceoptions
---

# Advancement - Choosing Class Feature and Feat Options

See `help advance` for more information about advancement.

## Choosing Options

Some class features and feats you gain in a level-up require that you choose an option, such as a weapon group or an ancestry. Others give you a feat, a skill, or a Lore to choose, such as an investigator's Skillful Lessons. `advance/review` lists each one under Options To Choose.

Choose every one of them with `advance/option`, including options that give you a feat. `advance/feat` only fills open feat slots.

**Commands**:
`advance/info <feature>`: Lists the options you're eligible for in a class feature or feat (`<feature>`).
`advance/info <feature>=<text>`: Lists only the options whose names contain `<text>`, such as `advance/info Additional Lore=arch`.
`advance/info<page> <feature>`: Shows another page of a long list, such as `advance/info2 Skillful Lessons`. The bottom of each page shows the command for the next page.
`advance/option <feature>=<option>`: Chooses an option (`<option>`) for a class feature or feat (`<feature>`) that `advance/review` lists as needing one. Choose again until the feature has no open picks left.
%t **Examples**:
%t `advance/option Ancestral Paragon=Nimble Sil`: Chooses Nimble Sil for Ancestral Paragon, if your character is a sildanyar or silyara.
%t `advance/option Fighter Weapon Mastery=sword`: Chooses the sword group for a fighter's Fighter Weapon Mastery.
%t `advance/option Skillful Lessons=Recognize Spell`: Chooses the Recognize Spell skill feat for an investigator's Skillful Lessons.

For more information about formula choices, such as an alchemist's Formula Book, see `help advanceformulas`.
