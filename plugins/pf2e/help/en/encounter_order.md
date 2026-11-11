---
toc: Pathfinder Second Edition - Running Encounters
summary: Moving through turns, and changing the initiative order.
aliases:
- e_order
- e_next
- e_prev
- e_mod
- e_remove
- e_scan
- e_resync
- ninit
- pinit
- rminit
- tscan
- initiative_order
- next_turn
---
# Pathfinder 2E Encounters - The Initiative Order

`encounter/next`: Moves on to the next turn. (Alias: `ninit`)
`encounter/prev`: Moves back one turn. (Alias: `pinit`)
`encounter/mod [<encounter ID>=]<#id or name>=<new init>`: Sets a combatant's initiative. The current turn stays where it is.
`encounter/remove [<encounter ID>=]<#id or name>`: Removes a combatant from the encounter. A removed creature is gone for good. (Alias: `rminit`)
`encounter/scan [<encounter ID>]`: Shows the encounter the way `encounter/view` shows it to you, with each creature's immunities, weaknesses, and resistances. Only the GM can use this. (Alias: `tscan`)
`encounter/resync [<encounter ID>=]<#id or name>`: Updates a character's encounter gear from their sheet, for something they forgot to buy or invest before joining. Items they already had in the encounter stay as they are. `encounter/undo` reverses a resync.
