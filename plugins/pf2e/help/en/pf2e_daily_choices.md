---
toc: Pathfinder Second Edition
summary: Choices your feats and class features have you make each day.
aliases:
- daily_choices
- dailychoices
---

# Daily Choices

Some feats and class features have you make a choice during your daily preparations. Each has its own switch on the `prepare` command. You can pick in an encounter or out of one. Your pick takes effect right away and stays locked until the GM next rests you (see `help rest`).

## Commands

`prepare/<switch>`: Lists what you can pick.
`prepare/<switch> <pick>`: Makes your pick.
`unprepare/<switch>`: Takes back a pick you made since your last rest. If it replaced a pick that was still in force, that pick comes back.
`prepared`: Shows your daily choices, after any prepared spells.

## Daily choice types

`prepare/longevity <skill>`: **Ancestral Longevity.** Picks the skill you're trained in until your next rest.
`prepare/studies <skill>`: **Flexible Studies.** Picks the skill you're trained in until your next rest.
`prepare/swordpractice <weapon>`: **Egalrin Weapon Familiarity.** Picks the sword you practice with. It stays in force until you pick another.
`prepare/armament <weapon>: <rune>`: **Blessed Armament.** Picks the weapon and the property rune for the day. Use `unarmed` for your unarmed attacks if you carry handwraps of mighty blows.
`prepare/scales <life or death>`: **Nudge the Scales.** Picks your side of the scales for the day.
`prepare/vialmaterial <material>`: **Advanced Vials** (Bomber). Picks the material of the day's versatile vials.
`prepare/broom <item>`: **Witch's Broom.** Picks the broom, staff, or polearm you anoint for the day.
`prepare/cauldron <oil or potion>`: **Cauldron.** Picks the oil or potion you brew each day, from the formulas you know. It stays in force until you pick another, and each rest brews a new batch. If you pick in an encounter, the batch is brewed there right away, and changing your pick replaces what's left of the old batch.
`prepare/charge <who>[, <who>...]`: **Witch's Charge.** Picks your charge for the day. With Witch's Communion, you can specify as many charges as your Intelligence modifier. Each charge sees the effect in their own effect list.
`prepare/rootmagic <who>`: **Root Magic.** Picks the ally you give your pouch to for the day.
`prepare/stratagem <who>[, <who>...]`: **Inspired Stratagem.** Picks up to five allies you review stratagems with for the day. Use the reaction with `encounter/act inspired stratagem=<who>`, once on each of them until your next rest.
`prepare/flexibility <feat>`: **Combat Flexibility.** Picks the fighter feat you have for the day.
`prepare/improvedflexibility <feat>`: **Improved Flexibility.** Picks your second fighter feat for the day.
`prepare/ultimateflexibility <feat>`: **Ultimate Flexibility.** Picks your third fighter feat for the day.
`prepare/spellshaping <feat>`: **Experimental Spellshaping.** Picks the spellshape feat you have for the day.

To pick a feat that has its own choice, put the choice after a colon, such as `prepare/flexibility Advanced Weapon Training: Sword`. Use the feat's name alone to see which choices you can make.
%t **Note:** You can't take back a flexibility feat while a later flexibility feat counts it towards its prerequisites. Take back the later one first.

A feat you have for the day is on your sheet, marked `DA`.

To specify someone, use the name of an approved character, or the name of a creature in your encounter. Put commas between names. With no names, `prepare/<switch>` lists the people in the room and the creatures in your encounter.
%t **Note:** A creature you specify counts only in the encounter you specified it in.

## Choosing again without a rest

Ultimate Flexibility and Radiant Armament let you change a choice before your next rest. Ask the GM, who uses `encounter/reprepare <who>` to unlock it for you to pick again. With Radiant Armament, pick the same weapon again with your new rune.
