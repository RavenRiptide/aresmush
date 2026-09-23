---
toc: Pathfinder Second Edition
summary: Formulas, and an alchemist's preparations.
aliases:
- crafting
- craft
- formulas
- formula
- alchemy
---

# Formulas and Crafting on Emblem of Ea

A formula is knowing how something is made. It is yours, not an encounter's: what you know is the same
inside a fight and out of one, and nothing in an encounter gives you a formula or takes one away.

## Formulas

`formulas [<character>]`: The formulas a character knows, and their reagents for the day if they have any.
`formula/buy <category>=<item>`: Buys a common formula. PF2e prices a formula by the level of the item it makes, not by that item's own price, and the money comes out of your purse.
`formula/reverse <category>=<item>`: Works a formula out from an item you carry: a Crafting check against what the item's level makes it. On a success you learn it and pay the formula's price in materials; on a critical failure half of that is wasted and you learn nothing.

An uncommon or rarer formula is not simply bought; staff give those.

## For staff

`formulas/add <character>=<category>/<item>`: Gives a character a formula.
`formulas/remove <character>=<category>/<item>`: Takes one back.

## An alchemist's preparations

An alchemist's infused reagents make a day's items. Say what to make, and your next rest makes it; what it
makes lasts until your next preparations after that.

`alchemy [<character>]`: Your preparations, and what your reagents allow: how many batches you have, how many items they make, and how many batches are left today.
`alchemy/prepare <item>[/<how many>]`: Puts an item on the list. It must be alchemical, no higher level than you are, and one whose formula you know.
`alchemy/clear [<item>]`: Takes one off the list, or empties it.
`+e/alchemy <item>`: Quick Alchemy in an encounter: a batch of reagents for one item, to hand until your next turn.

Each batch of reagents makes two items at a rest, or one on the spot. What a rest does not spend is left
for Quick Alchemy.
