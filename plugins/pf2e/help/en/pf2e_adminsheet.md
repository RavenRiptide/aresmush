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

### Retraining a feat
**Command**:
`admin/retrain <character> = <old feat>/<new feat>`: Swaps a feat the character has for another in the same slot.
%t **Note:** The new feat must be the same type as the old one, no higher than the level of the slot, and the character must meet its prerequisites at that level. You can't retrain a feat other feats need, so retrain those first.
%t **Note:** Some feats say they can't be retrained into or out of, such as Hag Claws, and `admin/retrain` refuses them.
%t **Note:** `admin/retrain` can't open a new feat's own grants or choices, or take back an old feat's grants other than the feats it gave. For those, use `admin/rollback` to send the character back to the level where they chose the feat.

A retrain in a slot from 2nd level or higher belongs to that level, so rolling the character back past that level puts the old feat back. A retrain in a 1st-level slot stays through any rollback.

**Key**:
`<character>`: The character's name.
`<old feat>`: The feat to retrain out of.
`<new feat>`: The feat to retrain into.

### Approving familiars
**Command**:
`familiar/approve <character>`: Approves the character's familiar's name, species, and form, and closes its approval request.
`familiar/reject <character> = <reason>`: Sends the details back with your reason, in the approval request, which stays open.
%t **Note:** Approving a character's application approves their familiar's details with it. If the details are incomplete, an approval request opens for the character to finish them.
%t **Note:** A character whose familiar is awaiting approval can't advance, and only the familiar's spells work.
`familiar/cantrip <character> = <old cantrip>/<new cantrip>`: Changes a cantrip that the character's Cantrip Connection adds to their repertoire, as retraining it, such as `familiar/cantrip Morwen = Shield/Light`.
%t **Note:** A repertoire caster chooses the cantrip the first time they choose Cantrip Connection, and the game keeps it on later days. Only this command changes it.

For more information about familiars, see `help familiars`.

### Approving animal companions

`companion/approve <character>`: Approves the character's animal companion's name, and closes its approval request.
`companion/reject <character> = <reason>`: Sends the name back with your reason, in the approval request, which stays open.
%t **Note:** Approving a character's application approves their companion's name with it. If the companion has no name or type yet, an approval request opens for the character to finish it.
%t **Note:** A companion awaiting approval doesn't stop its character from advancing.
`companion/dead <character>`: Marks the character's animal companion as dead. It can't join encounters until you revive it or approve a replacement.
`companion/revive <character>`: Marks a dead companion alive again, exactly as it was, such as after it's raised or reincarnated.
%t **Note:** Approving a replacement of a new type rewrites the character's old companion choices at the levels they made them, so a later rollback treats each new choice as that level's.
%t **Note:** If a replacement can't wear something the old companion wore, such as barding of the wrong size, it comes off and goes back to the character's inventory. The request's closing comment tells the player.
`companion/wear <character>=<category>=<item number>`: Puts an item from the character's inventory on their animal companion, including an item without the companion trait, such as `companion/wear Rowan=gear=5`. The barding and investiture limits still apply.
`companion/remove <character>=<category>=<item number>`: Takes an item off the character's animal companion and puts it back in their inventory.

For more information about animal companions, see `help companions`.

### Changing feats
To change a feat in a way `admin/retrain` can't, use `admin/rollback` to send the character back to the level where they made the choice and let them redo it, or `admin/respec` to let them rebuild the character from scratch while keeping their XP.

### Rolling a character back to an earlier level
**Command**:
`admin/rollback <character> = <level>`: Puts a character back to just before the level you specify, so they can make that level's choices again with `advance`. Everything they chose at that level and above is set aside, the XP those levels cost is refunded, and they are told in-game (if they are connected).
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

### Giving items
`item/give <character>=<category>/<name>`: Creates an item and gives it to the character, and takes the item's catalog price from their money. Use this to give the item a commission crafting request made, such as `item/give Alice=magicitem/Charm of Resistance`.
`item/give <character>=magicitem/<name>/<deity>`: Gives an item made for one deity, such as a Helm of Zeal, made for the deity you specify, such as `item/give Alice=magicitem/Helm of Zeal/Althea`.
`item/give <character>=<category>/<name>/<material>/<grade>`: Gives a weapon, armor, or shield made of a precious material, at the grade you specify (low, standard, or high), and takes its price, such as `item/give Alice=weapons/Longsword/adamantine/standard`. It doesn't spend the RPP an uncommon or rare material costs at the vendor; spend RPP for a request with `rpp/spend`.
`item/give/force <character>=<category>/<name>`: Gives an item above the character's level, and still takes its price.
`item/give/free <character>=<category>/<name>`: Gives an item without taking any money and without checking its level, such as loot or a reward.
%t **Note:** `item/give` refuses an item above the character's level, a character who can't afford the item, a character who isn't approved, and a character in a running encounter. Give the item after the encounter ends.
%t **Note:** `item/give` doesn't check the crafter's feat or formula, because the crafter is usually another character. Check those against the request before you give the item.

### Wands
`wand/repair <character>=<number>`: Repairs a wand that overcharging broke, on the character's own sheet. The number is the wand's number in their `gear` list.
%t **Note:** If the wand is in an encounter with them, the GM repairs it there with `encounter/repair <who>=<number>`.
