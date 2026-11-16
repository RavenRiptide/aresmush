---
toc: Pathfinder Second Edition - Chargen
summary: How to pick the formulas your class and feats give you.
aliases:
- cg_formula
- cg_formulas
---

# Setting Up Formulas

Some classes and feats give you formulas to pick, such as an alchemist's formula book, Alchemical Crafting, Snare Crafting, Magical Crafting, and a witch's Cauldron. Each one opens a choice, and the choice offers only the common formulas it allows.

## Commands

`cg/info <choice>`: Lists the formulas a choice offers, grouped by catalog and item level. Formulas you already know or picked are left out.
`cg/info<page> <choice>`: Shows another page of a long list, such as `cg/info2 Formula Book`. The bottom of each page shows the command for the next page.
`cg/info <choice>=<text>`: Lists only the formulas whose names contain `<text>`, such as `cg/info Formula Book=mutagen`.
`cg/option <choice>=<formula>`: Picks one formula from a choice. Pick again until the choice has no open picks left.
`formulas`: Lists the formulas you know.

Some choices open again when you level up. For more information about picking formulas in a level-up, see `help advanceformulas`.

To get other formulas, buy them with `formula/buy`. See `help formulas` for more information.
