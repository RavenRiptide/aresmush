---
toc: Pathfinder Second Edition
summary: Adding temporary custom creatures to encounters.
aliases:
- encounter_creatureimport
- encounter creatureimport
---
# Pathfinder 2E Encounters - Adding Temporary Custom Creatures to Encounters

Plotmasters and staff can add a custom creature to an encounter by describing it on one line. This is useful for a custom creature you want to use, but don't expect to run again. To save a permanent copy of a creature to use in other encounters, see `help creatures` or [read it on the web](/help/pf2e_creatures).

`encounter/add [elite|weak] <name>=<description>`: Adds a custom creature called `<name>`, built from `<description>`, to the encounter.
%t **Example**:
%t `encounter/add Bandit Chief=ac 19 hp 45 level 3 fort 9 ref 11 will 7 perception 9 speed 25 str 3 dex 4; skills athletics 9, stealth 11; resist poison 5; weak fire 5; immune sleep; traits humanoid, human; strike shortsword +12 1d6+6 piercing (agile, finesse); ranged shortbow +12 1d6+2 piercing (range 60, deadly d10); ability Hail of Arrows [2]: Each creature in a 15-foot burst takes 3d6 piercing damage (DC 20 basic Reflex save).`

## Writing a description

A description starts with the creature's statistics. Each other part comes after a semicolon and starts with a keyword, such as `skills`, `strike`, or `ability`.

- **Statistics:** `ac` and `hp` are required. You can also give `hardness`, `level`, `fort`, `ref`, `will`, `perception`, `speed` (plus `fly`, `swim`, `climb`, and `burrow`), and the attribute modifiers `str`, `dex`, `con`, `int`, `wis`, and `cha`. The game uses the attribute modifiers for any skill the creature doesn't list.
- **Skills:** `skills <skill> <n>, ...` lists the creature's skill modifiers, such as `skills athletics 9, stealth 11`.
- **Immunities, weaknesses, and resistances:** `immune <type>, ...`, `weak <type> <n>, ...`, and `resist <type> <n>[ except <type>[ or <type>]], ...`, such as `resist physical 10 except silver`.
- **Traits and senses:** `traits <trait>, ...`, `size <size>`, `rarity <rarity>`, and `senses <sense>, ...`.
- **Shield:** `shield [<name>] <hardness> <hit points>[ +<bonus>]`, such as `shield 5 20`. The shield gives +2 to AC when raised unless you give a different bonus, and the creature can Shield Block with it.
- **Strikes:** `strike <name> <bonus> <damage> <type>[ plus <damage> <type>][ (<traits>)]`, once for each Strike. For a ranged Strike, use `ranged` instead of `strike`, and include `range <feet>` among its traits. Write persistent damage like `1d4 persistent bleed`.
- **Abilities:** `ability <name>[ [<1|2|3|reaction|free|passive>]]: <what it does>`. If the text includes a save, using the ability with `encounter/as <#id>=act <ability>=<targets>` rolls that save for each target:
  - Damage written with its save, such as `3d6 fire damage (DC 20 basic Reflex save)`, is dealt according to each target's result.
  - Outcomes written the way a stat block writes them, each on its own line after `%r` (such as `Failure The creature is Frightened 2.`), apply the conditions they name.

A custom creature fights just like a creature from the bestiary: it makes Strikes, takes damage, and uses its abilities. You can make it elite or weak with `encounter/add elite` or `encounter/adjust`; see `help encounter_runner` or [read it on the web](/help/pf2e_encounter_runner).
