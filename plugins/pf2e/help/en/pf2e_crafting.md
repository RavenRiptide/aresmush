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
`formula/buy <category>=<item>`: Buys a common formula, and takes its price out of your money. In PF2e, a formula's price depends on the item's level, not on the item's own price.
%t **Note:** You can't buy uncommon or rarer formulas.

Your class and some feats also give you formulas to pick. See `help cg_formulas`.

## Alchemy preparations

An alchemist's infused reagents make a day's worth of items. Put the items you want to craft on your list, and your next rest makes them. Those items last until your next daily preparations after that. You join an encounter rested, so the game makes the items on your list when you join.

`alchemy [<character>]`: Shows your reagents and preparations, or another character's. In an encounter, it shows how many batches you have left today and what you've made with them. Outside an encounter, it shows what a rest will give you and how many batches your list leaves over.
`alchemy/prepare <item>[/<how many>]`: Adds an item to your list. The item must have the alchemical trait, must not be higher level than you, and must be an item whose formula you know.
%t **Note:** A potion you chose with Improbable Elixirs counts as alchemical.
`alchemy/clear [<item>]`: Removes an item from your list, or empties the whole list.
`encounter/alchemy <item>`: Performs Quick Alchemy in an encounter, using one batch of reagents to make one item that lasts until your next turn.

Each batch of reagents makes two items during a rest, or one item with Quick Alchemy. Batches a rest doesn't use are left over for Quick Alchemy.
