---
toc: Setting Up Formulas
summary: How to pick the formulas your class and feats give you.
aliases:
- cg_formula
- cg_formulas
---

# Setting Up Formulas

Some classes and feats give you formulas to pick, such as an alchemist's formula book, Alchemical Crafting, Snare Crafting, Magical Crafting, and a witch's Cauldron. Each one opens a choice, and the choice offers only the common formulas it allows.

## Commands

`cg/info <choice>`: Lists the formulas a choice offers. In a level-up, use `advance/info <choice>`.
`cg/option <choice>=<formula>`: Picks one formula from a choice. Pick again until the choice has no open picks left. In a level-up, use `advance/option <choice>=<formula>`.
`formulas`: Lists the formulas you know.

## Selections at later levels

Some choices open again when you level up: an alchemist's Formula Book, an investigator's Alchemical Sciences, Alchemical Scholar, Alchemical Discoveries, and Cauldron. They show up in `advance/review` with your other choices, and you pick them with `advance/option`.
%t **Note:** Undoing a level-up also takes back the formulas you picked during it.

To get other formulas, buy them with `formula/buy`. See `help formulas` for more information.
