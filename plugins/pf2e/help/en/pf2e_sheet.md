---
toc: Pathfinder Second Edition
summary: Pathfinder 2E sheets and sheet sections.
aliases:
- sheet
- sheet_history
- level_history
---

# Pathfinder 2E Sheets

`sheet`: Views your own sheet.
`sheet <name>`: Views someone else's sheet.
`sheet/<section>`: Views <section> of your sheet. See Valid Sections below.
`sheet/<section> <name>`: Views <section> of <name>'s sheet.
`sheet/history`: Lists what you chose or were given at each level, such as feats, attribute boosts, skill increases, languages, spells, and formulas.
`sheet/history <level>`: Lists what you chose or were given at one level, such as `sheet/history 5`.
`sheet/history <first>-<last>`: Lists what you chose or were given at a range of levels, such as `sheet/history 3-7`.
`sheet/history <name>` and `sheet/history <name>=<first>-<last>`: Lists the same for someone else.
`csheet` and `csheet <name>`: Alias for `sheet/combat`.
%t **Note:** The combat sheet is available once a character is approved. During chargen, use `sheet` instead.
`sheet/breakdown <stat>`: Shows the math behind a stat on your sheet: its base value, and every bonus and penalty applied to it. `<stat>` can be `hp`, `ac`, `speed`, `perception`, a save (`fortitude`, `reflex`, or `will`), `class dc`, or a skill or lore by name.
%t **Note:** A modifier that the stacking rules don't count is listed and marked, so you can see when a new item changes nothing because you already have a better bonus of the same type. Bonuses that only apply while you're doing something specific are listed separately, with the circumstance each one needs; see "Bonuses for specific actions" in `help roll` for how to claim them.
`sheet/breakdown <stat>=<player>`: Shows the same for someone else's sheet.
`sheet/option` (or `sheet/options`): Lists the circumstances your gear and feats offer, and which ones are on.
%t **Note:** Some items only work while one of their features is active. For example, a Clandestine Cloak hides you while its magic is running, but makes you harder to talk to. These circumstances are on by default, so an item you're wearing does what it says.
`sheet/option <name>`: Turns a circumstance off, or back on.
`sheet/option <name>=off` and `sheet/option <name>=on`: Turns a circumstance off or on, instead of switching it to the opposite setting.
`sheet/option <name>=default`: Resets a circumstance to the setting of the item or feat that offers it.
`sheet/option <name>=<value>`: Sets a circumstance that's a choice rather than an on/off switch, such as a gem twisted to frost rather than flame, or a signet set to Fortitude rather than Reflex. `sheet/option` lists the values each circumstance can be set to.

## Valid Sections

The following sections are valid switches for this command.

* **info** or **top**: Shows basic character information.
* **attributes**: Shows attribute modifiers. (P) marks a partial boost, which is halfway to the next modifier.
* **combat**: Shows derived stats, AC, to-hit, attacks and their bonuses, and lists feats that may apply in combat.
* **features**: Shows the features your class and archetypes gave you, by the level you gained each one. The full sheet shows only the highest step of a feature that improves as you level, such as Master Spellcaster in place of Expert Spellcaster.
* **feats**: Shows your feats by the level you took each one, and what type of feat each one is.
* **history**: Shows what you chose or were given at each level, such as feats, attribute boosts, and skill increases. Add a level or a range of levels to show only those, such as `sheet/history 3-7`.
* **languages**: Shows known languages.
* **magic**: Shows focus spells and spells per-day / remaining for spellcasting classes.
* **skills**: Shows skills and their modifiers.
