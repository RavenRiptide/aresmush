---
toc: Pathfinder Second Edition
summary: Exploring between fights - activities, Treat Wounds, and how a fight starts from it.
aliases:
- explore
- exploration
- exploring
---
# Pathfinder 2E - Exploring

Between fights, the party explores: traveling, searching, and recovering. Exploration is its own kind of encounter in the scene, with no initiative or turns. What happens during an exploration carries into the fight that starts from it, and a fight can carry into the next exploration, so wounds, spent spells, and used potions follow the party through the scene.

## For the GM

`encounter/explore[=<encounter ID>]`: Starts an exploration in the scene, with you as its GM. Name an earlier encounter, such as the fight that just ended, and everyone who was in it continues as they left it.
`encounter` or `encounter/start`: While the party is exploring, ends the exploration and starts a fight that continues from it. Everyone exploring joins the fight immediately and rolls initiative based on their exploration activity. Add the creatures with `encounter/add`.
`encounter/end <encounter ID>`: Ends a fight. To continue exploring from it, use `encounter/explore=<encounter ID>`.
`encounter/rest`: Declares that a night has passed. It works the same in an exploration as in a fight; see `help rest` or [read it on the web](/help/pf2e_daily).

## For players

`encounter/join`: Joins the exploration. There's no initiative to roll.
`encounter/act <activity>`: Chooses what you do as you travel: Avoid Notice, Defend, Detect Magic, Follow the Expert, Hustle, Investigate, Repeat a Spell, Scout, or Search. `encounter/view` shows what everyone is doing.
%t **Note:** Your activity affects how you start a fight. Avoid Notice rolls Stealth for your initiative instead of Perception, Scout gives everyone else +1 to their initiative, and Defend starts you with your shield raised. Any other activity rolls Perception, or whatever statistic the GM chose.
`encounter/act treat wounds=<who>[/<DC>]`: Spends ten minutes treating someone's wounds with a Medicine check against DC 15, or against DC 20, 30, or 40 for more healing. A success heals 2d8 HP and a critical success heals 4d8 HP; a critical failure deals 1d8 damage.
%t **Note:** Treat Wounds, and anything else that takes minutes, can only be done while exploring, not during a fight.
`encounter/refocus`, `encounter/use consumables=<n>[/<who>]`, and `encounter/cast`: Work the same way as in a fight.
`roll <skill>[/<DC>]`: Rolls any other check the GM asks for, such as Perception to notice something or Survival to track.
