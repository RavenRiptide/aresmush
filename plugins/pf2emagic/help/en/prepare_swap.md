---
toc: Pathfinder Second Edition - Magic
summary: Changing a prepared spell after your daily preparations.
aliases:
- prepare_swap
- prepare_reprepare
- call_of_the_wild
- elemental_summons
- rites_of_convocation
- spell_substitution
- reprepare_spell
---

# Changing a Prepared Spell: Call of the Wild, Elemental Summons, Rites of Convocation, Spell Substitution, and Reprepare Spell

Each of these takes 10 minutes, so you can't use them during a fight. You can use them while exploring or outside an encounter. In an encounter, they change the spells you have left there.

- **Call of the Wild** (druid): replace a prepared spell with *summon animal* or *summon plant or fungus* of the same rank.
- **Elemental Summons** (druid): replace a prepared spell with *summon elemental* of the same rank.
- **Rites of Convocation** (witch): replace a prepared spell with the summon spell you chose when you took the feat, of the same rank. Your familiar doesn't need to know it.
- **Spell Substitution** (wizard arcane thesis): replace a prepared spell with any spell from your spellbook of the same rank.
- **Reprepare Spell** (wizard): prepare again a spell you cast today, of rank 4 or lower and without a duration. With Spell Substitution, you can instead prepare a different spell without a duration in that slot. Until your next daily preparations, that slot can hold only spells without a duration.

**Commands**:
`prepare/swap <spell> = <new spell>`: Replaces one prepared `<spell>` you haven't cast yet with `<new spell>`, at the lowest rank you have `<spell>` prepared.
`prepare/swap <spell> <rank> = <new spell>`: Replaces `<spell>` prepared at `<rank>`.
`prepare/reprepare <spell>`: Prepares `<spell>` again in the slot you cast it from.
`prepare/reprepare <spell> = <new spell>`: Prepares `<new spell>` in the slot you cast `<spell>` from. Requires Spell Substitution.

For more information about preparing spells, see `help prepare`.
