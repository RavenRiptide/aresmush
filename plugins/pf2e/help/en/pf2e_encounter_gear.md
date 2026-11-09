---
toc: Pathfinder Second Edition
summary: Using the items you carry in an encounter.
aliases:
- encounter_gear
- encounter gear
---
# Pathfinder 2E Encounters - Using Gear

When you join an encounter, the game copies what you carry into it: your gear, what you wear, wield, and have invested, and your money. Everything in the encounter uses that copy, including your encounter sheet, your Strikes and AC, and the items you use. Anything you buy, sell, or equip outside the encounter after you join isn't part of it. The items you brought in belong to the encounter until it ends, so you can't use or sell them on your own sheet in the meantime; otherwise, you'd have them twice.

`encounter/gear [<who>]`: Lists what you, or another combatant, are carrying in the encounter here.
`encounter/use <category>=<number>[/<use>]`: Uses an item you're carrying in the encounter, such as drinking a potion or spending a charge.
`encounter/use consumables=<number>[/<who>]`: Drinks a potion, elixir, or mutagen, or gives it to someone else in the fight. A healing potion heals by its dice (vitality healing works on the living and does nothing for the undead), and an elixir or mutagen applies its effect to whoever takes it.
`encounter/equip <category>=<number>`: Draws a weapon, puts on armor, or straps on a shield.
`encounter/unequip <category>=<number>`: Puts away a weapon, armor, or shield.
`encounter/poison <weapon>=<poison>`: Applies an injury poison you're carrying to a weapon you're wielding. The poison stays on the weapon until your next Strike with it that hits or critically misses.
`encounter/loot <who>=<consumable>[/<quantity>]`: Gives someone a consumable from the catalog for this encounter.
%t **Note:** Only staff, and trusted GMs named by staff, can hand out items. Being an encounter's GM isn't enough on its own.

## Scrolls, wands, and staves

`encounter/use consumables=<number>[/<who>[, <who>]][/<word>]`: Casts the spell on a scroll at the scroll's rank, then uses the scroll up. Name your targets after the number, and any words the spell takes after them, as you would with `encounter/cast`.
`encounter/use magicitem=<number>[/<who>[, <who>]][/<word>]`: Casts the spell in a wand. You can cast from each wand once a day.
`encounter/overcharge magicitem=<number>[/<who>[, <who>]][/<word>]`: Casts from a wand you've already cast from today. Then a DC 10 flat check is rolled: on a success the wand breaks, and on a failure it's destroyed. Overcharging a wand twice in one day destroys it without casting anything.
`encounter/repair <who>=<number>`: **GM.** Repairs someone's broken wand.
`encounter/use magicitem=<number>[/<who>[, <who>]][/<spell>][/<word>]`: **Egalrin Feather Fan.** Casts a spell in your fan, or one of your innate cantrips, with Wave Fan. Name the spell after the targets, or leave it out if your fan has only one spell. A spell with no targets still needs the slash for them, such as `encounter/use magicitem=2//gust of wind`. A cantrip doesn't use up any of the day's activations.
`encounter/use weapons=<number>[/<who>[, <who>]][/<spell>][/<word>]`: **Staff.** Casts a spell from the staff you prepared today, which you must have equipped. Name the spell after the targets, as for the feather fan. It costs charges equal to the spell's rank, and a cantrip costs none.
`encounter/use weapons=<number>[/<who>[, <who>]]/<spell>/rank <number>`: **Staff, spontaneous caster.** Casts a spell from the staff for 1 charge and one of your spell slots, of the spell's rank or higher.
%t **Note:** The spell must be on a spell list you cast from. You cast it with your own spell attack and spell DC.
%t **Note:** To prepare a staff, see `help prepare`.
%t **Note:** Outside an encounter, `use consumables=<number>`, `use magicitem=<number>`, or `use weapons=<number>[/<spell>]` tells the room you cast the spell. A scroll is used up, but a wand's daily casting and a staff's charges aren't counted.

A battle form absorbs your gear, so you can't use, equip, or unequip anything until the form ends. The constant abilities of your gear still work.

`encounter/gear` shows item numbers. When the encounter ends, the consumables you used from your own inventory are removed from it. The rest of the copy, including your money and anything the encounter gave you, stays with the encounter. When one encounter continues from another, the copy carries over.

For using ammunition, see "Ammunition and reloading" in `help encounter_actions` or [read it on the web](/help/pf2e_encounter_actions). For buying items, see `help buy` or [read it on the web](/help/vendor).
