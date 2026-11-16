---
toc: Pathfinder Second Edition - Advancement
summary: Commands related to advancement and archetypes.
aliases:
- advancearchetypes
- advancededications
---

# Advancement - Archetypes and Dedications

See `help advance` for more information about advancement.

## Selecting Archetypes

Starting at level 2, you can spend a class feat on a Dedication feat, which enters you into that feat's archetype. Before you can take another Dedication feat, you must take two more feats from that archetype. For more information about archetypes, see [Archetypes & Dedications](/wiki/mechanics:archetypes-dedications).

**Commands**:
`advance/feat charclass=<feat name>`: Selects the Dedication or archetype feat you specify (`<feat name>`).
`advance/archetype specialty=<specialty>`: Selects a specialty for your archetype, if it offers any.
`advance/archetype specialtychoice=<choice>`: Selects the choice your archetype's specialty offers. Only the barbarian archetype's animal and dragon instincts and the sorcerer archetype's elemental and draconic bloodlines offer one.
`advance/archetype deity=<deity>`: Selects a deity for your archetype. Only the cleric and champion archetypes need one.
%t **Note:** If you set a deity in character generation, the game uses that deity for your archetype, and you don't need this command.
`advance/archetype key ability=<key ability>`: Selects your archetype's key ability (`<key ability>`), for archetypes that offer a choice.
`advance/archetype sanctification=<sanctification>`: Selects a sanctification for your archetype. Only the cleric and champion archetypes use one.

When an archetype, its specialty, or its deity gives you training in a skill you're already trained in, you get an open skill slot instead. To fill it, train an untrained skill with `advance/raise skill`. For more information about raising skills, see `help advanceskills`.

## Archetype Spells

If your class casts spells and your archetype gives you spellcasting too, learn your archetype's spells by adding the archetype's name to `advance/spell`. If your class doesn't cast spells, use the regular spell commands. For more information about the regular spell commands, see `help advancespells`.

**Commands**:
`advance/spell repertoire/<archetype name>/<level>=<spell name>`: Adds a spell (`<spell name>`) of the rank you specify (`<level>`) to your archetype's repertoire. `<archetype name>` is the archetype's full name, such as `oracle archetype`.
`advance/spell spellbook/<archetype name>/<level>=<spell name>`: Adds a spell (`<spell name>`) of the rank you specify (`<level>`) to your archetype's spellbook.
%t **Examples**:
%t `advance/spell repertoire/oracle archetype/cantrip=Stabilize`: Adds the Stabilize cantrip to your oracle archetype's repertoire.
%t `advance/spell spellbook/wizard archetype/cantrip=Light`: Adds the Light cantrip to your wizard archetype's spellbook.
