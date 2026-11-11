---
toc: Pathfinder Second Edition - Encounters
summary: Your turn, the modifiers on your last roll, finding the right command, and auras.
aliases:
- e_turn
- e_why
- e_how
- e_enter
- e_leave
- why
- how
- auras
- multiple_attack_penalty
---
# Pathfinder 2E Encounters - Your Turn

At the start of your turn, the game tells you your actions, your effects and how long they last, any persistent damage, and your auras.

`encounter/turn [<who>]`: Shows how many actions you've used this turn, whether you've spent your reaction, and your multiple attack penalty.
%t **Note:** The game never refuses an action for going over your actions, since the GM can always allow it. It tells the room instead.
`encounter/why`: Lists every modifier on your last roll, and on the defense it was rolled against.
`encounter/how <name>`: Shows the commands for what you specify, as you'd type them: an action, a Strike, a spell, an item you carry, or something such as spending a Hero Point. In an encounter, it works from what you carried in.
%t **Examples**:
%t `encounter/how strike`
%t `encounter/how opportune riposte`
%t `encounter/how healing potion`
%t `encounter/how hero point`

## Auras

`encounter/enter <aura>=<target>,<target>`: Marks which combatants are inside one of your auras. They get the aura's effects, following its rules for allies and enemies.
`encounter/leave <aura>=<target>`: Marks that a combatant has left your aura, which ends its effects on them.
