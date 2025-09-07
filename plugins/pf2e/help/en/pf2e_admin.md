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

`admin/set <character>/<keyword> = <value>`

Keyword can be one of: feat skill spellbook repertoire ability feature focus divine font

The syntax of `<value>` depends on the keyword.

For feats: `<feat type> [add|delete] <feat name>`

where feat type is one of: ancestry charclass skill general archetype dedication

For skills: `<skill name> <proficiency level>`

where proficiency level is one of: untrained trained expert master legendary

For spellbook or repertoire: `<charclass> [add|delete] <spell name> <spell level>`

For ability: `<ability name> <new value>` Value needs to be an integer, command will charf if not

For feature: `[add|delete] <feature name>`

For focus: `add|delete <charclass> cantrip|spell <spell name>`

For divine font: `heal|harm`

(Validate all data)

`admin/reset <character>`: Resets the character sheet, sets them to unapproved, forces them back through chargen, and wipes level / XP / gold back to starting default. 

`admin/respec <character>`: Resets the character sheet, sets them to unapproved, forces them back through chargen, but preserves level / XP / money / inventory. 

For gear runes:

`etch/potency <Character>=<Category>/<Item Number>/<Potency Level>`
`etch/striking <Character>=weapons/<Item Number>/<Striking Level>`
`etch/resilient <Character>=armor/<Item Number>/<Resilient Level>`
`etch/property <Character>=<Category>/<Item Number>/<Rune Name`

The first three have valid values of 0 to 3, while the third takes any string as a rune name (for now) and acts as a toggle, meaning repeating the command will set it or remove it.

