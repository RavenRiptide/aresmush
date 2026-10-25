---
toc: Pathfinder Second Edition - Admin
summary: Staff commands for approving and managing custom creatures.
aliases:
- pf2eadmin_creatures
- pf2eadmin creatures
- admincreatures
---

# Pathfinder 2E -- Admin Commands for Custom Creatures

Staff review the custom creatures that players submit for approval, and manage creatures once they're published. For creating, sharing, and submitting custom creatures, see `help creatures`.

## Reviewing submissions

When a player submits a creature, staff are notified, and a job opens in the request category, where you can discuss the creature with its author.

`creature/queue`: Lists the creatures awaiting approval. For each creature, it shows what changed since it was last published, and whether the author asked for approval for their own plots only.
`creature/approve <creature>`: Approves the submitted revision and publishes it, either for everyone or for the author's own plots, depending on what the author requested.
`creature/reject <creature>=<reason>`: Sends the creature back to its author, who can then review your `<reason>` for rejection.
%t **Note:** Approving or rejecting a creature closes its job.

## Managing published creatures

`creature/unpublish <creature>`: Takes a published creature out of use. Afterward, only people who could use the creature without approval (such as Plotmasters and staff) can still add it to an encounter.
`creature/retire <creature>`: Retires a creature, including public creatures. The creature is hidden from lists and can't be added to encounters. `creature/restore <creature>` brings it back.
`creature/owner <creature>=<character>`: Transfers ownership of the creature to `<character>`. Use this for a published creature whose author's character was deleted, or when an author wants to hand a creature over to someone else.
`creature/purge <creature>`: Permanently deletes the creature, along with its revisions and history.
%t **Note:** You can't purge a creature while an encounter that hasn't been deleted still uses it, because that encounter keeps the creature as it was added. Retire the creature in the meantime so nobody adds it to a new encounter.

## The house bestiary

The game also writes every public creature to `game/bestiary/house.yml`, so published creatures are kept with the game files. If the game can't write the file, the approval still stands, and the file is written again at the next approval.

## On the web

You can do all of the commands listed in this file instead through the web portal's [Creature Builder](/pf2/creatures). Its [approval queue](/pf2/creatures/queue) lists the creatures awaiting approval.