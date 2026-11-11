---
toc: Pathfinder Second Edition - Running Encounters
summary: What the game does with a creature's stat block, and what's left to you.
aliases:
- e_abilities
- e_affliction
- encounter_creatures
- pf2e_encounter_creatures
- constrict
- swallow_whole
- knockdown
- breath_weapons
- recharge
- ferocity
---
# Pathfinder 2E Encounters - Creature Abilities

The game runs as much of a creature's stat block as it can. When the creature uses anything else, the game shows the room the text as written, and you apply what it does by hand, with commands such as `damage`, `condition/set`, and `effect/add`. Only you see a creature's turn reminder and its hit points.

## Strikes

- **Grab, Knockdown, and Push:** When a Strike that lists one of these hits, the game gives you the command for the follow-up, such as `encounter/as #5=act grab=#2`. Use it as the creature's next action.
- **Abilities that Strike several targets**, such as a hydra's Storm of Jaws, Strike each target you specify.
- **Strikes that need reloading** fire once. `encounter/as #5=reload` reloads them.
- **Optional circumstances**, such as Pack Attack or a charge, are off until you turn them on: add `/pack attack` to the Strike, or use `encounter/option #5=pack-attack/on`.

## Abilities

- **Abilities with a save**, such as a breath weapon or a gaze: specify every target, and each one rolls the save. `encounter/as #5=act flame breath=#1,#2,#3`
- **Auras with a save**, such as Frightful Presence: place combatants inside the aura, and each one rolls the save. `encounter/as #5=enter frightful presence=#1,#2`
- **Constrict** damages everyone the creature is holding, or only the ones you specify. **Swallow Whole** only works on a target the creature is holding.
- **Abilities with a variable action cost**, such as a troop's `1 to 3` attack: add the actions you spend, such as `/actions 2`. Without it, the creature spends one action.
- **Abilities triggered by dropping**, such as Ferocity, are offered when the creature drops to 0 HP.
- **Recharging, reactions, and limited-use abilities** are up to you. The game tells you when a recharging ability is back, and warns you if you use any of them early.
- **Spells** are tracked by slot, prepared copy, or daily use. Past the limit, the game warns you, but still casts the spell.

## Afflictions, shields, and shapes

`encounter/affliction <who>=<name>/<stage>`: Sets an affliction's stage by hand, for stages measured in days. Stage 0 cures it.
`encounter/as #5=act raise a shield`: Raises a creature's shield. Use `encounter/as #5=act shield block` when the game says a hit can be blocked.
`encounter/as #5=act change shape/<shape>`: Changes a creature's shape with its own ability, such as a werewolf's. Its shape decides which Strikes it has. `encounter/creature #5` shows its current shape.
%t **Note:** Adamantine halves Hardness of 10 or less. Specify it when you deal damage: `damage #5=12 slashing adamantine`.
