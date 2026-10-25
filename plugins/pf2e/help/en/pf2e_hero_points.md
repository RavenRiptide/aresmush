---
toc: Pathfinder Second Edition
summary: Hero Points - reroll a check, add 10 to it, or avoid dying.
aliases:
- hero
- hero points
- heropoints
---

# Hero Points

Hero Points belong to a scene. Every player character starts a scene with one Hero Point and can hold up to three, and whoever runs the scene has none. Hero Points don't carry over: everyone starts the next scene with one again.

The person running the scene is whoever runs an encounter in it, or the scene's owner if there's no encounter.

`hero`: Shows your Hero Points in the current scene. If you're running the scene, it shows everyone's.
%t **Note:** Your Hero Points also appear on your combat sheet (`sheet/combat`) and in your row of `encounter/scan`.

## Spending a Hero Point

Spending a Hero Point isn't an action, and you can spend one even when you can't act.

`hero/reroll`: Rerolls your last check. The new roll stands, whatever it is.
`hero/boost`: Adds 10 to your last check, if the die rolled under 10.
%t **Note:** Both are fortune effects, so you can spend only one Hero Point per check, and none on a check that was already rolled twice because of another fortune or misfortune effect.

Your last check is the one from the most recent thing that happened in the encounter: your own Strike, spell, or action, or your save against something the GM just did. The game undoes that action and replays it with only your die rerolled; every other die stays the same. Whatever followed from the old roll is undone, and whatever follows from the new roll (damage, conditions, actions spent) happens instead. Nobody else's roll changes. Outside an encounter, your last check is your last `roll` in the scene.

Spend a Hero Point right after your roll. Once someone else has acted, it's too late: the game refuses the Hero Point and you keep it, though the GM can still rewind the fight with `encounter/undo`. The game also refuses it, and you keep it, while the GM whose action you rolled against is working in another encounter.

If the GM uses `encounter/undo` on a change you spent a Hero Point on, you get the Hero Point back, and `encounter/redo` spends it again. The same goes for `hero/survive`.

## Avoiding death

`hero/survive`: Spends all your Hero Points (you need at least one) to keep you from dying. You stop dying and are unconscious at 0 HP, and your Wounded value doesn't go up.
%t **Note:** You can use `hero/survive` in an encounter while you're dying, and even after your Dying value has risen high enough to kill you, for as long as that encounter lasts. When a dying character has Hero Points that could save them, the game reminds the room.

## Getting more Hero Points

`hero/award [<why>]`: Gives every player character in the scene a Hero Point, up to a maximum of three. Only the person running the scene can use this, and the game tells the room.
`hero/buy`: Buys a Hero Point for 3 RPP, and tells the room. You can't spend RPP you don't have, or hold more than three Hero Points.
`hero/give <name>`: Gives one of your Hero Points to someone in the scene who has none.
