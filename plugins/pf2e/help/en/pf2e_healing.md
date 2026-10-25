---
toc: Pathfinder Second Edition
summary: Healing and damage-related commands.
aliases:
- damage
- heal
- condition
---
# Pathfinder 2E - Damage and Healing

Damage, healing, and conditions only apply inside an encounter, to a character's encounter copy. These commands never change a character's own sheet: `sheet` shows a character as they normally are, and `encounter/sheet` shows them in the encounter here, with everything the encounter has done to them. Outside an encounter, these commands have no one to affect.

You can target a combatant by their ID from `encounter/view`, such as `damage #3=5 fire`.

## Anyone in the encounter

`heal <list>=<amount>[ <action>]`: Heals each combatant in `<list>` for `<amount>`, up to their maximum Hit Points. Name the action, such as `treat wounds`, to apply any healing bonus for that action.

## The GM

`damage[/ndc] <list>=<amount>[ <kind>[ <what else>...]]`: Damages each combatant in `<list>` for `<amount>`. Name the damage type (such as `fire`, `cold`, or `persistent-damage`) to apply the target's immunities, weaknesses, and resistances before the damage lands; without a type, nothing resists the damage. After the type, add any other properties of the damage (`silver`, `cold iron`, `magical`, `holy`, `area`, `splash`, `spell`, or `nonlethal`), so that weaknesses and resistances that depend on them apply: `damage #3=12 slashing silver`.
%t **Note:** Damage from a Plotmaster or staff can kill a character whose Dying value reaches the death threshold, unless you add `/ndc`. Damage from anyone else never kills a character; it leaves them unconscious instead.
`condition/set <list>=<condition>[/<value>]`: Sets `<condition>` on each combatant in `<list>`. `<value>` is 1-5, and 0 clears the condition.
%t **Note:** Only a Plotmaster or staff can give a character Drained or Doomed, but anyone running the encounter can lower or clear them. Only a Plotmaster or staff can mark a character dead with `condition/set <who>=dead`, and `condition/set <who>=dead/0` brings the character back, unconscious at 0 HP.

## At 0 hit points

A character reduced to 0 HP is dying: Dying 1, or Dying 2 from a critical hit, plus their Wounded value. From then on, their turn comes right before the turn of whoever was acting when they fell, and they roll a recovery check at the start of each of their turns. While dying, they can't act, except to use a reaction that could have prevented the hit that dropped them.

- **A nonlethal hit** knocks a character out without killing them: they're unconscious at 0 HP, not dying, and wake up once healed.
- **Damage of at least twice their maximum HP in a single hit** kills a character outright, if the encounter allows death.

## First aid and recovery

`encounter/act administer first aid=<who>/stabilize`: Rolls Medicine against the dying character's recovery DC + 5. On a success, they're no longer dying, but they're still unconscious and their Wounded value goes up by one. On a critical failure, they move closer to death.
`encounter/act administer first aid=<who>/stop bleeding/<dc>`: Rolls Medicine against the DC of whatever made the character bleed. On a success, they get a DC 10 flat check to end the bleeding; on a critical failure, they take the bleed damage immediately.
`encounter/act assisted recovery[=<who>][/<kind>][/<dc>]`: Spends two actions putting out flames or staunching bleeding on a character with persistent damage. They get an extra flat check right away, against the damage's DC or the DC the GM allows.
