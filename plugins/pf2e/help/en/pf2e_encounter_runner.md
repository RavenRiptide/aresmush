---
toc: Pathfinder Second Edition
summary: Encounter commands for whoever runs an encounter.
aliases:
- encounter_runner
- encounter runner
---
# Pathfinder 2E Encounters - Running an Encounter

`encounter/view` shows each combatant's ID: `#1`, `#2`, and so on. See `help encounter` or [read it on the web](/help/pf2e_combat) for how IDs work.

Any approved character can start an encounter. The encounter's GM is whoever started it, or whoever it was transferred to, and staff can run any encounter. Your GM commands reach your encounter from anywhere: in the encounter's scene, they go to that encounter; elsewhere, they go to the only encounter you run, or to the one you chose with `encounter/focus`.

What an encounter can do depends on who runs it:

- **Anyone** can run an encounter with creatures from Monster Core and Monster Core 2, as written or with the elite or weak adjustment. These encounters can't kill a character or leave them Drained or Doomed. A character who would die is left unconscious and no longer dying instead, and Drained or Doomed from a creature's ability doesn't apply. Anything a character does to themselves still applies.
- **A Plotmaster** (a role with the `kill_pc` permission) can add any bestiary creature, and custom creatures. In a Plotmaster's encounters, Drained and Doomed apply, and a character dies when their Dying value reaches the death threshold, whether from a hit, persistent damage, or a failed recovery check. `encounter/undo` reverses a death like any other change, and `condition/set <who>=dead/0` brings a character back.
- **Staff** run any encounter the same way a Plotmaster does.

## Starting and running an encounter

`encounter [<stat>][=<encounter ID>]`: Starts an encounter in the scene, with you as its GM, and rolls initiative on `<stat>` (Perception by default). Name an earlier encounter to continue from it: everyone who was in it keeps their wounds, conditions, effects, and spent spells. Anyone else starts fresh from their own sheet, fully rested.
%t **Note:** Starting an encounter while the party is exploring replaces the exploration. See `help exploration` or [read it on the web](/help/pf2e_exploration).
`encounter/focus [<encounter ID>]`: Chooses which of your encounters your commands go to while you're away from its scene. With no ID, your commands go to the only encounter you run.
`encounter/owner [<encounter ID>=]<character>`: Transfers the encounter to `<character>`, who becomes its GM.
`encounter/end <encounter ID>`: Ends an encounter. Ending it also clears trust, cover and concealment, and once-per-encounter uses.
`encounter/restart <encounter ID>`: Restarts an encounter, as long as its scene hasn't ended.

## Adding creatures

`encounter/add [<count>] [elite|weak] <creature>[/<shape>][=<name>]`: Adds creatures from the Remaster bestiary, which has about three thousand of them. Each creature gets its own ID, hit points, and conditions, and rolls initiative on its Perception. (Alias: `jinit`)
%t **Examples**:
%t `encounter/add 3 goblin warrior` adds three goblin warriors.
%t `encounter/add goblin warrior=Grik` adds one goblin warrior named Grik.
%t `encounter/add 2 elite goblin warrior` adds two goblin warriors with Monster Core's elite adjustment.
%t `encounter/add 3 werewolf/animal` adds three werewolves already in wolf form, at no action cost.
%t **Note:** Player characters join with `encounter/join` instead.
`encounter/add [elite|weak] <name>=<description>`: Adds a custom creature. Only Plotmasters and staff can use this. See `help encounter_creatureimport` or [read it on the web](/help/pf2e_encounter_creatureimport).
`encounter/adjust <#id>[,<#id>...]=elite|weak|normal`: Makes a creature already in the encounter elite or weak, or removes the adjustment. Use this to fit one creature to parties of different levels. The creature keeps any damage it has already taken, and only you are told about the change.
%t **Note:** Elite gives the creature +2 to AC, attacks, DCs, saves, Perception, and skills; +2 damage on Strikes and abilities (+4 on abilities it can't use every round, and on spells); extra hit points based on its level; and +1 level. Weak does the reverse.
`encounter/bestiary <words>[/<level>]`: Lists the creatures you can add whose names contain `<words>`, at the given level if you name one.
`encounter/creature <creature>`: Shows a creature's stat block from the bestiary. You can't use this while you're a player in someone else's encounter.

## The initiative order

`encounter/next`: Moves the initiative forward one turn. (Alias: `ninit`)
`encounter/prev`: Moves the initiative back one turn. (Alias: `pinit`)
`encounter/mod [<encounter ID>=]<#id or name>=<new init>`: Sets a combatant's initiative. The current turn stays where it is.
`encounter/remove [<encounter ID>=]<#id or name>`: Removes a combatant from the initiative order. A removed creature is gone for good. (Alias: `rminit`)
`encounter/scan`: Shows everyone in the encounter by ID, as they currently are: each combatant's hit points, AC, Perception, saves, and whether they have Reactive Strike; each creature's level and any elite or weak adjustment; and each combatant's immunities, weaknesses, and resistances. (Alias: `tscan`)
`encounter/resync [<encounter ID>=]<#id or name>`: Updates a character's encounter gear from their sheet, for something they had to buy after joining. The game adds the items they bought since joining, and sets their money to match their sheet. Items they already had stay as they are in the encounter (drawn or stowed, minus anything used), and so does anything the encounter gave them. `encounter/undo` reverses a resync.

## Party, difficulty, and rewards

`encounter/level <n>`: Sets the party level used for the encounter's difficulty. Without it, the game uses the characters' average level, and `encounter/level 0` goes back to the average.
%t **Note:** `encounter/view` shows the GM the encounter's difficulty: the threat level, from trivial to extreme, and the XP behind it, using GM Core's encounter budget. Players don't see the difficulty, in the game or on the web.
`hero/award [<why>]`: Gives every player character in the scene a Hero Point, up to a maximum of three. `encounter/scan` shows how many each character has.

For running the creatures in an encounter, see `help encounter_creatures` or [read it on the web](/help/pf2e_encounter_creatures). For custom creatures, see `help encounter_creatureimport` or [read it on the web](/help/pf2e_encounter_creatureimport).
