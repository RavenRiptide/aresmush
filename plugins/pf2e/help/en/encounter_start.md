---
toc: Pathfinder Second Edition - Running Encounters
summary: Starting, continuing, handing over, and ending an encounter, and its difficulty.
aliases:
- e_start
- e_end
- e_focus
- e_owner
- e_restart
- e_level
- encounter_runner
- pf2e_encounter_runner
- difficulty
- threat
- party_level
---
# Pathfinder 2E Encounters - Starting and Ending

`encounter [<stat>][=<encounter ID>]`: Starts an encounter in the scene, with you as its GM, and rolls initiative on `<stat>` (Perception by default). Specify an earlier encounter to continue from it: everyone who was in it keeps their wounds, conditions, effects, and spent spells, and anyone else starts fresh from their sheet, fully rested.
%t **Note:** Starting an encounter while the party is exploring replaces the exploration. For more information about exploring, see `help exploration` or [read it on the web](/help/pf2e_exploration).
`encounter/focus [<encounter ID>]`: Chooses which of your encounters your GM commands go to while you're away from its scene. In an encounter's scene, your commands always go to that encounter. With no ID, they go to the only encounter you run.
`encounter/owner [<encounter ID>=]<character>`: Hands the encounter over to `<character>`, who becomes its GM.
`encounter/end <encounter ID>`: Ends an encounter. This also clears trust, cover, concealment, and once-per-encounter uses.
`encounter/restart <encounter ID>`: Restarts an encounter, as long as its scene hasn't ended.

## Difficulty and rewards

`encounter/level <n>`: Sets the party level used for the encounter's difficulty. Without it, the game uses the characters' average level. `encounter/level 0` goes back to the average.
%t **Note:** `encounter/view` shows you the threat level, from trivial to extreme, and the XP behind it. Players don't see it.
`hero/award [<why>]`: Gives every player character in the scene a Hero Point, up to three.
