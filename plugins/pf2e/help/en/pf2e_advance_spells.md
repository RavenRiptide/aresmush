---
toc: Pathfinder Second Edition - Advancement
summary: Commands related to advancement and spells.
aliases:
- advancespells
---

# Advancement - Spells and Magic

See `help advance` for more information about advancement.

## Learning Spells

A level-up can give you new spells to learn, and `advance/review` lists the open spell slots. Repertoire spellcasters can also swap a spell they know for a new one, and some choose signature spells from their repertoire.

**Commands**:
`advance/spell <type>/<level>=<spell name>`: Learns a new spell (`<spell name>`) of the rank you specify (`<level>`). `<type>` is `repertoire` or `spellbook`, depending on how you cast. You need an open slot at that rank.
`advance/spell innate/<level>=<spell name>`: Learns an innate spell (`<spell name>`) of the rank you specify (`<level>`), when a feat gives you an open innate spell.
`advance/swapspell repertoire/<level>=<old spell>/<spell name>`: Swaps a repertoire spell you know (`<old spell>`) for a new spell (`<spell name>`) of the same rank (`<level>`). You can swap once per level-up, and cantrips count.
%t **Note:** You can't swap the spells your bloodline or class gives you.
`advance/spell signature/<level>=<spell name>`: Makes a repertoire spell (`<spell name>`) a signature spell. `<level>` is the spell's base rank.
`spell/eligible <level>`: Lists every spell you can take at a rank (`<level>`), for the traditions you cast. Add `=<text>` to narrow the list. For more information about finding spells, see `help spell search`.

## The Divine Font

A cleric whose deity grants both fonts chooses which spell their extra daily slots cast. Clerics usually choose in character generation, but a level-up can open the choice too, and `advance/review` lists it under Options To Choose.

`advance/font <heal or harm>`: Chooses your divine font. Your extra daily spell slots at each rank then cast that spell.
%t **Note:** In character generation, use `cg/font` or `dfont`. Staff can set it with `admin/set <character>/divine font=<heal or harm>`.

## Archetype Spells

If your class casts spells and your archetype gives you spellcasting too, learn your archetype's spells by adding the archetype's name to `advance/spell`. If your class doesn't cast spells, use the commands in the Learning Spells section.

**Commands**:
`advance/spell repertoire/<archetype name>/<level>=<spell name>`: Adds a spell (`<spell name>`) of the rank you specify (`<level>`) to your archetype's repertoire. `<archetype name>` is the archetype's full name, such as `oracle archetype`.
`advance/spell spellbook/<archetype name>/<level>=<spell name>`: Adds a spell (`<spell name>`) of the rank you specify (`<level>`) to your archetype's spellbook.
%t **Examples**:
%t `advance/spell repertoire/oracle archetype/cantrip=Stabilize`: Adds the Stabilize cantrip to your oracle archetype's repertoire.
%t `advance/spell spellbook/wizard archetype/cantrip=Light`: Adds the Light cantrip to your wizard archetype's spellbook.
