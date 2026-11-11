---
toc: Pathfinder Second Edition
summary: Commands related to advancement, skills, and attributes.
aliases:
- advancefeats
- advancefeatures
- eligible feats
---

# Advancement - Selecting Feats and Class Features

See `help advance` for more information about advancement.

## Selecting Feats and Class Features
Most levels have you selecting some type of feat. Some class features gained in advancement may also require you to choose an option.

**Commands**:
`advance/feat <type> = <feat name>`: Select a feat (by its `<feat name>`) that is the specified `<type>`. Dedication feats are selected with class (charclass) feats. `<type>` options: `general`, `skill`, `charclass`, or `ancestry`. Dedication and Archetype feats are `charclass` feats.
`advance/option <feature> = <option>`: Some class features and feats require that an option selected with this command in `advance/review`. `<feature>` is the name of the class feature or feat, and `<option>` is the option you'd like to choose. 

Sometimes, feats might give training in skills you're already trained in. Those skills are turned into open slots to train an untrained skill into a trained one. Use the regular `advance/raise skill` command (as outlined in `help advanceskills`) to train those skills.

### Examples
Ancestral Paragon: `advance/option ancestral paragon=Nimble Sil` would satisfy Ancestral Paragon if the player character is a sildanyar or silyara.
Fighter Weapon Mastery: `advance/option Fighter Weapon Mastery=sword` would satisfy the Fighter Weapon Mastery class feature for fighters.

## What can I actually take?

`advance/review` lists the feat slots this level still has open.

`advance/info <slot type>`: Lists the feats you're eligible for in that slot. `<slot type>` options: `general`, `skill`, `ancestry`, `charclass`, `archetype`, and `dedication`.
`advance/info <slot type>=<text>`: Lists only the eligible feats whose names contain `<text>`: `advance/info skill=cat`.

`=<text>` narrows any long list on `advance/info`. `advance/info Additional Lore=arch` lists only the Lores containing 'arch' instead of paging through all of them.
