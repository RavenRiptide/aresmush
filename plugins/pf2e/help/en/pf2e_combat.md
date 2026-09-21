---
toc: Pathfinder Second Edition
summary: Encounter-related commands.
aliases:
- initiative
- init
- tinit
- damage
- heal
- encounter
- combat
---
# Pathfinder 2E Encounters

Invoking encounter mode (also known as _initiative_) changes the time flow of a scene. It is used when time must be closely tracked in order to understand the outcome.

The following commands are used to manage encounter mode in a scene. Note that in order to participate in an encounter, you must join the scene (not just watch).

For all commands, `+e`, "initiative" and "init" are short for "encounter": `+e/view` is `encounter/view`.

Everyone in an encounter has an id, shown by `+e/view` as `#1`, `#2` and so on. An id is never reused
in an encounter, so `#3` is the same goblin all fight long; commands that name someone take the id or
a name only one combatant has. Acting in an encounter - actions, Strikes, spells - is in
`help encounter actions`.

## Encounter commands for participants

`encounter/join <encounter ID>[=<stat>]`: Joins an encounter in progress, using the stat specified by the organizer by default. If the organizer tells you that you should use a different stat, specify <stat>. 
`+e/sheet[ <#id or name>][/<section>]`: A character's sheet as they stand in this encounter: their Hit Points, conditions and what they are under, which `sheet` does not show. Sections are those of `sheet`.
`encounter/view [<encounter ID>]`: View the initiative table for the encounter in question: each combatant's id, initiative, conditions, and the cover and concealment set on them. (Alias `tinit <encounter ID>`)
`+e/creature <#id>`: A creature's name and conditions. The GM sees its whole stat block and hit points.

## Encounter commands for plot runners

`encounter [<stat>][=<encounter ID>]`: Starts an encounter in the scene, with you as its GM, rolling initiative on `<stat>` (Perception unless you say otherwise). Name an earlier encounter and whoever was in it carries on as they left it: their wounds, conditions, effects and spent spells. Anyone else starts fresh - their own sheet, rested.
`+e/add [<count>] <creature>[=<name>]`: Adds creatures from the bestiary - Foundry's bestiaries, six thousand of them - each with its own id, hit points and conditions, and its initiative rolled on its Perception. `+e/add 3 goblin warrior` adds three; `+e/add goblin warrior=Grik` names one. Player characters join with `encounter/join`. (Alias: `jinit`)
`+e/add <name>=ac <n> fort <n> ref <n> will <n> perception <n> hp <n>`: Adds a creature the bestiary lacks, from the numbers on its stat block. It has no Strikes of its own; roll its attacks with `roll`.
`+e/bestiary <words>[/<level>]`: Creatures whose names hold the words, at a level if one is given.
`+e/creature <creature>`: A creature's stat block from the bestiary.
`encounter/mod [<encounter ID>=]<#id or name>=<new init>`: Sets a combatant's initiative. Whoever's turn it is keeps it.
`encounter/remove [<encounter ID>=]<#id or name>`: Takes a combatant out of the order; a creature removed is gone. (Alias: `rminit`)
`encounter/next`: Moves the initiative forward one turn. (Alias: `ninit`)
`encounter/prev`: Moves the initiative backwards one turn. (Alias: `pinit`)
`encounter/scan`: Allows the organizer to view details on all player characters who have joined the encounter. (Alias: `tscan`)
`encounter/end <encounter ID>`: Ends an encounter. Trust given for it, the cover and concealment set in it, and what may be used once an encounter all end with it.
`encounter/restart <encounter ID>`: Restarts an encounter, so long as the scene has not ended.

## Bonuses and penalties

A bonus or penalty that lasts a while is an effect: `effect/add <who>=<effect>` puts someone under it -
Bless, Heroism, a potion - and its numbers reach every roll it applies to, and it ends at the right turn
on its own. See `help effects`. A combatant can be named by its id: `effect/add #3=bless`.

## Healing and Damage Commands

Damage, healing and conditions happen to a character as they stand in the encounter: `help heal`.
