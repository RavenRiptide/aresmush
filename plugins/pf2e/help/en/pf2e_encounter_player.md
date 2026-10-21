---
toc: Pathfinder Second Edition
summary: Encounter commands for everyone taking part.
aliases:
- encounter_player
- encounter player
---
# Pathfinder 2E Encounters - Taking Part

Everyone in an encounter has an id, shown by `+e/view` as `#1`, `#2` and so on: see `help encounter`.

**You fight with what you carried in.** Joining an encounter takes a copy of your gear, what you have equipped and invested, and your money. Your Strikes, AC and everything you use there come from that copy, so anything you buy, sell or equip on your own sheet afterwards is not part of this encounter. `+e/gear` shows what you carry here, and `+e/equip` draws a weapon or puts on armour from it. Your own items that went in with you can't be used or sold on your sheet until the encounter ends. `help encounter actions` has the details, under "What you carry".

`encounter/join [<encounter ID>=][<stat>]`: Joins an encounter, rolling initiative on the statistic its GM named - Perception unless they said otherwise. If the GM tells you to roll something else, name it: Perception, a skill, or an ability, in any case, by its first letters or an ability's three: `encounter/join 12=stealth`, `encounter/join dex`.
`+e/sheet[ <#id or name>][/<section>]`: A character's sheet as they stand in this encounter: their Hit Points, conditions and what they are under, which `sheet` does not show. Sections are those of `sheet`.
`encounter/view [<encounter ID>]`: View the initiative table for the encounter in question: each combatant's id, initiative, conditions, and the cover and concealment set on them, and the address of its page on the web, which the scene's Play menu on the web also links to. (Alias `tinit <encounter ID>`)
`+e/creature <#id>`: A creature's name and conditions. Its stat block and hit points are its GM's to see.
`hero`, `hero/reroll`, `hero/boost`, `hero/survive`: Your Hero Points in the scene, and spending one to roll your last check again, to add 10 to it, or all of them not to die. See `help hero points`.

Acting in an encounter - actions, Strikes and spells - is in `help encounter actions`.
