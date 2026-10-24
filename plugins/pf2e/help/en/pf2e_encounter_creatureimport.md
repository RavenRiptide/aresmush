---
toc: Pathfinder Second Edition
summary: A creature of your own, described on one line for +e/add.
aliases:
- encounter_creatureimport
- encounter creatureimport
---
# Pathfinder 2E Encounters - A Creature of Your Own

A Plotmaster or staff describes a creature on one line: its figures first, then whatever else it has,
each part after a semicolon and named by its first word. To keep one and add it again by name, save it:
see `help creatures`.

`+e/add Bandit Chief=ac 19 hp 45 level 3 fort 9 ref 11 will 7 perception 9 speed 25 str 3 dex 4; skills athletics 9, stealth 11; resist poison 5; weak fire 5; immune sleep; traits humanoid, human; strike shortsword +12 1d6+6 piercing (agile, finesse); ranged shortbow +12 1d6+2 piercing (range 60, deadly d10); ability Hail of Arrows [2]: Each creature in a 15-foot burst takes 3d6 piercing damage (DC 20 basic Reflex save).`

- **Figures**: `ac` and `hp` are needed; `hardness`, `level`, `fort`, `ref`, `will`, `perception`, `speed` (and `fly`, `swim`, `climb`, `burrow`), and its attribute modifiers `str dex con int wis cha`, which stand in for a skill it does not list.
- `skills <skill> <n>, ...`
- `immune <type>, ...`; `weak <type> <n>, ...`; `resist <type> <n>[ except <type>[ or <type>]], ...`: `resist physical 10 except silver`
- `traits <trait>, ...`; `size <size>`; `rarity <rarity>`; `senses <sense>, ...`
- `shield [<name>] <hardness> <hit points>[ +<bonus>]`: `shield 5 20`, raised for +2 to AC unless you say, and blocked with.
- `strike <name> <bonus> <damage> <type>[ plus <damage> <type>][ (<traits>)]`, as many as it has. `ranged` for a ranged one, with `range <feet>` among its traits. `1d4 persistent bleed` is persistent damage.
- `ability <name>[ [<1|2|3|reaction|free|passive>]]: <what it does>`. One whose words give a save rolls it when used with `+e/as <#id>=act <ability>=<targets>`: damage against it - `3d6 fire damage (DC 20 basic Reflex save)` - is dealt by the save, and outcomes written as a stat block writes them, each on a line of its own after `%r` - `Failure The creature is Frightened 2.` - leave the conditions they name.

It fights as a creature from the bestiary does, and can be made elite or weak.
