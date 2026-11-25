---
toc: Pathfinder Second Edition
summary: Choosing, naming, advancing, and equipping your animal companion.
aliases:
- companion
- companions
- animal_companion
- animal_companions
- companion_name
- nimble
- savage
- specialization
- specializations
- faithful_steed
- bonded_animal
- companion_replace
- replace_companion
- dead_companion
- companion_wear
- companion_remove
- companion_gear
- barding
---

# Animal Companions

Some feats and class features give you an animal companion, such as Animal Companion, Faithful Steed, and the druid's animal order. A character can have only one animal companion, and can't have both an animal companion and a bonded animal.

## Choosing Your Companion

`cg/info <feat>`: Lists the companion types you can choose with the feat you specify (`<feat>`), such as `cg/info Animal Companion`.
`cg/option <feat>=<type>`: Chooses your companion's type in chargen, such as `cg/option Animal Companion=Wolf` or `cg/option Faithful Steed=Horse (Large)`. Use the name of the feat that gave you the companion.
%t **Note:** A horse comes in two sizes, so you choose `Horse (Medium)` or `Horse (Large)`. Faithful Steed offers only mounts.
%t **Note:** For each type's stats, see the Animal Companions page on the wiki.
`advance/info <feat>`: Lists what you can choose with a companion feat you take while advancing, such as `advance/info Incredible Companion (Druid)`.
`advance/option <feat>=<choice>`: Chooses your companion's type when a level gives you a companion, nimble or savage when you take Incredible Companion, or a specialization when you take Specialized Companion, such as `advance/option Incredible Companion (Druid)=Savage`.

## Naming Your Companion

`companion/name <name>`: Names your companion, such as `companion/name Ash`. Staff approve the name.
%t **Note:** A name is one word, like a character's name: it starts with a letter, can use only the letters A to Z, apostrophes, and hyphens, and is 2 to 30 characters long. It can't be a restricted name, another character's name, or your familiar's name.
%t **Note:** In chargen, staff approve your companion's name with your application. When a level gives you a companion, an approval request opens when you finish the level. After your companion is approved, a new name opens an approval request, and your companion keeps its approved name until staff approve the new one.

## Reviewing Your Companion

`sheet/companion`: Shows your companion's sheet: its type, stats, attacks, support benefit, and advanced maneuver. Until staff approve your companion, the sheet also shows what's waiting for approval.
`sheet/companion <character>`: Shows another character's companion, such as `sheet/companion Rowan`. Like every sheet, a companion's sheet is open to anyone.
`cg/review`: Shows your companion's name and type while you build your character, and reminds you to name it.
`advance/review`: Shows what the level changes about your companion, such as its size, attributes, and attacks when it becomes savage.

## Companion Gear

Your companion can wear barding and items with the companion trait, such as a collar of empathy or alacritous horseshoes. Buy them as you would anything else, then put them on your companion from your inventory.

`companion/wear <category>=<item number>`: Puts the item numbered `<item number>` in `<category>` on your companion, such as `companion/wear gear=3` for barding or `companion/wear magicitem=1` for a collar. Your companion invests an item with the invested trait as it puts the item on.
`companion/remove <category>=<item number>`: Takes the item off your companion and puts it back in your inventory, uninvested.
%t **Note:** Your companion can wear one barding, and can have two items invested. Barding fits only the sizes in its name, and horseshoes fit only a four-legged companion.
%t **Note:** An item your companion wears stays in your `gear` list, marked with your companion's name, but its Bulk doesn't count toward yours. You can't sell it, store it in a bag, or invest it yourself until you take it off.
%t **Note:** A companion can never activate an item, so you activate a companion item's abilities yourself with `use`, such as barding of the zephyr's Take Flight.
%t **Note:** When your companion grows too big for its barding, the barding comes off and goes back to your inventory. `advance/review` warns you before you finish the level.
%t **Note:** `sheet/companion` shows what your companion wears, and its barding's effect on its AC and Speed.

## Companions in Encounters

`encounter/companion`: Brings your companion into the encounter you're in. For more information about animal companions in encounters, see `help encounter_companion`.

## Replacing Your Companion

When your companion dies, or you part ways with it, you can bring in a new one. Staff approve the new companion, and until they do, your old companion stays on your sheet.

`companion/replace`: Starts replacing your companion with a new animal of the same type, which keeps your old companion's choices, such as nimble or savage. Name the new companion with `companion/name`.
`companion/replace <type>`: Starts replacing your companion with an animal of the type you specify, such as `companion/replace Bear`. Name the new companion with `companion/name`.
`companion/replace/option <feat>=<choice>`: Makes one of your companion's choices again for a companion of a new type, such as `companion/replace/option Incredible Companion (Druid)=Nimble`. You make each choice your old companion had again, such as nimble or savage and each specialization.
`companion/replace/cancel`: Withdraws a replacement that's still awaiting staff approval, and keeps your old companion.
%t **Note:** You can replace your companion only after your application is approved, and not while you're advancing.
%t **Note:** `sheet/companion` shows the replacement and what it still needs, and `sheet/history` records each replacement once staff approve it.
