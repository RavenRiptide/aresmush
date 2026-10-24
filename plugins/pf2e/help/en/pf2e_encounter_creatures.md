---
toc: Pathfinder Second Edition
summary: "Running a creature in an encounter: what its stat block does for it."
aliases:
- encounter_creatures
- encounter creatures
---
# Pathfinder 2E Encounters - Running a Creature

`+e/as <#id>=strike <target>[=<Strike>]`, `=act <ability>[=<targets>]`, `=cast <spell>=<targets>` and
`=enter <aura>=<targets>` act for a creature. What its stat block gives it is run where the rules can
be:

- **A Strike's follow-up** - Grab, Knockdown, Push and their Improved forms - is offered when the Strike
  that lists it hits, and is its very next action: `+e/as #5=act grab=#2`. A Grab on someone it already
  holds tightens the hold to the end of its next turn, without a roll.
- **Constrict** crushes everyone it holds, or those you name among them. **Swallow Whole** needs it to
  hold the target; **Engulf** and **Trample** take every target you name. **Rend** needs two hits
  running with its listed Strike. **Ferocity** is offered when it drops.
- **An ability that calls for a save** - a breath, a gaze, a swarm's bites - is aimed at as many as you
  name, and each rolls it: `+e/as #5=act flame breath=#1,#2,#3`. What its outcomes name is left on
  them, and damage in its words is dealt by the save.
- **An aura with a save** - Frightful Presence, Stench - is rolled by whoever you put inside it with
  `+e/as #5=enter frightful presence=#1,#2`. Whoever has saved is immune for as long as its words say.
- **A venom or disease** on its Strike is saved against as the Strike hits, and runs its stages from
  there. `+e/affliction <who>=<name>/<stage>` moves it by hand: a stage counted in days, a cure with 0.
- **An ability that Strikes each of several targets** - a hydra's Storm of Jaws - Strikes each one you
  name under the one penalty, which moves on once they are all made. One whose Strike follows a failed
  save - a harpy's Hungry Winds - rolls the save, and Strikes whoever fails.
- **An ability that takes one action or more** - a troop's attack, `1 to 3` on its first line - deals
  what the actions you spend deal: `+e/as #5=act shambling onslaught=#1,#2/actions 2`. One, unless you say.
- **A shield** on its stat block is raised and blocked with as a character's is: `+e/as #5=act raise a
  shield`, and `+e/as #5=act shield block` when a hit it could block says so. `+e/creature #5` shows
  what the shield has taken.
- **Hardness** comes off each hit it takes, and adamantine as hard as it halves that: `damage #5=12
  slashing adamantine`.
- **A troop** loses a segment as its hit points fall below each threshold, which is then the most it has.
- **What its dropping triggers** - a vampire's Mist Escape, Ferocity - is offered as it drops, and is
  all it can still do.
- **A breath that takes rounds to come back**, a reaction already spent, and an ability used more often
  than its Frequency allows are yours to allow: you are told when the breath is back, and warned if you
  use any of them early.
- **What it is for good** - a zombie's Slowed 1 and its having no reactions - is on it from the start,
  and stays whatever is cleared.
- **A Strike that takes loading** is shot once: `+e/as #5=reload` loads it again.
- **Its spells** are counted: each preparation of a prepared spell, the slots of a rank for a
  spontaneous caster, once a day for an innate spell unless its stat block says otherwise. Past that
  you are warned, and it is cast.
- **Immunity to magic** keeps out a spell and all it does, but for the spells it names.
- **A shape** - a werecreature's hybrid, humanoid or animal - decides which of
  its Strikes it has: a werewolf has its weapons, jaws and claws as a hybrid, its weapons and fist as a
  human, and only its jaws and claws as a wolf. Its stat block says which Strike is offered in which
  shape. It changes shape with its ability, which takes the ability's actions: `+e/as #5=act change
  shape/animal`. You see the shape each is in with `+e/creature #5` and on the encounter's page; the
  players do not. `+e/add werewolf/animal` adds one already changed.
- **A circumstance** its stat block makes a toggle - Pack Attack, a charge - is off until you say it
  holds: `/pack attack` on the Strike, or `+e/option #5=pack-attack/on`.
- **Immunities, weaknesses and resistances** apply by what the damage is: a swarm resists a blade and
  is hurt more by a fireball; a devil's resistance lets silver through. `encounter/scan` lists them.
  What a creature is counts without its stat block saying so: a construct, a mindless creature and a
  swarm have their kind's immunities, vitality harms only the undead, and void only the living.
  `damage` tells you what was taken where that is not what you named.
- **The incapacitation trait** moves the outcome a degree for a creature too strong for the effect.

Anything else on its stat block is told with its words when used, for you to run.
