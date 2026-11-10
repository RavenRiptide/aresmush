---
toc: Pathfinder Second Edition - Admin
summary: Admin commands to manipulate the character sheet.
aliases:
- pf2estaff_sheet
- pf2eadmin_sheet
---

# Pathfinder 2E -- Admin Commands for Character Sheets

Staff can make some modifications to characters' sheets.

### Setting attributes
**Command**:
`admin/set <character>/attribute = <attribute name> <attribute score>`

**Key**:
`<character>`: The character's name.
`<attribute name>`: The name of the attribute. For example, Charisma.
`<attribute score>`: The score behind the modifier the sheet shows. A score of 10 is +0, and each 2 points add 1, so 18 is +4. An odd score above 18 is a partial boost, which the sheet marks (P): 19 is +4 (P). Attribute boosts the character earns at later levels still apply on top of it, so setting a score at 1st level does not freeze it.

### Setting character features
**Command**:
`admin/set <character>/feature = [add|delete] <feature name>`

**Key**:
`<character>`: The character's name.
`[add|delete]`: Choose `add` to add a feature; `delete` to delete a feature.
`<feature name>`: The name of the feature.

### Setting a chosen option for a feat or class feature
**Command**:
`admin/set <character>/choice = <feat or choice>: <what was chosen>`: Sets a choice for a character's feat or class feature with a choice to choose.
`admin/set <character>/choice = delete <feat or choice>: <what was chosen>`: Deletes a choice for a character's feat or class feature with a choice to choose.

**Key**:
`<character>`: The character's name.
`<feat or choice>`: The feat or class feature the choice is for, as it appears on the character's sheet, such as `Assurance` or `Domain Initiate`.
`<what was chosen>`: The option the character picked, such as `Arcana` or `Family`.

### Setting skills
**Command**:
`admin/set <character>/skill = <skill name> <proficiency level>`

**Key**:
`<character>`: The character's name.
`<skill name>`: The name of the skill to train, or a lore ending in `Lore`.
`<proficiency level>`: `untrained`, `trained`, `expert`, `master`, `legendary`

### Setting languages
**Command**:
`admin/set <character>/language = [add|delete] <language>`

Players can spend RPP to learn a common, uncommon, or rare language. Spend the RPP with `rpp/spend` first, then add the language with this command. Spending RPP is the only way a character can learn a rare language. Secret languages cannot be bought with RPP: specific game features grant some of them, such as the druid's Wildsong, and the rest are not available to player characters. A language you add stays on the sheet through any rollback.

**Key**:
`<character>`: The character's name.
`[add|delete]`: Choose `add` to teach the character a language; `delete` to remove one they know.
`<language>`: The language's name. Use `lang/info <type>` to see each type's languages, where `<type>` is `common`, `uncommon`, `rare`, or `secret`.

### Changing feats
Feats cannot be set directly. To change a character's feats, use `admin/rollback` to send them back to the level where the choice was made and let them redo it, or `admin/respec` to let them rebuild the character from scratch while keeping their XP.

### Rolling a character back to an earlier level
**Command**:
`admin/rollback <character> = <level>`: Puts a character back to just before the level you name, so they can make that level's choices again with `advance`. Everything they chose at that level and above is set aside, the XP those levels cost is refunded, and they are told in-game (if they are connected).
`admin/unrollback <character>`: Undoes the last rollback on the character and puts the choices back exactly as they were, which is the command to reach for if you rolled back the wrong person or the wrong level.

Two things a rollback deliberately leaves alone:
- **Boons** granted outside the leveling process. A boon that takes effect at a level the character no longer has goes quiet until they level back up to it, while a boon granted with no level at all is never touched.
- **A character part-way through an advancement.** They have to finish it with `advance/done` or abandon it with `advance/reset` first, or their in-progress choices would be lost.

**Key**:
`<character>`: The character's name.
`<level>`: The level to send them back to redo. Must be 2 or higher.

### Setting alignment and deity
**Command**:
`admin/set <character>/alignment = <alignment>`
`admin/set <character>/deity = <deity>`

%xrWARNING%xn:
- Do not use these commands on a character with the Champion class or a character with the Champion Archetype, due to how their class works.
- Do not use the deity command to change a Cleric's deity or a character with the Cleric Archetype's deity, due to how their class works.
Offer respecs to these characters instead if they want to redo their sheet!

**Key**:
`<character>`: The character's name.
`<alignment>`: Alignment code (such as, `OT`, `BT`, or `WT`).
`<deity>`: The deity's name.

### Adding formulas
**Command**:
`formulas/add <character> = <category>/<item>`: Give a character a formula.
`formulas/remove <character> = <category>/<item>`: Take one away.
%t **Note:** You can add formulas only for an approved character.

**Key**:
`<character>`: The character's name.
`<category>`: The item category. See `help vendor` for category types.
`<item>`: The name of the item for the formula.

### Unlocking uncommon and rare spells
**Command**:
`admin/access <character>`: Lists the uncommon and rare spells unlocked for the character.
`admin/access <character>/spell = <spell>`: Unlocks an uncommon or rare spell, so the character can learn it the usual way: with a spell pick when they level up, or with `spell/learn` for a spellbook.
`admin/unaccess <character>/spell = <spell>`: Takes back an unlock.
%t **Note:** Taking back an unlock doesn't remove a spell the character already learned. It only stops them learning it again.

Players spend RPP through a request to unlock an uncommon or rare spell. Spend the RPP with `rpp/spend` first, then unlock the spell with this command. You can unlock spells only for an approved character. An unlock stays on the sheet through any rollback.

**Key**:
`<character>`: The character's name.
`<spell>`: The spell's name.

### Uncommon and rare items
Players can buy common items from the vendor. They can also buy an uncommon or rare item there when a feat, class feature, or class names it, such as Khazadi Weapon Familiarity or a cleric's uncommon favored weapon. Players get any other uncommon or rare item through requests: they buy its formula with RPP and money, which you record with `formulas/add`, and then request to have the item crafted for themselves or another character.
### Wands
`wand/repair <character>=<number>`: Repairs a wand that overcharging broke, on the character's own sheet. The number is the wand's number in their `gear` list.
%t **Note:** If the wand is in an encounter with them, the GM repairs it there with `encounter/repair <who>=<number>`.
