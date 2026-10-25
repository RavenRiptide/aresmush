---
toc: Pathfinder Second Edition
summary: "Running a creature in an encounter: what its stat block does for it."
aliases:
- encounter_creatures
- encounter creatures
---
# Pathfinder 2E Encounters - Running a Creature

`encounter/as <#id>=<command>`: Acts for a creature, using the same commands players use: `strike <target>[=<Strike>]`, `act <ability>[=<targets>]`, `cast <spell>=<targets>`, or `enter <aura>=<targets>`. See `help encounter actions` or [read it on the web](/help/pf2e_encounter_actions).

The game runs as much of a creature's stat block as the rules allow. When the creature uses anything else in its stat block, the game shows the room the text as written, for you to resolve.

## Strikes

- **Strike follow-ups:** When a Strike that lists Grab, Knockdown, or Push (or their Improved versions) hits, the game offers the follow-up, which must be the creature's next action: `encounter/as #5=act grab=#2`. A Grab on someone the creature is already holding extends the hold to the end of its next turn, with no roll.
- **Abilities that Strike several targets**, such as a hydra's Storm of Jaws, Strike each target you name at the same multiple attack penalty, which increases once all the Strikes are made. An ability whose Strike follows a failed save, such as a harpy's Hungry Winds, rolls the save, then Strikes everyone who fails it.
- **Poisons and diseases** on a Strike: the target saves when the Strike hits, and the affliction runs through its stages from there. `encounter/affliction <who>=<name>/<stage>` sets the stage by hand for stages measured in days, and stage 0 cures it.
- **Strikes that need reloading** fire once. `encounter/as #5=reload` reloads them.
- **Optional circumstances** from the stat block, such as Pack Attack or a charge, are off until you turn them on: add `/pack attack` to the Strike, or use `encounter/option #5=pack-attack/on`.

## Abilities

- **Constrict** damages everyone the creature is holding, or only the ones you name. **Swallow Whole** only works on a target the creature is holding. **Engulf** and **Trample** hit every target you name. **Rend** needs two hits in a row with the Strike it lists.
- **Abilities with a save**, such as a breath weapon, a gaze, or a swarm's bites, target everyone you name, and each target rolls the save: `encounter/as #5=act flame breath=#1,#2,#3`. The game applies the conditions named in each outcome, and deals the damage in the ability's text according to each target's result.
- **Auras with a save**, such as Frightful Presence or Stench: each combatant you place inside the aura with `encounter/as #5=enter frightful presence=#1,#2` rolls the save. Anyone who succeeds is immune for as long as the aura's text says.
- **Abilities with a variable action cost**, such as a troop's attack marked `1 to 3`, deal damage based on how many actions you spend: `encounter/as #5=act shambling onslaught=#1,#2/actions 2`. Without `/actions`, the creature spends one action.
- **Abilities triggered by dropping**, such as Ferocity or a vampire's Mist Escape, are offered when the creature drops to 0 HP, and are the only things it can still do.
- **Recharging abilities, spent reactions, and limited-use abilities** are up to you. The game tells you when a recharging ability is back, and warns you if you use any of them early.

## Defenses

- **Shields** on a stat block work the same way a character's do: raise the shield with `encounter/as #5=act raise a shield`, then use `encounter/as #5=act shield block` when the game says a hit can be blocked. `encounter/creature #5` shows how much damage the shield has taken.
- **Hardness** reduces each hit the creature takes. Adamantine halves Hardness of 10 or less: `damage #5=12 slashing adamantine`.
- **Immunities, weaknesses, and resistances** apply based on the damage: a swarm resists blades and takes extra damage from a fireball, and a devil's resistance doesn't apply to silver. `encounter/scan` lists each creature's immunities, weaknesses, and resistances. If the damage the creature took differs from what you entered, `damage` tells you.
%t **Note:** A creature's type counts even if its stat block doesn't mention it: constructs, mindless creatures, and swarms have their type's immunities, vitality damage only hurts the undead, and void damage only hurts the living.
- **Immunity to magic** blocks a spell and all its effects, except for any spells the immunity lists.
- **The incapacitation trait** improves the outcome by one degree for a creature too high-level for the effect.
- **Troops** lose a segment each time their hit points drop below a threshold, and that threshold becomes their new maximum.
- **Permanent conditions**, such as a zombie's Slowed 1 and lack of reactions, apply from the start of the encounter, and stay even when the creature's other conditions are cleared.

## Spells and shapes

- **Spells** are tracked: each prepared copy of a prepared spell, each rank's slots for a spontaneous caster, and once a day for innate spells unless the stat block says otherwise. Past that limit, the game warns you, but still casts the spell.
- **Shapes**, such as a werecreature's hybrid, humanoid, or animal form, decide which Strikes the creature has. For example, a werewolf has its weapons, jaws, and claws in hybrid form; its weapons and fist in human form; and only its jaws and claws in wolf form. The stat block says which Strikes go with which shape. The creature changes shape with its ability, spending that ability's actions: `encounter/as #5=act change shape/animal`. `encounter/add werewolf/animal` adds a werewolf already in wolf form.
%t **Note:** You can see each creature's shape with `encounter/creature #5` and on the encounter's web page. Players can't.
