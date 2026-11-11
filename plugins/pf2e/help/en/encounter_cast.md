---
toc: Pathfinder Second Edition - Encounters
summary: Casting a spell in an encounter.
aliases:
- e_cast
- force_barrage
---
# Pathfinder 2E Encounters - Spells

`encounter/cast <spell>[=<target>,<target>...][/rank <n>][/class <class>]`: Casts a spell at one or more targets. It uses a slot, a Focus Point, or a usage the same way `cast` does, and the command is refused if you have none left. The game rolls your spell attack against each target's AC, or has each target roll a save against your spell DC, and applies the outcome.
%t **Examples**:
%t `encounter/cast fear=#3`
%t `encounter/cast fireball=#3,#4,#5/rank 4`
%t `encounter/cast heal=#2/actions 2`
%t **Note:** Add `/focus`, `/innate`, or `/signature` to cast that kind of spell.

## Telling the game how you cast

- **A spell with more than one version:** Specify the version, such as `/actions 2` for Heal's two-action version, or a word from a variant's name, such as `/silver` for silver Needle Darts.
- **A spell that affects an item or asks for a choice:** Specify the item or your choice after the target: `encounter/cast runic weapon=Bram/longsword` or `encounter/cast resist energy=Bram/fire`.
- **Force Barrage:** Spend one action for each shard: `encounter/cast force barrage=#3/actions 3`. Every target you specify takes all the shards. To split them, cast at one target with `/actions` set to the number of shards it takes, and the GM rolls each other shard's damage and deals it to its target: `roll 1d4+1` for a 1st-rank shard, then `damage #4=<result> force`. `encounter/turn` then counts fewer actions than you spent.
- **Heal and Harm:** Each target is healed or damaged depending on what kind of creature it is. The two-action version's extra healing only applies to healing.
- **A save that isn't basic:** If the spell's text doesn't say how much damage a target takes on the outcome they rolled, the game deals none. It shows the room the spell's damage dice instead, and the GM decides how much damage that target takes and deals it with `damage`. For more information about `damage`, see `help heal` or [read it on the web](/help/pf2e_healing).

For more information about casting outside an encounter, Untamed Form, and spell slots, see `help cast` or [read it on the web](/help/cast). For more information about casting from a scroll, wand, or staff, see `help e/gear`.
