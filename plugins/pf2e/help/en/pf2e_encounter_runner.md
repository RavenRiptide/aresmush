---
toc: Pathfinder Second Edition
summary: Encounter commands for whoever runs an encounter.
aliases:
- encounter_runner
- encounter runner
---
# Pathfinder 2E Encounters - Running One

Everyone in an encounter has an id, shown by `+e/view` as `#1`, `#2` and so on: see `help encounter`.

Any approved character starts an encounter, and is its GM: whoever started it, or whoever it was handed
to. Staff can run any encounter. A GM's
commands reach their encounter from anywhere: in its scene they address it, and away from it they
address the one encounter the GM runs, or the one chosen with `+e/focus`.

How far an encounter may go depends on who runs it:

- **Anyone** runs one with the creatures of Monster Core and Monster Core 2, each as written or made
  elite or weak. Their encounter does not kill a character or leave one Drained or Doomed: what would
  kill leaves the character unconscious instead, no longer dying, and a Drained or Doomed from a
  creature's ability passes them by. What a character does to themselves still lands.
- **A Plotmaster** - a role with the `kill_pc` permission - adds any creature of the bestiary, and
  creatures of their own making. In their encounter a character at the dying value that is death
  dies, from a hit, persistent damage or a failed recovery check, and Drained and Doomed land.
  `+e/undo` takes a death back like any other change, and `condition/set <who>=dead/0` brings a
  character back.
- **Staff** run any encounter as a Plotmaster does.

`+e/focus [<encounter ID>]`: Which of the encounters you run your commands address while you are away from its scene. With no ID, the only one you run.
`+e/owner [<encounter ID>=]<character>`: Hands the encounter to someone else, who is its GM from then on.

`encounter [<stat>][=<encounter ID>]`: Starts an encounter in the scene, with you as its GM, rolling initiative on `<stat>` (Perception unless you say otherwise). Name an earlier encounter and whoever was in it carries on as they left it: their wounds, conditions, effects and spent spells. Anyone else starts fresh - their own sheet, rested. Started while the party is exploring, it takes over from the exploration: see `help exploration`.
`+e/add [<count>] [elite|weak] <creature>[=<name>]`: Adds creatures from the bestiary - the Remaster's, some three thousand of them - each with its own id, hit points and conditions, and its initiative rolled on its Perception. `+e/add 3 goblin warrior` adds three; `+e/add goblin warrior=Grik` names one; `+e/add 2 elite goblin warrior` adds two with Monster Core's elite adjustment. Player characters join with `encounter/join`. (Alias: `jinit`)
`+e/adjust <#id>[,<#id>...]=elite|weak|normal`: Makes a creature already in the encounter elite or weak, or takes the adjustment off. Elite is two more to its AC, attacks, DCs, saves, Perception and skills, two more damage from its Strikes and abilities (four from what it cannot use every round, and from its spells), more hit points by its level, and a level higher; weak is the same the other way. It keeps the hit points it has lost. Only you are told. This is how one creature serves parties of different levels.
`+e/add [elite|weak] <name>=<description>`: For a Plotmaster or staff: adds a creature of your own making. See `help encounter_creatureimport`.
`+e/bestiary <words>[/<level>]`: Creatures you may add whose names hold the words, at a level if one is given.
`+e/creature <creature>`: A creature's stat block from the bestiary. Not while you are a player in someone else's encounter.
`encounter/mod [<encounter ID>=]<#id or name>=<new init>`: Sets a combatant's initiative. Whoever's turn it is keeps it.
`encounter/remove [<encounter ID>=]<#id or name>`: Takes a combatant out of the order; a creature removed is gone. (Alias: `rminit`)
`encounter/next`: Moves the initiative forward one turn. (Alias: `ninit`)
`encounter/prev`: Moves the initiative backwards one turn. (Alias: `pinit`)
`encounter/scan`: For the GM: everyone in the encounter as they stand, by id - each character and creature's hit points, AC, Perception, saves and whether they have a Reactive Strike, a creature's level and whether it is elite or weak, and beneath each what they are immune to, weak to and resist. (Alias: `tscan`)
`+e/level <n>`: Sets the party's level for the encounter's difficulty, which is otherwise the characters' average. `+e/level 0` goes back to the average. `+e/view` shows the GM the difficulty: the threat, from trivial to extreme, and the XP behind it, by GM Core's encounter budget. Players are not shown it, in the game or on the web.
`hero/award [<why>]`: Gives every player character in the scene a Hero Point, up to three. `encounter/scan` shows what each holds.
`encounter/end <encounter ID>`: Ends an encounter. Trust given for it, the cover and concealment set in it, and what may be used once an encounter all end with it.
`encounter/restart <encounter ID>`: Restarts an encounter, so long as the scene has not ended.

Running the creatures in it is in `help encounter_creatures`, and creatures of your own in `help encounter_creatureimport`.
