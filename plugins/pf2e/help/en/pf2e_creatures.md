---
toc: Pathfinder Second Edition
summary: Saved creatures - your own, kept to add to an encounter by name.
aliases:
- creature
- creatures
- custom creatures
---

# Saved creatures

A creature you save is kept, to add to an encounter by name as one from the bestiary is. Anyone may save
one. A Plotmaster or an admin adds their own as they stand, and those another Plotmaster or admin shares
with them. Anyone else adds a saved creature once an admin has approved it, and approval makes it anyone's
to add.

Each change you save is a new revision of it. An encounter keeps the revision a creature was added as, so
changing it later changes no fight that has it.

## Making one

`creature/save <name>=<description>` - Saves a creature from a one-line description, in the words `+e/add`
reads (see `help encounters`): `creature/save Barrow Hound=ac 18 hp 40 level 3; strike jaws +11 1d10+5 piercing`.
Saving again under a name you already have makes a new revision of it.
`creature/save <name>=#<id>` - Saves a creature from the encounter you run here.
`creature/clone <creature>=<new name>` - A copy of a bestiary creature, or a saved one you may see, to change.

A saved creature may not take a bestiary creature's name, and its name may not hold `=`, `;`, `#` or `/`.
One that the game could not fight with - no AC, a damage formula it cannot read - is not saved.

## Changing one

`creature/set <name>=<part>` - Changes one part, in the same words: `=ac 19 hp 45`,
`=strike jaws +12 2d8+5 piercing`, `=weak fire 5`, `=traits undead`. A Strike or ability of a name it has is
replaced; a weakness, resistance, immunity, skill, sense or trait is added.
`creature/unset <name>=<part>` - Takes one off: `=strike jaws`, `=ability grave howl`, `=weak fire`, `=trait undead`.
`creature/rename <name>=<new name>`
`creature/notes <name>=<notes>` - Your own notes on it, which are no part of its stat block.
`creature/describe <name>` - The line that makes it again, and what a line cannot hold - spellcasting, an
ability's traits - which stays only in the saved creature.

## On the web

The portal's creature pages (`/pf2/creatures`) do all of this with a form: the library of your own, those
shared with you, the published ones and the bestiary; a new creature from one that exists, from a
description or blank; an editor that checks the creature as you change it and shows what the game will run
of each Strike and ability; and for admins, the queue of what awaits approval.

## Seeing them

`creature/list [mine|shared|published|all][/<level>]` - The saved creatures you may see.
`creature <creature>` - Its stat block, whose it is, and where it stands: a draft, submitted, published or retired.
`creature/history <name>` - Its revisions, and who did what to it.
`creature/check <creature>` - What would keep it from being saved, what is warned of, and where each figure
sits for its level in GM Core's tables: extreme, high, moderate, low or terrible. A figure above the highest
is flagged to you and to the admins who approve it, and is not refused.
`+e/bestiary <words>` lists the saved creatures you may add beside the bestiary's.

A creature is named by its name, or by `c:<id>` - `creature c:12`, `+e/add c:12` - which reaches only saved
creatures. A bestiary name always means the bestiary's creature.

## Sharing and approval

`creature/share <name>=<character>[,<character>...]` - Lets those Plotmasters or admins add it as it
stands. `=plotmasters` shares it with every Plotmaster; `=private` with nobody. A share reaches only a
Plotmaster or an admin.
`creature/unshare <name>=<character>`
`creature/submit <name>[=<note>]` - Asks an admin to approve its latest revision. Once approved, anyone may
add it, and it is that revision they get; what you change after waits for the next approval.
`creature/withdraw <name>` - Takes the request back.
`creature/retire <name>`, `creature/restore <name>` - Off the lists and out of use, or back. A published
creature is retired only by an admin.

## For admins

`creature/queue` - What awaits approval, with what changed since it was last published.
`creature/approve <creature>` - Publishes the submitted revision for everyone.
`creature/reject <creature>=<reason>` - Sends it back; its author reads the reason on it.
`creature/unpublish <creature>` - Takes it out of use for everyone but whoever may use it unapproved.

Every approved creature is also written to `game/bestiary/house.yml`, to keep with the game.
