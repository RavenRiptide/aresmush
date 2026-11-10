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
%t **Note:** You can't sell an item a feat or class feature gave you, such as an egalrin feather fan.

## Scrolls and wands

`browse scroll`, `browse wand`: Shows what a scroll or wand costs at each spell rank.
`buy scroll=<spell>[/<quantity>]`: Buys a scroll of a spell, at the spell's own rank.
`buy wand=<spell>`: Buys a wand of a spell, at the spell's own rank.
`buy/rank<number> scroll=<spell>`, `buy/rank<number> wand=<spell>`: Buys a scroll or wand with the spell heightened to that rank, such as `buy/rank5 scroll=Fireball`.
`buy wand=<spell> (widening)`, `buy wand=<spell> (continuation)`: Buys a wand of widening or a wand of continuation containing the spell. Add `/rank<number>` after `buy` to heighten the spell. `browse magicitem` lists their prices by rank.
%t **Note:** A wand of widening contains a spell that takes 1 or 2 actions, has no duration, and has a burst of 10 feet or more, a cone, or a line. A wand of continuation contains a spell that takes 1 or 2 actions and lasts from 10 minutes to 1 hour.
%t **Note:** A scroll or wand can contain a common spell that isn't a cantrip, focus spell, or ritual. To buy a scroll or wand of an uncommon or rare spell, put in a request with RPP and money, even if the spell is unlocked for you.
%t **Note:** Find spells with `spell/search`. To cast from a scroll or wand, see `help encounter_gear`.

## Runes

`browse rune`: Lists the fundamental runes at every grade, and the property runes you can buy, with any items they're limited to.
`buy/rune <category>/<item number>=<rune>`: Buys a rune and etches it onto one of your weapons, armor, or shields, such as `buy/rune weapons/0=+1 Weapon Potency`, `buy/rune weapons/0=Flaming`, or `buy/rune shields/0=Minor Reinforcing`. Find the item number with `gear`.
%t **Note:** Raising a rune the item already has, such as +1 to +2 potency or *flaming* to *greater flaming*, costs the difference between the two prices.
%t **Note:** An *energy-resistant* rune needs a damage type: acid, cold, electricity, or fire. Add it in parentheses, such as `buy/rune armor/0=Energy Resistant (Fire)`.
%t **Note:** The vendor refuses a rune that doesn't fit the item, and says why. A specific magic weapon or armor, such as a *searing blade*, can't gain property runes, but you can raise its fundamental runes.
%t **Note:** A rune's price is added to the item's, so selling the item returns half of what you paid for its runes.
%t **Note:** To move a rune to another item, put in a request. Staff etch it and handle the money. To buy an uncommon or rare rune, or one above your level, put in a request with RPP and money.

Weapons, armor, magic items, and shields will only permit you to buy or sell one at a time, and you must specify items in these categories by number, not by name.

A few things to be aware of:
 * Items of a higher level than the character cannot be bought or sold through the vendor. Please put in a request for such purchases.
 * The vendor sells common items to everyone. It sells you an uncommon or rare item only if a feat or class you have names it, such as Khazadi Weapon Familiarity or a cleric's favored weapon. `browse` lists only the items you can buy. To get any other uncommon or rare item, put in a request to buy its formula with RPP and money, then put in a request to have the item crafted for you or another character.
 * If encumbrance tracking is turned on, the vendor sells you an item even if it's too heavy for you, and warns you if the purchase leaves you encumbered. To lighten your load, sell items, or stow them in a backpack or extradimensional container. See `help gear`.
 * Ordinary ammunition (arrows, bolts, and sling bullets) isn't sold or tracked, because ranged weapons always have it. Cold iron and silver ammunition is sold by the piece under consumables. To fire it, name the material when you attack; see "Ammunition and reloading" in `help encounter actions` or [read it on the web](/help/pf2e_encounter_actions).
 * The item list supports partial matching, but if there are multiple items with that name, it will try to match the exact one you specified, so it may help to cut and paste names.
