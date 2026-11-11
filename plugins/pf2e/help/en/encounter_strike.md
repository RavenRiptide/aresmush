---
toc: Pathfinder Second Edition - Encounters
summary: Making a Strike, throwing a bomb, and reloading.
aliases:
- e_strike
- e_reload
- strike
- bomb
- bombs
- splash
- ammunition
- ammo
---
# Pathfinder 2E Encounters - Strikes

`encounter/strike [<weapon>=]<target>[/<detail>...]`: Strikes the target with your first equipped weapon, or with the weapon you specify: by name, by nickname, or an unarmed attack such as `fist`. On a hit, the game rolls the damage and deals it.
%t **Examples**:
%t `encounter/strike #3`
%t `encounter/strike longsword=#3/flanking`
%t `encounter/strike shortbow=#4/range 2`
%t **Note:** For more information about command details, such as `flanking` and `range 2`, see `help e/details`.

## Bombs

`encounter/strike <bomb>=<target>[/splash <target>, <target>]`: Throws a bomb you carry. The bomb is used up whether or not it hits. To splash others near the target, specify them after `splash`; the GM decides who is close enough.
%t **Example**:
%t `encounter/strike alchemist's fire=#3/splash #4, #5`

## Ammunition and reloading

`encounter/reload [<weapon>]`: Reloads a weapon that needs it, such as a crossbow or sling. Reloading takes as many actions as the weapon's reload value.
%t **Note:** The game doesn't track ordinary ammunition. To fire a piece of precious ammunition you bought, specify its material: `encounter/strike longbow=#3/cold iron`. The piece is used up whether or not it hits.

For more information about actions that include a Strike, such as Flurry of Blows or Reactive Strike, see `help e/classfeats`. `encounter/how strike` lists the Strikes you can make.
