---
toc: Pathfinder Second Edition - Encounters
summary: Details you add to an encounter command, such as flanking or range 2.
aliases:
- e_details
- e_command_details
- e_circumstances
- circumstances
- flanking
- two_handed
- versatile
- nonlethal
- volley
---
# Pathfinder 2E Encounters - Command Details

A command detail tells the game something it can't see, such as where you stand. Add each one after the target, after a `/`.
%t **Examples**:
%t `encounter/strike longsword=#3/flanking`
%t `encounter/strike bastard sword=#3/flanking/two-handed`

- `flanking`: The target is off-guard to you (-2 AC).
- `range <n>`: The target is in range increment `<n>`: -2 to your attack for each increment past the first. Ranged attacks can't reach past the sixth increment.
- `<number>`: Sets the DC for an action with no target, such as `encounter/act balance/18`.
- `two-handed`: Uses both hands on a weapon that deals more damage that way.
- `piercing`, `slashing`, `bludgeoning`: Chooses the damage type a versatile weapon deals this time.
- `nonlethal`, `lethal`: Makes a nonlethal attack with a lethal weapon, or a lethal attack with a nonlethal weapon, at -2 to hit. A nonlethal hit that drops someone to 0 HP knocks them out.
- `volley`: The target is within a volley weapon's short range (-2 to hit).
- `silver`, `cold iron`, `holy`, `magical`, and so on: Specifies what your weapon is made of or carries, so weaknesses and resistances to it apply.
- `hidden`: The target is hidden from this one attack only. See `help e/cover` for more information about concealment.
- `force`: **GM.** Has a creature do something its stat block doesn't give it, or a character do something their battle form prevents. See `help e/as` for more information about `/force`.

Other command details come from the action's own rules, such as `unintelligible` for Demoralize, a skill for Aid, or `stabilize` for Administer First Aid. The help file for each action lists them.

You don't need to specify a weapon's other traits, such as sweep, forceful, or backstabber; the game applies them on its own.
