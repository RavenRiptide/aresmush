---
toc: Pathfinder Second Edition - Running Encounters
summary: Adding creatures to an encounter, and making them elite or weak.
aliases:
- e_add
- e_adjust
- e_bestiary
- e_creature
- jinit
- elite
- weak
---
# Pathfinder 2E Encounters - Adding Creatures

`encounter/add [<count>] [elite|weak] <creature>[/<shape>][=<name>]`: Adds creatures from the Remaster bestiary. Each creature gets its own ID and hit points, and rolls initiative on its Perception. (Alias: `jinit`)
%t **Examples**:
%t `encounter/add 3 goblin warrior` adds three goblin warriors.
%t `encounter/add goblin warrior=Grik` adds one goblin warrior named Grik.
%t `encounter/add 2 elite goblin warrior` adds two elite goblin warriors.
%t `encounter/add 3 werewolf/animal` adds three werewolves already in wolf form.
%t **Note:** Player characters join with `encounter/join` instead.
`encounter/adjust <#id>[,<#id>...]=elite|weak|normal`: Makes creatures already in the encounter elite or weak, or removes the adjustment. The creature keeps any damage it has taken, and only you are told.
%t **Note:** Elite gives +2 to AC, attacks, DCs, saves, Perception, skills, and damage, more hit points, and +1 level. Weak does the reverse.
`encounter/bestiary <words>[/<level>]`: Lists the creatures you can add whose names contain `<words>`, at the level you specify, if any.
`encounter/creature <creature>`: Shows a creature's stat block from the bestiary. You can't use this while you're a player in someone else's encounter.

For more information about adding a custom creature in one line, see `help e/import`. For more information about saving a creature for use in other encounters, see `help creatures` or [read it on the web](/help/pf2e_creatures).
