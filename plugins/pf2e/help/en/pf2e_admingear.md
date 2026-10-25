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

**Key**:
`<character>`: The character's name.
`<category>`: `weapons` or `armor`. Case-sensitive.
`<item number>`: The number of the item in the character's inventory.
`<potency level>`: The level of the Potency rune, as a number. Acceptable values: 0-3
`<striking level>`: The level of the Striking rune, as a number. Acceptable values: 0-3
`<resilient level>`: The level of the Resilient rune, as a number. Acceptable values: 0-3
`<rune name>`: The name of a property rune, as `browse runes` lists it, such as `Flaming`, `Ghost Touch`, or `Keen`. The game refuses rune names that aren't in the database.

To remove a property rune from an item, repeat the command that added the rune.

A property rune does what its catalog entry says. For example, a *flaming* rune adds 1d6 fire damage to the weapon, plus 1d10 persistent fire damage on a critical hit, and a *keen* rune makes a natural 19 a critical hit. An item can hold as many property runes as its Potency rune's value, so if a rune won't fit, etch a higher Potency rune on the item first.
%t **Note:** Armor runes go on armor, and weapon runes go on weapons. `browse runes` shows which is which.