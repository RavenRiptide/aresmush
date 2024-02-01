---
toc: Pathfinder Second Edition
summary: Inventory - Buying and Selling Equipment
aliases:
- browse
- buy
- sell
---

# Pathfinder 2E Inventory - Buying and Selling Equipment

Emblem of Ea's inventory system allows characters to buy and sell items from and to the game. There are six categories of items:

* Weapons (weapons) - Weapons, including any held item that can be used like a wand or a stave.
* Armor (armor) - All types of armor.
* Shields (shields) - All types of shields. Note that a boss or spikes for a shield are considered a weapon linked to the shield.
* Magic Items (magicitem) - Wearable magical items such as boots, cloaks, rings, etc. If it can be invested, it's in this category.
* Bags and Containers (bags) - Backpacks, bags of holding, belt pouches, and similar.
* Consumables (consumables) - Potions, oils, alchemical items, etc.
* Gear (gear) - Adventuring gear such as grappling hooks, ladders, etc.

## Commands

`browse <category>`: Browses items purchasable in <category>.

**You need to be approved for play to buy or sell gear.** This is to prevent money issues associated to app rejection and rework requirements. You will be able to buy gear once you are approved for play.

`buy <category> = <name>[/<quantity>]`: Buys item in <category> named <name>. Quantity is optional, default is 1.
`sell <category> = <name>[/quantity>]`: Sells item in <category> named <name> for half of its purchase price. Quantity is optional, default is 1.

Weapons, armor, magic items, and shields will only permit you to buy or sell one at a time, and you must specify items in these categories by number, not by name.

A few things to be aware of:
 * Items of a higher level than the character cannot be bought or sold through the vendor. Please put in a request for such purchases.
 * If encumbrance tracking is turned on, the vendor will not permit you to purchase an item that you cannot carry (i.e. that would put you over your max Bulk capacity. Refer to the PRD for an explanation of Bulk.)
 * The item list supports partial matching, but if there are multiple items with that name, it will try to match the exact one you specified, so it may help to cut and paste names.
