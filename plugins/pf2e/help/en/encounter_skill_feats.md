---
toc: Pathfinder Second Edition - Encounters
summary: General and skill feats in an encounter, such as Battle Medicine and Shield Block.
aliases:
- e_skillfeats
- e_generalfeats
- battle_medicine
- bon_mot
- shield_block
- titan_wrestler
---
# Pathfinder 2E Encounters - General and Skill Feats

These feat actions take more than `encounter/act <action>=<target>`, or work differently from other actions. For more information about other actions, see `help e/act`.

`encounter/act battle medicine=<who>[/<DC>]`: Rolls Medicine to heal someone, against DC 15, or against a higher Treat Wounds DC (20, 30, or 40) if you specify one, for more healing.
%t **Example**:
%t `encounter/act battle medicine=bram/20`
%t **Note:** The GM keeps track of who you've treated today.
`encounter/act bon mot=<target>`: Rolls Diplomacy against the target's Will DC, and applies the result.
`encounter/act shield block`: Blocks a hit you just took while your shield is raised. Your shield's Hardness reduces the hit's physical damage, and you and the shield each take the rest. The game tells you when you can block a hit.
%t **Note:** Raise your shield first with `encounter/act raise a shield`.
**Titan Wrestler:** Lets you Disarm, Grapple, Reposition, Shove, and Trip targets up to two sizes larger than you, or three sizes larger if you're legendary in Athletics. The game applies this on its own.
