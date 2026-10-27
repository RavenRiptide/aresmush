---
toc: Pathfinder Second Edition
summary: Playtest-only commands - approve your own character, and award yourself XP and gold.
aliases:
- playtest
- selfapprove
- selfaward
---

# Playtest Commands

These commands let you build a character, approve it, and take it to any level without waiting on staff. They work only during the playtest. When the playtest ends, staff turn them off and go back to approving characters and awarding XP themselves.

## Approving your character

`selfapprove`: Approves your own character.
%t **Note:** Submit your application with `app/submit` first; `selfapprove` refuses a character with no application.

You need an approved character to use `roll`, `roll/alias`, `selfaward/gold`, and the other commands that are for approved characters only.

## Awarding yourself XP

`selfaward/xp <amount>`: Awards your character `<amount>` XP.
`selfaward/xp me=<amount>`: Awards your character `<amount>` XP, the same as `selfaward/xp <amount>`.
%t **Note:** You can award XP only to yourself. A negative `<amount>` takes XP away.

Spend the XP with `advance` to raise your character a level. See `help advancement`.

## Claiming level wealth

`selfaward/gold`: Gives your character the gold a new character of a higher level starts with, as according to GM Core's Treasure for New Characters table.
%t **Note:** Your character must be approved first before you can use this command. Additionally, a 1st-level character has nothing to claim, since they get 15 gold immediately upon approval.

The amounts come from Treasure for New Characters in GM Core: 30 gp at 2nd level, 270 gp at 5th, 2,300 gp at 10th, and so on up, to 112,000 gp at 20th. Claim your gold after you advance to your destination level.

Spend your gold with `buy`. See `help vendor`.
