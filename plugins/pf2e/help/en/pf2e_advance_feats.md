---
toc: Pathfinder Second Edition - Advancement
summary: Commands related to advancement and feats.
aliases:
- advancefeats
- eligible feats
---

# Advancement - Selecting Feats

See `help advance` for more information about advancement.

## Selecting Feats

Most levels give you at least one feat to select.

**Commands**:
`advance/feat <type>=<feat name>`: Selects the feat you specify (`<feat name>`) for an open slot of that type (`<type>`): `general`, `skill`, `charclass`, or `ancestry`.
%t **Note:** Dedication and archetype feats use `charclass` slots.

A class feature or feat that gives you a feat to choose, such as Skillful Lessons, doesn't use a feat slot. Choose that feat with `advance/option`. For more information about choosing options, see `help advancefeatures`.

When a feat gives you training in a skill you're already trained in, you get an open skill slot instead. To fill it, train an untrained skill with `advance/raise skill`. For more information about raising skills, see `help advanceskills`.

## Finding Feats You Can Take

`advance/review`: Lists the feat slots this level still has open.
`advance/info <slot type>`: Lists the feats you're eligible for in a slot type (`<slot type>`): `general`, `skill`, `ancestry`, `charclass`, `archetype`, or `dedication`.
`advance/info <slot type>=<text>`: Lists only the eligible feats whose names contain `<text>`, such as `advance/info skill=cat`.
`advance/info<page> <slot type>`: Shows another page of a long list, such as `advance/info2 skill`. The bottom of each page shows the command for the next page.
