---
toc: Pathfinder Second Edition - Running Encounters
tutorial: true
summary: Start here - running a fight, step by step, and who can run what.
order: 1
aliases:
- e_gm
- gm
- running_encounters
- gm_quick_start
---
# Pathfinder 2E Encounters - GM Quick Start

Any approved character can start an encounter in a scene, and becomes its GM.

## Running a fight

1. `encounter`: Starts an encounter in your scene, with you as its GM.
2. `encounter/add 3 goblin warrior`: Adds three goblin warriors. `encounter/bestiary goblin` finds creatures by name.
3. Players join with `encounter/join`.
4. `encounter/view`: Shows the turn order, each combatant's ID, and each creature's stats.
5. `encounter/as #3=strike aria`: Acts for a creature on its turn, with the same commands players use: `strike`, `act`, or `cast`.
6. `encounter/next`: Moves on to the next turn.
7. `encounter/undo`: Takes back the last change, if something went wrong.
8. `encounter/end <encounter ID>`: Ends the encounter.

The game rolls attacks, checks, saves, and damage, and applies the conditions and effects it understands. When a creature uses anything else in its stat block, the game shows the room the text as written, and you apply what it does by hand, with commands such as `damage`, `condition/set`, and `effect/add`.

## Who can run what

- **Anyone** can use creatures from Monster Core and Monster Core 2. These encounters can't kill a character or leave them Drained or Doomed: a character who would die is left unconscious and no longer dying instead.
- **A Plotmaster** (a role with the `kill_pc` permission) can use any bestiary creature and custom creatures. In a Plotmaster's encounter, Drained and Doomed apply, and characters can die. `encounter/undo` reverses a death, and so does `condition/set <who>=dead/0`.
- **Staff** run any encounter the same way a Plotmaster does.

## GM help files

- `help e/start`: Starting, continuing, handing over, and ending an encounter, and its difficulty.
- `help e/add`: Adding creatures, and making them elite or weak.
- `help e/order`: Moving through turns, and changing the initiative order.
- `help e/as`: Acting for creatures.
- `help e/abilities`: What the game does with a creature's stat block, and what's left to you.
- `help e/undo`: Undoing and redoing changes.
- `help e/import`: Adding a custom creature in one line.
- `help e/cover`: Setting cover and concealment, and trusting a player to set them.
- `help heal`: Damaging, healing, and setting conditions by hand. [Read it on the web](/help/pf2e_healing).
