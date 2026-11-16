---
toc: Pathfinder Second Edition - Advancement
summary: Commands related to advancement and formulas.
aliases:
- advanceformulas
- advance_formula
- advance_formulas
---

# Advancement - Formulas

See `help advance` for more information about advancement.

## Picking Formulas

Some choices give you more formulas when you level up: an alchemist's Formula Book, an investigator's Alchemical Sciences, Alchemical Scholar, Alchemical Discoveries, and a witch's Cauldron. A feat you take during the level-up, such as Alchemical Crafting or Magical Crafting, can open a formula choice too. Each one shows up in `advance/review` with your other choices, and offers only the common formulas it allows.

**Commands**:
`advance/info <choice>`: Lists the formulas a choice offers, grouped by catalog and item level. Formulas you already know or picked this level are left out.
`advance/info<page> <choice>`: Shows another page of a long list, such as `advance/info2 Formula Book`. The bottom of each page shows the command for the next page.
`advance/info <choice>=<text>`: Lists only the formulas whose names contain `<text>`, such as `advance/info Formula Book=elixir`.
`advance/option <choice>=<formula>`: Picks one formula from a choice. Pick again until the choice has no open picks left.
%t **Examples**:
%t `advance/info Formula Book`: Lists the formulas your Formula Book offers this level.
%t `advance/option Formula Book=Bottled Lightning (Moderate)`: Adds Bottled Lightning (Moderate) to your Formula Book.
`advance/undo`: Takes back your most recent choice this level, including a formula you picked.
%t **Note:** `advance/reset` discards every formula you picked this level, along with the rest of the level-up.
`formulas`: Lists the formulas you know. Formulas you pick in a level-up appear there after `advance/done`.

For more information about formulas you pick in character generation, see `help cg_formulas`. To get other formulas, buy them with `formula/buy`. See `help formulas` for more information.
