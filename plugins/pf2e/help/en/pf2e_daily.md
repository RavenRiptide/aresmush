---
toc: Pathfinder Second Edition
summary: Resting in an encounter.
aliases:
- rest
- refocus
- daily
---

# Resting

Rests aren't tied to real time. A scene can cover a minute or weeks, so the GM decides when a night passes by using `encounter/rest` in an encounter.

`encounter/rest [<who>,<who>...]`: Declares that a night has passed for everyone in the encounter, or only for the characters you name. Each character recovers a night's worth of Hit Points and gets back their once-a-day uses, a full focus pool, the day's spells from what they prepared, an alchemist's versatile vials and prepared items, and their invested items. Anything lasting less than a day, such as most effects, ends, and anything measured in days has one night taken off its duration. Each character's daily choices unlock so they can choose again (see `help daily_choices`).
%t **Note:** Only the GM can use this. The GM can rest characters as often as the story needs, and can reverse an accidental rest with `encounter/undo`.
`encounter/reprepare <who>`: Unlocks the daily choices a character's Ultimate Flexibility or Radiant Armament lets them make again without a rest (see `help daily_choices`).
%t **Note:** Only the GM can use this.
`encounter/gather <who>[=<periods>]`: Gives an alchemist back the versatile vials they gather in the number of 10-minute periods you name, one if you don't.
%t **Note:** Only the GM can use this.
`encounter/refocus [<who>]`: Performs the Refocus activity, which restores a Focus Point (or more, if you have certain feats) when your focus pool isn't full. The GM can refocus anyone.

An encounter can continue from an earlier one (see `help encounter_runner` or [read it on the web](/help/pf2e_encounter_runner)). Anyone who was in both encounters starts the new one in the same state they left the old one, so several encounters can make up a single day until the GM rests the group. Resting never changes your own sheet; it only restores what an encounter used up.
