---
toc: Pathfinder Second Edition
summary: Inventory - Buying and Selling Equipment
aliases:
- browse
- buy
- sell
---

# Pathfinder 2E Inventory - Buying and Selling Equipment

Emblem of Ea's inventory system allows characters to buy and sell items from and to the game. There are seven categories of items:

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
`buy magicitem = <name>/<deity>`: Buys a magic item made for one deity, such as a Helm of Zeal, made for the deity you specify (`<deity>`). The item's bonus goes to that deity's Divine Skill, whatever your own deity is.
`sell <category> = <name>[/quantity>]`: Sells item in <category> named <name> for half of its purchase price. Quantity is optional, default is 1.
%t **Note:** You can shorten a category to its first few letters, such as `buy magic=Ring of Lies` or `browse cons`.
%t **Note:** You can't sell an item a feat or class feature gave you, such as an egalrin feather fan.

## Scrolls and wands

`browse scroll`, `browse wand`: Shows what a scroll or wand costs at each spell rank.
`buy scroll=<spell>[/<quantity>]`: Buys a scroll of a spell, at the spell's own rank.
`buy wand=<spell>`: Buys a wand of a spell, at the spell's own rank.
`buy/rank<number> scroll=<spell>`, `buy/rank<number> wand=<spell>`: Buys a scroll or wand with the spell heightened to that rank, such as `buy/rank5 scroll=Fireball`.
`buy wand=<spell> (widening)`, `buy wand=<spell> (continuation)`: Buys a wand of widening or a wand of continuation containing the spell. Add `/rank<number>` after `buy` to heighten the spell. `browse magicitem` lists their prices by rank.
%t **Note:** A wand of widening contains a spell that takes 1 or 2 actions, has no duration, and has a burst of 10 feet or more, a cone, or a line. A wand of continuation contains a spell that takes 1 or 2 actions and lasts from 10 minutes to 1 hour.
`buy magicitem=<wand>`: Buys a wand that contains its own spell, such as `buy magicitem=Wand of Smoldering Fireballs (3rd-Rank Spell)`. `browse magicitem` lists them.
%t **Note:** When you cast from one in an encounter, the room is told what the wand adds to its spell. The game applies what it can: smoldering fireballs' persistent fire and crackling lightning's off-guard on a failed save, the spider's poison when its web is cast, and overflowing life's healing at the start of your next turn. A wand of slaughter tells the room when its spell slays a living target, and the GM deals the burst's damage with `damage`. The GM applies the rest, such as hopeless night's frightened or the snowfields' difficult terrain.
%t **Note:** After you cast from a wand of shardstorm, the game reminds you at the start of each of your turns for the next minute. Direct that turn's shards with `encounter/use` on the wand, for no action and without using the wand's day again. Using the wand any other time while the storm lasts ends it.
%t **Note:** A scroll or wand can contain a common spell that isn't a cantrip, focus spell, or ritual. To buy a scroll or wand of an uncommon or rare spell, put in a request with RPP and money, even if the spell is unlocked for you.
%t **Note:** Find spells with `spell/search`. To cast from a scroll or wand, see `help e/gear`.

## Runes

`browse rune`: Lists the fundamental runes at every grade, and the property runes you can buy, with any items they're limited to.
`buy/rune <category>/<item number>=<rune>`: Buys a rune and etches it onto one of your weapons, armor, or shields, such as `buy/rune weapons/0=+1 Weapon Potency`, `buy/rune weapons/0=Flaming`, or `buy/rune shields/0=Minor Reinforcing`. Find the item number with `gear`.
%t **Note:** Raising a rune the item already has, such as +1 to +2 potency or *flaming* to *greater flaming*, costs the difference between the two prices.
%t **Note:** An *energy-resistant* rune needs a damage type: acid, cold, electricity, or fire. Add it in parentheses, such as `buy/rune armor/0=Energy Resistant (Fire)`.
%t **Note:** The vendor refuses a rune that doesn't fit the item, and says why. A specific magic weapon or armor, such as a *searing blade*, can't gain property runes, but you can raise its fundamental runes.
%t **Note:** A rune's price is added to the item's, so selling the item returns half of what you paid for its runes.
%t **Note:** To move a rune to another item, put in a request. Staff etch it and handle the money. To buy an uncommon or rare rune, or one above your level, put in a request with RPP and money.
%t **Note:** An orichalcum weapon or armor can have one more property rune than its potency rune allows, and a *quickstrike* rune costs half as much on an orichalcum weapon.

## Precious materials

`browse material`: Lists the precious materials, with the level and price of each grade for weapons, armor, shields, bucklers, and tower shields.
`buy/material <category> = <item>/<material>/<grade>`: Buys a weapon, armor, or shield made of a precious material, at the grade you specify (low, standard, or high), such as `buy/material weapons=Longsword/cold iron/low` or `buy/material shields=Steel Shield/adamantine/standard`.
%t **Note:** An uncommon material (adamantine, dawnsilver, or duskwood) costs 2 RPP as well as its price, and a rare material (orichalcum) costs 4 RPP. The item itself follows the usual rules: you can buy an uncommon or rare weapon, armor, or shield only if a feat or class you have names it.
%t **Note:** A metal weapon or armor can be made of any material except duskwood, and a wooden weapon only of duskwood. Leather and cloth armor, slings, saps, bolas, and whips can't be made of a precious material. A wooden shield or tower shield can only be made of duskwood, a steel shield of any material except duskwood, and a buckler of any material.
%t **Note:** You choose an item's material when you buy it, and you can't change it later. `item/view` shows the material and grade.
%t **Note:** The game applies what each material does:
%t - A weapon's material counts against creatures' weaknesses and resistances. Dawnsilver counts as silver.
%t - An adamantine weapon halves a creature's Hardness, unless that Hardness is above the weapon's own.
%t - A lighter material reduces the item's Bulk.
%t - Dawnsilver and duskwood armor have a lower Strength requirement and Speed penalty.
%t - A shield's Hardness and Hit Points come from its material.
%t - Orichalcum armor gives a +1 bonus to initiative.
%t - A creature weak to cold iron or silver that critically fails an unarmed attack against someone wearing that armor is sickened 1.
%t - An orichalcum shield that would be destroyed is left with 1 HP and broken instead, once until the GM rests you.
%t - A shield boss or shield spikes attached with `gear/attach` counts as a weapon of the shield's material.
%t **Note:** One effect you apply by hand: a creature weak to cold iron or silver is sickened 1 while it wears that armor.

Weapons, armor, magic items, and shields will only permit you to buy or sell one at a time, and you must specify items in these categories by number, not by name.

A few things to be aware of:
 * Items of a higher level than the character cannot be bought or sold through the vendor. Please put in a request for such purchases.
 * The vendor sells common items to everyone. It sells you an uncommon or rare item only if a feat or class you have names it, such as Khazadi Weapon Familiarity or a cleric's favored weapon. `browse` lists only the items you can buy. To get any other uncommon or rare item, put in a request to buy its formula with RPP and money, then put in a request to have the item crafted for you or another character.
 * If encumbrance tracking is turned on, the vendor sells you an item even if it's too heavy for you, and warns you if the purchase leaves you encumbered. To lighten your load, sell items, or stow them in a backpack or extradimensional container. See `help gear`.
 * Ordinary ammunition (arrows, bolts, and sling bullets) isn't sold or tracked. Cold iron and silver ammunition is sold by the piece under consumables. To fire it, specify the material when you attack; see `help e/strike` or [read it on the web](/help/encounter_strike).
 * The item list supports partial matching, but if there are multiple items with that name, it will try to match the exact one you specified, so it may help to cut and paste names.
