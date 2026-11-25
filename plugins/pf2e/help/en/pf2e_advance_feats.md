---
toc: Pathfinder Second Edition - Advancement
summary: Commands related to advancement and feats.
aliases:
- advancefeats
- advanceretrain
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

When you take Incredible Companion, you choose whether your animal companion becomes nimble or savage, and when you take Specialized Companion, you choose a specialization. Make the choice with `advance/option`, such as `advance/option Incredible Companion (Druid)=Savage`. For more information about animal companions, see `help companions`.

## Retraining a Feat

When you take Witch Dedication and already have a familiar from Pet, Familiar, Animal Accomplice, or Rat Familiar, the familiar your patron sends you replaces it, and you retrain that feat in the same level. `advance/review` lists the retrain until you make it.

`advance/info retrain`: Lists the feats you can retrain into. Add `=<text>` to narrow the list, such as `advance/info retrain=spell`.
`advance/retrain <feat name>`: Retrains the feat you owe a retrain into the feat you specify (`<feat name>`).
%t **Note:** The new feat must be the same type as the old one, no higher than the level you took the old one at, and one whose prerequisites you met at that level. It can't be a Dedication.
%t **Note:** Taking back the level with `advance/reset` also takes back the retrain. For more information about familiars and Witch Dedication, see `help advance_familiar`.

When a feat gives you training in a skill you're already trained in, you get an open skill slot instead. To fill it, train an untrained skill with `advance/raise skill`. For more information about raising skills, see `help advanceskills`.

## Finding Feats You Can Take

`advance/review`: Lists the feat slots this level still has open.
`advance/info <slot type>`: Lists the feats you're eligible for in a slot type (`<slot type>`): `general`, `skill`, `ancestry`, `charclass`, `archetype`, or `dedication`.
`advance/info <slot type>=<text>`: Lists only the eligible feats whose names contain `<text>`, such as `advance/info skill=cat`.
`advance/info<page> <slot type>`: Shows another page of a long list, such as `advance/info2 skill`. The bottom of each page shows the command for the next page.
