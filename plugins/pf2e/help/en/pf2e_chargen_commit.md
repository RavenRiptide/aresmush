---
toc: Pathfinder Second Edition
summary: Starting character generation - committing, restoring, and undoing chargen stages.
aliases:
- commit
- restore
- cg_restore
- undo
- cg_undo
---

# Pathfinder 2E Chargen - Committing and Restoring Stages

You build your Pathfinder 2e sheet in stages, because later choices depend on earlier ones. When you finish a stage, `commit` locks in your choices and moves you to the next stage. If you change your mind later, `cg/restore` takes you back to the start of a committed stage.

## Stages

`info`: Choose your ancestry, heritage, background, class, specializations, and other basic details.
`abilities`: Assign attribute boosts to set your final attribute scores.
`skills`: Choose your skills and languages.

You assign feats last, along with magic if your character casts spells. Feats have no stage to commit. Once nothing is left to assign, `cg/review` shows your finished sheet and tells you how to submit it for approval.

## Undoing a choice

`cg/undo` takes back your choices one at a time, starting with the newest. Because it works backward, a later choice always comes off before any earlier choice it depends on. For example, if you took a class feat and then a skill feat that requires it, `cg/undo` removes the skill feat first and the class feat second.

`cg/undo` reaches back only as far as the start of chargen. After your character is approved, only staff can change it.

## Commands

`commit <stage>`: Locks in your choices for `<stage>` and moves you to the next stage. `cg/commit <stage>` does the same thing.
`cg/restore <stage>`: Returns your character to the point before you committed `<stage>`, so you can change your basic info, attribute boosts, or skills.
%t **Note:** After you make your changes, run `commit <stage>` again to move on.
%t **Example:** To change your ancestry and background, run `cg/restore info`, make your changes, and then run `commit info`.
`cg/undo`: Takes back your most recent choice, such as a pick, a boost, a language, or a feat. Run it again to take back the choice before that.
`cg/redo`: Puts back the last choice you took back with `cg/undo`.
`commit featskills`: Locks your skills again after a feat unlocked them.
%t **Note:** Some feats grant a skill of your choice, or grant a skill you're already trained in and give you a free skill instead. Either kind unlocks your skills so you can assign the skill with `skill/set free=<skill>`. You must lock your skills again before you take another feat, so assign the skill and run `commit featskills` first.
