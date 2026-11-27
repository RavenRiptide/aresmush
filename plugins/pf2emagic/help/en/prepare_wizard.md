---
toc: Pathfinder Second Edition - Magic
summary: Preparing with Split Slot, Spell Combination, Spell Mastery, Infinite Possibilities, and Form Retention.
aliases:
- prepare_wizard
- prepare_splitslot
- prepare_spellcombination
- prepare_spellmastery
- prepare_infinite
- prepare_formretention
- split_slot
- spell_combination
- spell_mastery
- infinite_possibilities
- form_retention
---

# Two Spells in One Slot, Mastered Spells, Open Slots, and Retained Forms: Split Slot, Spell Combination, Spell Mastery, Infinite Possibilities, and Form Retention

A wizard with one of these feats prepares through its own switch. `prepared` and `magic` show what you have, and each takes effect when you next `rest`.

- **Split Slot**: two spells in one slot, at least one rank below your highest. Cast either one and the other is lost.
- **Spell Combination**: two spells in one slot of rank 3 or higher, one such slot per rank. Both are cast together, at two ranks below the slot. Both spells must target only one creature (or be able to), and both must work the same way: both by spell attack, both by the same save, or both automatically. The code doesn't check this yet, so keep to it yourself.
- **Spell Mastery**: up to four spells from your spellbook, each at a different rank of 9 or lower, prepared at every rest in slots of their own. Change them whenever you like; the change takes effect at your next rest.
- **Infinite Possibilities**: one slot of rank 3 or higher held open. When you cast from it, choose any spell from your spellbook of 2 or more ranks lower than the slot. The spell is cast as a spell 2 ranks lower than the slot.
- **Form Retention**: a polymorph spell that grants a battle form and lasts 1 minute, prepared in a slot 2 ranks higher than the rank you cast it at. It's cast at the lower rank and lasts up to 10 minutes.

**Commands**:
`prepare/splitslot <rank> = <spell>, <spell>`: Prepares two spells in one slot of `<rank>`.
`unprepare/splitslot`: Empties that slot.
`prepare/spellcombination <rank> = <spell> + <spell>`: Prepares a combined spell in a slot of `<rank>`.
`unprepare/spellcombination <rank>`: Empties the combination slot of `<rank>`.
`prepare/spellmastery [<rank> =] <spell>`: Masters `<spell>`, at its own rank or at `<rank>`. A spell already mastered at that rank is replaced.
`unprepare/spellmastery <spell>`: Stops mastering `<spell>`.
`prepare/infinite <rank>`: Holds a slot of `<rank>` open.
`unprepare/infinite`: Prepares that slot as usual again.
`prepare/formretention <rank> = <spell>`: Prepares a battle form `<spell>` in a slot of `<rank>`, to cast at 2 ranks lower.
`unprepare/formretention [<rank>]`: Empties that slot.

To cast from one of these slots, cast the spell as usual. A combined spell is cast by specifying either of its spells. A spell cast from an open slot is one you haven't prepared anywhere else.
