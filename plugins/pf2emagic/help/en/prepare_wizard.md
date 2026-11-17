---
toc: Pathfinder Second Edition - Magic
summary: Preparing with Split Slot, Spell Combination, and Spell Mastery.
aliases:
- prepare_wizard
- prepare_splitslot
- prepare_spellcombination
- prepare_spellmastery
- split_slot
- spell_combination
- spell_mastery
---

# Two Spells in One Slot, and Mastered Spells: Split Slot, Spell Combination, and Spell Mastery

A wizard with one of these feats prepares through its own switch. `prepared` and `magic` show what you have, and each takes effect when you next `rest`.

- **Split Slot**: two spells in one slot, at least one rank below your highest. Cast either one and the other is lost.
- **Spell Combination**: two spells in one slot of rank 3 or higher, one such slot per rank. Both are cast together, at two ranks below the slot. Both spells must target only one creature (or be able to), and both must work the same way: both by spell attack, both by the same save, or both automatically. The code doesn't check this yet, so keep to it yourself.
- **Spell Mastery**: up to four spells from your spellbook, each at a different rank of 9 or lower, prepared at every rest in slots of their own. Change them whenever you like; the change takes effect at your next rest.

**Commands**:
`prepare/splitslot <rank> = <spell>, <spell>`: Prepares two spells in one slot of `<rank>`.
`unprepare/splitslot`: Empties that slot.
`prepare/spellcombination <rank> = <spell> + <spell>`: Prepares a combined spell in a slot of `<rank>`.
`unprepare/spellcombination <rank>`: Empties the combination slot of `<rank>`.
`prepare/spellmastery [<rank> =] <spell>`: Masters `<spell>`, at its own rank or at `<rank>`. A spell already mastered at that rank is replaced.
`unprepare/spellmastery <spell>`: Stops mastering `<spell>`.

To cast from one of these slots, cast the spell as usual. A combined spell is cast by specifying either of its spells.
