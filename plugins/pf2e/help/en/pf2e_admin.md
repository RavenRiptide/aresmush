---
toc: Pathfinder Second Edition
summary: Admin commands to manipulate the character sheet.
aliases:
- pf2e staff
- pf2 staff
- pf2 admin
---

# Pathfinder 2E -- Admin Commands

Game admins and those they designate can make some modifications to characters' sheets. 

## Setting ability scores
**Command**:
`admin/set <character>/ability = <ability name> <ability score>`

**Key**:
`<character>`: The character's name.
`<ability name>`: The name of the ability. For example, Charisma.
`<ability score>`: The number to set the score to.

## Setting character features
**Command**:
`admin/set <character>/feature = [add|delete] <feature name>`

**Key**:
`<character>`: The character's name.
`[add|delete]`: Choose `add` to add a feature; `delete` to delete a feature.
`<feature name>`: The name of the feature.

## Setting skills
**Command**:
`admin/set <character>/skill = <skill name> <proficiency level>`

**Key**:
`<character>`: The character's name.
`<skill name>`: The name of the skill to train.
`<proficiency level>`: `untrained`, `trained`, `expert`, `master`, `legendary`

## Setting feats
**Command**:
`admin/set <character>/feat = <feat type> [add|delete] <feat name>`

**Key**:
`<character>`: The character's name.
`<feat type>`: `ancestry`, `charclass`, `skill`, `general`, `archetype`, `dedication`
`[add|delete]`: Choose `add` to add a feat; `delete` to remove a feat.
`<feat name>`: The name of the feat.

## Setting spellbook or repertoire spells
**Command**:
`admin/set <character>/[spellbook|repertoire] = <charclass> [add|delete] <spell name> <spell level>`

**Key**:
`<character>`: The character's name.
`[spellbook|repertoire]`: Choose `spellbook` for prepared casters; `repertoire` for spontaneous casters.
`[add|delete]`: Choose `add` to add a spell; `delete` to remove a spell.
`<spell level>`: The level of the spell. Needs to be a number from 1-10.

## Setting spellbook or repertoire spells
**Command**:
`admin/set <character>/[spellbook|repertoire] = <charclass> [add|delete] <spell name> <spell level>`

**Key**:
`<character>`: The character's name.
`[spellbook|repertoire]`: Choose `spellbook` for prepared casters; `repertoire` for spontaneous casters.
`<charclass>`: The character's class.
`[add|delete]`: Choose `add` to add a spell; `delete` to remove a spell.
`<spell name>`: The name of the spell.
`<spell level>`: The level of the spell. Needs to be a number from 1-10.

## Setting focus spells and cantrips
**Command**:
`admin/set <character>/focus = [add|delete] <charclass> [cantrip|spell] <spell name>`

**Key**:
`<character>`: The character's name.
`[add|delete]`: Choose `add` to add a focus cantrip/spell; `delete` to remove a focus cantrip/spell.
`<charclass>`: The character's class.
`[cantrip|spell]`: Choose `cantrip` to add a focus cantrip; `spell` to add a focus spell.
`<spell name>`: The name of the spell.

## Setting divine fonts
**Command**:
`admin/set <character>/divine font = [heal|harm]`

**Key**:
`<character>`: The character's name.
`[heal|harm]`: Choose `heal` to set healing font; choose `harm` to set harming font.

## Etching runes
**Commands**:
`etch/potency <character>=<category>/<item number>/<potency level>`
`etch/striking <character>=weapons/<item number>/<striking level>`
`etch/resilient <character>=armor/<item number>/<resilient level>`
`etch/property <character>=<category>/<item number>/<rune name>`

**Key**:
`<character>`: The character's name.
`<category>`: `weapons` or `armor`. Case-sensitive.
`<item number>`: The number of the item in the character's inventory.
`<potency level>`: The level of the Potency rune, as a number. Acceptable values: 0-3
`<striking level>`: The level of the Striking rune, as a number. Acceptable values: 0-3
`<resilient level>`: The level of the Resilient rune, as a number. Acceptable values: 0-3
`<rune name>`: The name of the rune; can be any string of words (for now). 

To remove the name of a Property rune from an item, repeat the command that added the rune name.

## Reset or respec a character
**Commands**:
`admin/reset <character>`: Resets the character sheet, sets them to unapproved, forces them back through chargen, and wipes level / XP / gold back to starting default. 
`admin/respec <character>`: Resets the character sheet, sets them to unapproved, forces them back through chargen, but preserves level / XP / money / inventory. 
