---
toc: Pathfinder Second Edition - Admin
summary: Admin commands for other inventory and gear functions.
aliases:
- pf2estaff_inv
- pf2eadmin_gear
- pf2eadmin_inventory
---

# Pathfinder 2E -- Admin Commands for Inventory and Gear

Staff can make some modifications to characters' inventories.

### Etching runes
**Commands**:
`etch/potency <character>=<category>/<item number>/<potency level>`
`etch/striking <character>=weapons/<item number>/<striking level>`
`etch/resilient <character>=armor/<item number>/<resilient level>`
`etch/property <character>=<category>/<item number>/<rune name>`
`etch/reinforcing <character>=shields/<item number>/<reinforcing grade>`

**Key**:
`<character>`: The character's name.
`<category>`: `weapons` or `armor`. Case-sensitive.
`<item number>`: The number of the item in the character's inventory.
`<potency level>`: The level of the Potency rune, as a number. Acceptable values: 0-3
`<striking level>`: The level of the Striking rune, as a number. Acceptable values: 0-3
`<resilient level>`: The level of the Resilient rune, as a number. Acceptable values: 0-3
`<reinforcing grade>`: The grade of the Reinforcing rune, as a number. Acceptable values: 0 (none), 1 (minor), 2 (lesser), 3 (moderate), 4 (greater), 5 (major), 6 (supreme)
`<rune name>`: The name of a property rune, as `browse runes` lists it, such as `Flaming`, `Ghost Touch`, or `Keen`. The game refuses rune names that aren't in the database.

To remove a property rune from an item, repeat the command that added the rune. This works even for a rune the game no longer has.

A property rune does what its catalog entry says. For example, a *flaming* rune adds 1d6 fire damage to the weapon, plus 1d10 persistent fire damage on a critical hit, and a *keen* rune makes a natural 19 a critical hit. An item can have as many property runes as its Potency rune's value, so if a rune won't fit, etch a higher Potency rune on the item first.
%t **Note:** Armor runes go on armor, and weapon runes go on weapons. Many runes go only on certain items, such as *returning* on a thrown weapon or *shadow* on light or medium armor that isn't metal. The game refuses a rune that doesn't fit, the same way the vendor does.

Etching a stronger version of a rune the item already has replaces the weaker one, such as *greater flaming* over *flaming*, and doesn't use another property rune slot. The game refuses a weaker or equal version, and it refuses a *holy* rune on an item with an *unholy* rune, or the reverse.

An *energy-resistant* rune needs a damage type: acid, cold, electricity, or fire. Add the type in parentheses, such as `etch/property <character>=armor/<item number>/Energy Resistant (Fire)`. An item can have more than one, each resisting a different damage type.

A Reinforcing rune raises a shield's Hardness and Hit Points, up to the maximum for its grade, and the shield's Broken Threshold rises with its Hit Points. The shield shows its new Hardness and Hit Points wherever they appear. To remove the rune, set its grade to 0.