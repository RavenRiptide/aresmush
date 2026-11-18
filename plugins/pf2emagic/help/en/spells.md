---
toc: Pathfinder Second Edition - Magic
summary: Other spell-related commands.
aliases:
- spell
- spells
- magic
---

# Magic-Related Commands in Pathfinder 2e
Many characters in Pathfinder 2e have access to magic. This page acts as a reference for magic-related commands.

## Basic Magic Commands
**Commands**:
`spell <spell name>`: Quickly looks up the details of a spell. This command will accept partial matches, but spell details are only given if there is exactly one match. (For a more robust spell search command, see `help spell search` to learn more about the `spell/search` command.)
`magic`: Shows your magic by class, innate spell access, and archetype, plus your focus spells. In an encounter, it shows what you have left to cast since the GM last rested you.
`magic <character>`: Shows the same for another character.

## Preparing Spells
If you're a prepared spellcaster, the spells you prepare are the ones you can cast after the GM rests you in an encounter. For more information about preparing spells and resting and a full list of spell preparation commands, see `help prepare` and `help rest`.

## Learning Spells
If you keep a spellbook or a book a feat gives you, use `spell/learn` to Learn a Spell and add a spell to it. For more information about the check, the cost, and which spells you can learn, see [Learn a Spell](/wiki/mechanics:learnaspell).

**Commands**:
`spell/learn <spell name>`: Learns `<spell name>` into your spellbook or book.
`spell/learn <book or class>/<spell name>`: If you keep more than one spellbook or book, learns `<spell name>` into the one you specify.

## Casting Spells
Casting spells depends on what type of spell you'd like to cast. For more information about casting spells and a full list of casting commands, see `help casting`.

## Searching Spells
The `spell/search` command provides a robust search function to help you find spells for your character to learn. See `help spell search` for more information.

To see only the spells you could actually put in a slot - the right tradition, at a rank you can cast - use `spell/eligible <level>`, or `spell/eligible` on its own to see which traditions you draw on.