---
toc: Pathfinder Second Edition
summary: Encounter mode, and where the help for each part of it is.
aliases:
- initiative
- init
- tinit
- encounter
- combat
---
# Pathfinder 2E Encounters

Invoking encounter mode (also known as _initiative_) changes the time flow of a scene. It is used when time must be closely tracked in order to understand the outcome.

The following commands are used to manage encounter mode in a scene. Note that in order to participate in an encounter, you must join the scene (not just watch).

For all commands, `+e`, "initiative" and "init" are short for "encounter": `+e/view` is `encounter/view`.

Everyone in an encounter has an id, shown by `+e/view` as `#1`, `#2` and so on. An id is never reused
in an encounter, so `#3` is the same goblin all fight long; commands that name someone take the id or
a name only one combatant has.

## Where to look

- `help encounter_player`: taking part - joining, your sheet in the encounter, the initiative table, Hero Points.
- `help encounter_runner`: running one - starting it, adding creatures, the initiative order, its difficulty, ending it.
- `help encounter_creatures`: running a creature - what its Strikes, abilities, auras and spells do for it.
- `help encounter_creatureimport`: a creature of your own, described on one line.
- `help encounter actions`: acting in an encounter - actions, Strikes and spells.
- `help pf2eadmin_rewards`: for staff, what an encounter pays.

## Bonuses and penalties

A bonus or penalty that lasts a while is an effect: `effect/add <who>=<effect>` puts someone under it -
Bless, Heroism, a potion - and its numbers reach every roll it applies to, and it ends at the right turn
on its own. See `help effects`. A combatant can be named by its id: `effect/add #3=bless`.

## Healing and Damage Commands

Damage, healing and conditions happen to a character as they stand in the encounter: `help heal`.
