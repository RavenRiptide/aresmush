---
toc: Pathfinder Second Edition
summary: Pathfinder 2E sheets and sheet sections.
aliases:
- sheet
---

# Pathfinder 2E Sheets

`sheet`: Views your own sheet.
`sheet <name>`: Views someone else's sheet. Depending on your game configuration and on the other player's setting, this may or may not be permitted.
`sheet/<section>`: Views <section> of your sheet. See Valid Sections below.
`sheet/<section> <name>`: Views <section> of <name>'s sheet. Depending on your game configuration and on the other player's setting, this may or may not be permitted.
`csheet` and `csheet <name>`: Alias for `sheet/combat`.
%t **Note:** The combat sheet is available once a character is approved. During chargen, use `sheet` instead.
`sheet/why <figure>`: Shows the math behind one number on your sheet: its base value, and every bonus and penalty applied to it. `<figure>` can be `hp`, `ac`, `speed`, `perception`, a save (`fortitude`, `reflex`, or `will`), `class dc`, or a skill or lore by name.
%t **Note:** A modifier that the stacking rules don't count is listed and marked, so you can see when a new item changes nothing because you already have a better bonus of the same type. Bonuses that only apply while you're doing something specific are listed separately, with the circumstance each one needs; see "Bonuses for specific actions" in `help roll` for how to claim them.
`sheet/why <figure>=<name>`: Shows the same for someone else's sheet, if you're allowed to view their sheet with `sheet <name>`.
`sheet/option` (or `sheet/options`): Lists the circumstances your gear and feats offer, and which ones are on.
%t **Note:** Some items only work while one of their features is active. For example, a Clandestine Cloak hides you while its magic is running, but makes you harder to talk to. These circumstances are on by default, so an item you're wearing does what it says.
`sheet/option <name>`: Turns a circumstance off, or back on.
`sheet/option <name>=off` and `sheet/option <name>=on`: Turns a circumstance off or on, instead of switching it to the opposite setting.
`sheet/option <name>=default`: Resets a circumstance to the setting of the item or feat that offers it.
`sheet/option <name>=<value>`: Sets a circumstance that's a choice rather than an on/off switch, such as a gem twisted to frost rather than flame, or a signet set to Fortitude rather than Reflex. `sheet/option` lists the values each circumstance can be set to.
`sheet/show`: Shows what permissions you have granted to your sheet.
`sheet/show <name>[=<section>]`: Shows optional <section> of your sheet to <name>. Depending on your game configuration, this command may have no effect.
`sheet/unshow <name>`: Ends showing of all sections of your sheet to <name>. Depending on your game configuration, this command may have no effect.

## Valid Sections

The following sections are valid switches for this command.

* **info** or **top**: Shows basic character information.
* **ability**: Shows ability scores and modifiers.
* **combat**: Shows derived stats, AC, to-hit, attacks and their bonuses, and lists feats that may apply in combat.
* **features**: Shows class-specific features gained from your class and dedication archetypes.
* **feats**: Shows general and skill feats.
* **languages**: Shows known languages.
* **magic**: Shows focus spells and spells per-day / remaining for spellcasting classes.
* **skills**: Shows skills and their modifiers.
