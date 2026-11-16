---
toc: Pathfinder Second Edition - Advancement
summary: Commands related to advancement, feats, and class features.
aliases:
- advancefeats
- advancefeatures
- eligible feats
---

# Advancement - Selecting Feats and Class Features

See `help advance` for more information about advancement.

## Selecting Feats and Class Features

Most levels give you at least one feat to select. Some class features and feats you gain in a level-up also require that you choose an option.

**Commands**:
`advance/feat <type>=<feat name>`: Selects the feat you specify (`<feat name>`) for an open slot of that type (`<type>`): `general`, `skill`, `charclass`, or `ancestry`.
%t **Note:** Dedication and archetype feats use `charclass` slots.
`advance/option <feature>=<option>`: Chooses an option (`<option>`) for a class feature or feat (`<feature>`) that `advance/review` lists as needing one.
%t **Examples**:
%t `advance/option Ancestral Paragon=Nimble Sil`: Chooses Nimble Sil for Ancestral Paragon, if your character is a sildanyar or silyara.
%t `advance/option Fighter Weapon Mastery=sword`: Chooses the sword group for a fighter's Fighter Weapon Mastery.

When a feat gives you training in a skill you're already trained in, you get an open skill slot instead. To fill it, train an untrained skill with `advance/raise skill`. For more information about raising skills, see `help advanceskills`.

## Finding Feats You Can Take

`advance/review`: Lists the feat slots this level still has open.
`advance/info <slot type>`: Lists the feats you're eligible for in a slot type (`<slot type>`): `general`, `skill`, `ancestry`, `charclass`, `archetype`, or `dedication`.
`advance/info <slot type>=<text>`: Lists only the eligible feats whose names contain `<text>`, such as `advance/info skill=cat`.
`advance/info<page> <slot type>`: Shows another page of a long list, such as `advance/info2 skill`. The bottom of each page shows the command for the next page.

`=<text>` narrows any long list on `advance/info`. For example, `advance/info Additional Lore=arch` lists only the Lores whose names contain "arch".
