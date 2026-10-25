---
toc: Pathfinder Second Edition
summary: Creating and using your custom creatures.
aliases:
- creature
- creatures
- customcreatures
- customcreaturelibrary
- creaturelibrary
---

# Custom Creature Library

You can add a custom creature to an encounter by name, just like a creature from the bestiary. Anyone can create a custom creature, but who can add it to an encounter depends on the creature:

- **Plotmasters and staff** can add their own custom creatures to their encounters, plus any that another Plotmaster or staff member has shared with them.
- **Everyone else** can add a custom creature to an encounter once staff approves it.
- **A creature approved "for your own plots"** can only be added to an encounter by its author and the people the author shares it with.

Each time you save a creature, you create a new revision of it. An encounter keeps the revision it was added with, so later changes don't affect fights that already include the creature.

## Making a custom creature

`creature/save <name>=<description>`: Creates or updates a custom creature from a one-line description, written the same way `encounter/add` reads it (see `help encounter_creatureimport`): `creature/save Barrow Hound=ac 18 hp 40 level 3; strike jaws +11 1d10+5 piercing`.
%t **Note:** Saving a creature again under a name you already have creates a new revision of it.
`creature/save <name>=#<id>`: Saves a combatant from an encounter you're running as a custom creature called `<name>`.
`creature/clone <creature>=<new name>`: Copies a bestiary creature, or a custom creature you can see, under a new name so you can change it.

**Notes**:
- A custom creature can't use a bestiary creature's name, and its name can't contain `=`, `;`, `#`, or `/`.
- The game won't save a creature it couldn't fight with, such as one with no AC or a damage formula it can't read.

## Creating and editing a custom creature

`creature/new <name>=<level> <road map>`: Creates a creature from one of [GM Core's road maps](https://2e.aonprd.com/Rules.aspx?ID=2874): brute, magical striker, skill paragon, skirmisher, sniper, soldier, or spellcaster. The road map sets each statistic it names to the recommended value for the creature's level, and sets every other statistic to moderate. The new creature has one placeholder Strike for you to rename and fill in, plus a spell DC and spell attack if it's a spellcaster. Use `creature/check` to see where each statistic falls.
`creature/set <name>=<part>`: Changes one part of the creature's stat block, written the same way as in a description, such as `=ac 19 hp 45`, `=strike jaws +12 2d8+5 piercing`, `=weak fire 5`, or `=traits undead`. If the creature already has a Strike or ability with that name, the new one replaces it. A weakness, resistance, immunity, skill, sense, or trait is added to the ones the creature already has.
`creature/unset <name>=<part>`: Removes one part of the creature's stat block, such as `=strike jaws`, `=ability grave howl`, `=weak fire`, or `=trait undead`.
`creature/set <name>=shape <shape>`: Sets the shape the creature starts a fight in, chosen from the shapes its abilities give it. For example, `creature/set <name>=shape animal` makes a custom werewolf always start a fight as a wolf.
`creature/unset <name>=shape`: Makes the creature start a fight in its stat block's default shape again.
`creature/rename <name>=<new name>`: Renames the creature.
`creature/notes <name>=<notes>`: Adds your own notes to the creature. The notes aren't part of its stat block.
`creature/describe <name>`: Shows the one-line description that recreates the creature, and lists anything the description can't hold (such as spellcasting or an ability's traits). Those parts are kept only in the saved creature.

## On the web

The web portal's [Creature Builder](/pf2/creatures) does all of this with a friendly user interface. From the Creature Builder, you can view your own custom creatures, custom creatures shared with you, published creatures shared with the playerbase, and the bestiary. You can start a new creature from an existing one, from a description, or from scratch. The editor checks the creature as you work and shows what the game will do with each Strike and ability.

## Reviewing creatures

`creature/list [mine|shared|published|all][/<level>]`: Lists the custom creatures you can see: your own (`mine`), the ones shared with you (`shared`), the published ones (`published`), or all of them (`all`). Add `/<level>` to list only creatures of that level.
`creature <creature>`: Shows the creature's stat block, its owner, and its status: draft, submitted, approved for its author, published, or retired.
`creature/history <name>`: Lists the creature's revisions, and who made each change.
`creature/check <creature>`: Checks a creature for errors and warnings, and shows where each statistic falls for its level in GM Core's tables for building creatures: extreme, high, moderate, low, or terrible.
%t **Note:** If a statistic is above the highest value in the tables, it's flagged for you and for staff to review, but you can still save or submit the creature.
`encounter/bestiary <words>`: Lists the bestiary creatures and custom creatures you can add to an encounter whose names contain `<words>`.

You can refer to a creature by its name, or by its ID as `c:<id>` (such as `creature c:12` or `encounter/add c:12`). The `c:<id>` form only matches custom creatures, and a bestiary creature's name always means the bestiary creature.

## Sharing and approval

`creature/share <name>=<character>[,<character>...]`: Shares your creature (`<name>`) with a specified person (`<character>`). Alternatively, `creature/share <name>=plotmasters` shares your creature with Plotmasters. `creature/share <name>=private` makes your creature private.
%t **Note:** An unapproved creature can only be shared with Plotmasters and staff. You can share an approved custom creature with anyone (such as a co-GM), and they can add the approved version of the creature to their encounters.
`creature/unshare <name>=<character>`: Stops sharing your creature with that person. `creature/unshare <name>=plotmasters` stops sharing it with Plotmasters.
`creature/submit <name>[=<note>]`: Submits the latest revision of your creature to staff for approval, with an optional note. Once staff approves it, anyone can add that revision of your creature to their encounters.
%t **Note:** Changes you make after approval need to be approved again.
`creature/submitown <name>[=<note>]`: Submits your creature to staff for approval for your own plots only. Once staff approves it, you and the people you share it with can add the approved version to your encounters. Nobody else can see it.
%t **Note:** Submitting a creature opens a job where you and staff can discuss it. The job closes when staff approves or rejects the creature, or when you withdraw the request.
`creature/public <name>`: Makes your creature that was approved for your own plots public, so anyone can add the approved version to their encounters. It doesn't need another approval from staff.
`creature/withdraw <name>`: Withdraws your approval request.
`creature/retire <name>`: Retires your creature: it's hidden from lists and can't be added to encounters.
%t **Note:** Only staff can retire a public creature.
`creature/restore <name>`: Brings back a creature you retired.
