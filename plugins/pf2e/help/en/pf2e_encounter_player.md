---
toc: Pathfinder Second Edition
summary: Encounter commands for everyone taking part.
aliases:
- encounter_player
- encounter player
---
# Pathfinder 2E Encounters - Taking Part

`encounter/view` shows each combatant's ID: `#1`, `#2`, and so on. See `help encounter` or [read it on the web](/help/pf2e_combat) for how IDs work.

**You fight with what you carried in your inventory.** When you join an encounter, the game copies your gear, the items you have equipped and invested, and your money totals into the encounter. Your Strikes, your AC, and every item you use in the encounter come from that copy. Anything you buy, sell, or equip on your own sheet after you join isn't part of the encounter. Until the encounter ends, you can't use or sell the items you brought into it from your own sheet. `encounter/gear` lists what you're carrying in the encounter, and `encounter/equip` draws a weapon or puts on armor from it. See `help encounter_gear` or [read it on the web](/help/pf2e_encounter_gear) for details.

`encounter/join [<encounter ID>=][<stat>]`: Joins an encounter and rolls your initiative on the statistic the GM chose (Perception by default).
%t **Note:** If the GM asks you to roll a different statistic, name it: Perception, a skill, or an ability, such as `encounter/join 12=stealth` or `encounter/join dex`. Capitalization doesn't matter, and you can type just the first few letters of a skill, or an ability's three-letter abbreviation.
`encounter/sheet[ <#id or name>][/<section>]`: Shows your sheet, or another combatant's, as it stands in this encounter, including the Hit Points, conditions, and effects that `sheet` doesn't show. Add `/<section>` to show one section; the sections are the same as `sheet`'s.
`encounter/csheet[ <#id or name>]`: Shows your combat sheet, or another combatant's, as it stands in this encounter: the Strikes you can make with what you carry in the encounter, with their attack bonuses and damage, and your AC, saves, and conditions. `csheet` shows the same sheet outside the encounter.
%t **Note:** While you're in a stance that limits your Strikes, such as Stumbling Stance, the sheet lists only the stance's attack.
`encounter/view [<encounter ID>]`: Shows the encounter's initiative table: each combatant's ID, initiative, conditions, cover, and concealment. It also gives a link to the encounter's web page, which you can also open from the scene's Play menu on the web. (Alias: `tinit <encounter ID>`)
`encounter/creature <#id>`: Shows a creature's name and conditions.
%t **Note:** Only the encounter's GM can see a creature's stat block and hit points.
`hero`: Shows your Hero Points in the scene. `hero/reroll` rerolls your last check, `hero/boost` adds 10 to it, and `hero/survive` spends all your Hero Points to avoid dying. See `help hero points` or [read it on the web](/help/pf2e_hero_points).

For actions, Strikes, and spells, see `help encounter actions` or [read it on the web](/help/pf2e_encounter_actions).
