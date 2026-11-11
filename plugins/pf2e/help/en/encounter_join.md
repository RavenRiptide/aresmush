---
toc: Pathfinder Second Edition - Encounters
summary: Joining an encounter, and seeing it, your sheet, and other combatants.
aliases:
- e_join
- e_view
- e_sheet
- e_csheet
- encounter_player
- pf2e_encounter_player
---
# Pathfinder 2E Encounters - Joining

`encounter/join [<encounter ID>=][<stat>]`: Joins an encounter and rolls your initiative on Perception, or on the statistic the GM asks for (`<stat>`): a skill, or an attribute's three-letter abbreviation. You can type just the first few letters of a skill.
%t **Examples**:
%t `encounter/join`
%t `encounter/join 12=stealth`
%t `encounter/join dex`
%t **Note:** You fight with what you carried in. Joining copies your gear, the items you have equipped and invested, and your money into the encounter. See `help e/gear` for more information.
`encounter/view [<encounter ID>]`: Shows the encounter in turn order: each combatant's ID, initiative, hit points, defenses, conditions, and effects, and a link to the encounter's web page. (Alias: `tinit <encounter ID>`)
%t **Note:** Only the GM sees a creature's stats. Everyone else sees how hurt the creature looks: Unhurt, Bloodied, Near Death, or Dead.
`encounter/sheet[ <#id or name>][/<section>]`: Shows your sheet, or another combatant's, as it stands in the encounter, with hit points, conditions, and effects. Add `/<section>` to show one section; the sections are the same as `sheet`'s.
`encounter/csheet[ <#id or name>]`: Shows your combat sheet, or another combatant's: the Strikes you can make with what you carry, with attack bonuses and damage, and your AC, saves, and conditions.
`encounter/creature <#id>`: Shows a creature's name and conditions.
`hero`: Shows your Hero Points. For more information, see `help hero points` or [read it on the web](/help/pf2e_hero_points).
