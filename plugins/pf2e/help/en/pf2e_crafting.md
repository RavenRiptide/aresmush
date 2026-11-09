---
toc: Pathfinder Second Edition
summary: Formulas and alchemy preparations.
aliases:
- crafting
- craft
- formulas
- formula
- alchemy
---

# Formulas and Alchemy

Formulas are formalized instructions for making items. For full rules on formulas and crafting, see [Crafting](/wiki/mechanics:crafting).

## Commands

`formulas [<character>]`: Lists the formulas you know, or the formulas another character knows.
`formula/buy <category>=<item>`: Buys a formula, and takes its price out of your money. In PF2e, a formula's price depends on the item's level, not on the item's own price.
%t **Note:** You need to be approved for play to buy formulas.
%t **Note:** You can buy the formula for an uncommon or rare item with this command only if a feat or class you have names the item. For any other uncommon or rare formula, put in a request to buy it with RPP and money. See `help vendor`.

Your class and some feats also give you formulas to pick. See `help cg_formulas`.

## Alchemy

Each rest makes the items on your alchemy list and gives you your versatile vials, which last until your next rest. You join an encounter rested, so you start it with both.

`alchemy [<character>]`: Shows your vials and your list, or another character's. In an encounter, it also shows how many vials you have left and what you've made today.
`alchemy/prepare <item>[/<how many>]`: Adds an item to your list. The item must be an alchemical consumable, must not be higher level than you, and must be an item whose formula you know.
%t **Note:** A potion you chose with Improbable Elixirs counts as an alchemical consumable.
`alchemy/clear [<item>]`: Removes an item from your list, or empties the whole list.
`encounter/alchemy <item>`: Performs Quick Alchemy in an encounter, spending one versatile vial to make one item that lasts until your next turn.
`encounter/alchemy <item>, <item>`: Makes two items with one Quick Alchemy, spending a vial for each. You need Double Brew.
`encounter/alchemy/vial`: Makes a quick vial, which spends no vial and lasts until the end of your turn. You can throw a quick vial, but you can't spend it on Quick Alchemy.
%t **Note:** Quick Alchemy needs an Alchemist's Toolkit that you're carrying and haven't put in a bag.

To throw a versatile vial, Strike with it like any other bomb (see `help encounter_actions`). To get vials back by gathering reagents, ask the GM, who uses `encounter/gather` (see `help rest`).

Some research fields add commands:

`sheet/option bomber-field-vials=<cold, electricity, or fire>`: **Bomber.** Sets the damage type your vials deal. Use `sheet/option bomber-field-vials=off` to go back to acid.
`prepare/vialmaterial <adamantine, cold iron, or dawnsilver>`: **Bomber, 11th level.** Sets the material of the day's vials (see `help daily_choices`).
`encounter/poison <weapon>=versatile vial`: **Toxicologist.** Applies a vial to a weapon as an injury poison (see `help encounter_gear`).
`encounter/use consumables=<vial>[/<who>]`: **Chirurgeon.** Drinks a versatile vial to heal, or throws it to heal someone else.
`encounter/use consumables=<vial>`: **Mutagenist.** Drinks a versatile vial to suppress the drawbacks of your newest mutagen.
`encounter/mutagenreroll`: **Mutagenist, 5th level.** Ends your mutagen to reroll your last check, if it was a Fortitude save.
`encounter/persistentmutagen`: **Persistent Mutagen.** Makes the mutagen you drank most recently last until your next rest. You can use it once a day.
`encounter/spray <who>`: **Toxicologist, 13th level.** When a creature fails its first saving throw against a poison you applied, sprays it onto the creature you name. You have until the end of your turn.
