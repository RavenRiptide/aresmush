---
toc: Pathfinder Second Edition - Magic
summary: Preparing spells.
aliases:
- prepare
- unprepare
- prepared
---

# Preparing Spells in Pathfinder Second Edition

Some classes record spells and cantrips in a spellbook, or otherwise 'prepare' spells for the day.

**Important!** The spells you prepare are the ones you can cast in your next encounter. You start the encounter with them, and you prepare them again each time the GM rests you in that encounter. See `help rest`.

**Commands**:
`prepare <caster class>/<level> = <spell name>`: Prepares `<spell name>` at the defined level, optionally at a higher `<level>` than its default level. Preparing at a higher level than a spell's base level heightens the spell to that level. (You can't prepare a spell lower than its default level.) Omitting the `<level>` switch will prepare the spell at its base level.
`unprepare <caster class>/<level> = <spell name>`: Removes `<spell name>` at the defined `<level>` from your prepared list.
`prepare <caster class>/<cantrip> = <spell name>`: Prepares the cantrip `<spell name>`.
`unprepare <caster class>/<cantrip> = <spell name>`: Removes the cantrip `<spell name>` from your prepared list.
`prepared [<caster class>]`: Shows how many spell slots you have at each rank and the spells you've prepared in them, including ranks with nothing prepared yet. If `<caster class>` is omitted, it shows all your classes and your daily choices.

Some feats have you make other choices during your daily preparations, such as the skill Ancestral Longevity trains you in. See `help daily_choices`.

## Other ways to prepare

- `help prepare/cleric`: Filling a cleric's divine font slots, and preparing their deity's spells.
- `help prepare/book`: Picking a spell each day from a Book of Occult Spells (Esoteric Polymath) or an Arcane Evolution list.
- `help prepare/wizard`: Split Slot, Spell Combination, and Spell Mastery.
- `help prepare/staff`: Preparing a staff, expending spells on it, and Staff Nexus.
