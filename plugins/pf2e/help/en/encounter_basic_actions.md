---
toc: Pathfinder Second Edition - Encounters
summary: Basic actions that need more than a target, such as Delay, Sustain, and Administer First Aid.
aliases:
- e_basic
- delay
- sustain
- dismiss
- escape
- retch
- first_aid
- administer_first_aid
- assisted_recovery
- aid
- raise_a_shield
---
# Pathfinder 2E Encounters - Basic Actions

These basic actions take more syntax than `encounter/act <action>=<target>`. For more information about other actions, see `help e/act`.

## Your turn and your effects

`encounter/act delay`: Waits for a better moment, at the start of your turn. Your end-of-turn effects happen right away, and the GM moves on initiative. To come back into initiative, use `encounter/act delay` again after anyone else's turn: you act then, and keep that new place in the order. If a full round passes without you coming back, you lose that turn.
`encounter/act sustain[/<effect>]`: Keeps an effect you sustain going through the end of your next turn. You can leave off the effect's name if you have only one effect to sustain.
%t **Note:** An effect you don't sustain ends at the end of your next turn. If sustaining it does something more, the GM takes care of that part.
`encounter/act dismiss/<effect>`: Ends an effect that can be dismissed, on everyone you put it on. You can also dismiss an effect a GM put on you.

## Getting free

`encounter/act escape`: Escapes whoever is holding you. If you're swallowed or engulfed, the game uses the DC the creature lists. See `help e/conditions` for more information.
`encounter/act retch[/<DC>]`: Tries to shake off the sickened condition with a Fortitude save against the DC of whatever sickened you. If the GM set the condition manually instead of from a creature's stat block or effect, add the DC manually: `encounter/act retch/18`.

## Helping others

`encounter/act administer first aid=<who>/stabilize`: Stabilizes someone who is dying.
`encounter/act administer first aid=<who>/stop bleeding/<DC>`: Tries to stop someone's persistent bleed damage, against the DC of what made them bleed.
`encounter/act assisted recovery[=<who>][/<kind>][/<DC>]`: Gives you, or someone else, another flat check to end persistent damage. Specify the kind of damage, such as `fire`, if there's more than one. Add a lower DC if the GM rules the help is especially fitting.
`encounter/act aid=<who>/<skill>`: Aids an ally's check with the skill you specify.

## Limits the game enforces

- **Disarm, Grapple, Reposition, Shove, and Trip** only work on targets up to one size larger than you. The Titan Wrestler feat raises the limit; see `help e/skillfeats` for more information.
- **Raise a Shield** needs a shield equipped that isn't broken.
- **Actions with their own command** are refused with the command to use instead, such as `encounter/alchemy` for Quick Alchemy, `encounter/refocus` for Refocus, and `encounter/cast` to cast a spell.
- **Exploration activities** are refused during a fight. For more information about exploring, see `help exploration` or [read it on the web](/help/pf2e_exploration).
