---
toc: Pathfinder Second Edition - Running Encounters
summary: Acting for creatures, and letting them do what their stat block doesn't give them.
aliases:
- e_as
- e_option
- e_force
- encounter_gmactions
- pf2e_encounter_gm
---
# Pathfinder 2E Encounters - Acting for Creatures

`encounter/as <combatant>=<act|strike|cast|enter|leave> <what>`: Acts for a creature, or for anyone else in the encounter, with the same commands players use.
%t **Examples**:
%t `encounter/as #3=strike aria`
%t `encounter/as #3=strike shortbow=aria/range 2`
%t `encounter/as #5=act demoralize=aria`
%t `encounter/as #3=act goblin scuttle`
%t `encounter/as #6=cast fear=aria`
%t `encounter/as #6=act magma breath=#1,#2,aria`
%t **Note:** For more information on command syntax, see `help e/strike`, `help e/act`, and `help e/cast`. For more information about what the game does with a creature's abilities, see `help e/abilities`.

## Going beyond the stat block

A creature can use the basic actions anyone can, such as Stride, Trip, or Raise a Shield, its own abilities, and the spells its stat block lists. To have it do anything else, add `/force`.
%t **Example**:
%t `encounter/as #3=cast force barrage=aria/force`
%t **Note:** A spell cast this way is cast at half the creature's level, rounded up, unless you add `/rank <n>`. If the creature has no spell attack or spell DC on its stat block, you roll the attack or set the DC yourself.
`/force` also lets a character in a battle form do something the form prevents if you rule that they can do it: `encounter/as aria=act interact/force`.

## Options

`encounter/option <combatant>=<option>[/on|off|default]`: Turns a circumstance from a creature's own rules on or off, such as fast healing that only works in open air. With no option specified, this lists the creature's options.
