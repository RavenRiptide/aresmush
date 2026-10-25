---
toc: Pathfinder Second Edition - Admin
summary: Admin commands for other miscellaneous functions.
aliases:
- pf2estaff_other
- pf2eadmin_other
---

# Pathfinder 2E -- Admin Commands for Miscellaneous Purposes

Staff can make some modifications to characters' sheets. 

### RPP
**Commands**:
`rpp <name>`: Shows currently available RPP and total RPP for a player. You can specify any alt of a player to see that player's RPP. 
`rpphist <name>` (alias: `listrpp`) Shows the history of RPP received and spent for the named player in reverse chronological order. You can specify any alt of a player to see information for that player.

`rpp/award <name>=<award>[/<reason>]`: Awards a PC RPP. Note that RPP is tracked per player, not per character.
`rpp/spend <name>=<spend>[/<reason>]`: Spends RPP for a player.

### Reset or respec a character
**Commands**:
`admin/reset <character>`: Resets the character sheet, sets them to unapproved, forces them back through chargen, and wipes level / XP / gold back to starting default. 
`admin/respec <character>`: Resets the character sheet, sets them to unapproved, forces them back through chargen, but preserves level / XP / money. Inventory and stats are cleared. 

### Manage jobs
See `help jobs`.

### Reset a password / change a player's name or alias / set a MotD
See `help manage login`.

### Dealing with griefers, trolls, and creeps
See `help ban`, `help boot`, and `help statue`. Also `help trouble tutorial`.