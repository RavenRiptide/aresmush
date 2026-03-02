---
toc: Pathfinder Second Edition
summary: Commands related to experience and advancement.
aliases:
- advance
- advancement
- xp
- listxp
---

# Experience and Advancement in Pathfinder Second Edition

As in most games, Pathfinder Second Edition uses a system of Experience Points (XP) to track character growth and power increases over time. Unlike in D&D and Pathfinder First Edition, Pathfinder Second Edition does not operate on a sliding scale of increasingly large experience point totals needed to advance. Instead, to gain a level, you spend a flat 1000 XP, whether you are 1st level or 30th, and XP rewards remain the same per encounter or plot no matter your level. 

XP rewards per plot are shared publicly on the wiki and may be reviewed there. Your current XP total is listed at the top of your character sheet. 

Note that you cannot `advance` if you are in an active encounter. Scenes are fine, but you cannot advance in the middle of combat.

## Commands

`listxp`: View a history of your XP rewards and spends.
`advance`: Begins the advancement process. No modification to your sheet is made until you enter `advance/done`.
`advance/review`: Your guidebook for what you get and the options you need to select. (Alternative alias: `adv/review`)
`advance/raise ability = <ability>`: Raises an ability score to the next step. For example, `advance/raise ability=Strength` raises Strength.
`advance/raise skill = <skill>`: Raises a skill to the next step of proficiency. For example, `advance/raise skill=Nature` raises the Nature skill.
`advance/raise skill choice = <skill>`: If you have a skill training choice, such as from a Dedication feat, this command raises the chosen skill to the next step of proficiency. For example, if given the choice of Stealth or Thievery, input `advance/raise skill choice=Stealth` to raise the Stealth skill.
`advance/feat <type> = <feat>`: If advance/review indicates a feat to select, use this. Dedication feats are selected with class (charclass) feats. Type options: `general`, `skill`, `charclass`, or `ancestry`. Dedication and Archetype feats are `charclass` feats.
`advance/option <item> = <option>`: Some feats or class features require you to choose something else. Use this command to select those.
`advance/spell <type>/<level> = [<old spell>]/<spell>`: Selects a new spell. Type is either 'repertoire' or 'spellbook'. Note that you must either specify the spell to replace or have an open slot.
`advance/signature <spell>`: If `advance/review` indicates that this is needed, set a signature spell. 
`advance/done`: Locks your choices, takes you out of advancement mode, and updates your sheet. 
`advance/reset`: Backs out of advancement and discards all changes.