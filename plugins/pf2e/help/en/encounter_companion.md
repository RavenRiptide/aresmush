---
toc: Pathfinder Second Edition - Encounters
summary: Your animal companion in encounters - joining, leaving, Commanding it, its Support, its advanced maneuver, riding it, and casting spells on it.
aliases:
- e_companion
- encounter_companion
- companion_encounter
- command_an_animal
- companions_cry
- mature_companion
- support
- support_benefit
- advanced_maneuver
- advanced_maneuvers
- badger_rage
- companion_dying
- riding
- dismount
- mounted_combat
- instinctive_support
- companion_spells
---

# Animal Companions in Encounters

Your animal companion joins an encounter only when you say it's there, since you may have left it behind. It has an ID like any other combatant, so anyone can target it by its ID or its name, but it has no place in the turn order: it acts on your turn.

For more information about animal companions, see `help companions`.

## Joining and Leaving

`encounter/companion`: Brings your animal companion into the encounter you're in. Join the encounter first with `encounter/join`.
`encounter/companion/leave`: Takes your animal companion out of the encounter, such as when it flees or you send it away.
`encounter/companion <character>`: Brings a character's animal companion into the encounter. Only the GM can use it.
`encounter/companion/leave <character>`: Takes a character's animal companion out of the encounter. Only the GM can use it.
%t **Note:** Only a named animal companion that staff have approved can join an encounter. Name it with `companion/name` first.
%t **Note:** Your animal companion's AC, saves, skills, and attacks are its own, with the barding and items it wears. `encounter/view` shows its stats beneath yours.
%t **Note:** Your animal companion joins with full Hit Points. If the GM starts an encounter that carries on from one your companion was in, it joins as it was at the end of that one, with its damage, conditions, and effects.
%t **Note:** Your animal companion leaves the encounter when you do. Two combatants can't share a name, so if another combatant already has your companion's name, it can't join.
%t **Note:** You're told when your animal companion takes damage.
`encounter/sheet/companion`: Shows your companion's sheet as it stands in the encounter: its ID, the actions it has this turn, its conditions and effects, and its hit points, defenses, skills, and attacks with those conditions counted.
`encounter/sheet/companion <character or companion>`: Shows another companion's sheet in the encounter, by its master's name or by the companion's ID or name, such as `encounter/sheet/companion #7`.

## At 0 Hit Points

Your companion is knocked out and dying at 0 Hit Points, as you would be: dying 1, or dying 2 from a critical hit, plus its wounded value. It makes its recovery checks at the start of your turn, and dies when its dying value reaches 4.
%t **Note:** Death Consent (DC) applies to your companion as it does to you. If the GM doesn't have DC, your companion stops dying instead of dying, and it isn't left drained or doomed.
%t **Note:** Healing your companion brings it out of dying, and it wakes once it has Hit Points again. While it's unconscious, it can't act.
%t **Note:** When your companion dies, staff record its death on your sheet with `companion/dead`, and you can then replace it with `companion/replace`. For more information, see `help companions`.

## Commanding Your Companion

`encounter/act command an animal=<companion>`: Spends 1 of your actions to Command your animal companion, which gives it 2 actions this turn, such as `encounter/act command an animal=Ash`. You don't attempt a Nature check to Command your own companion.
`encounter/act command an animal=<companion>/actions 2`: Spends 2 of your actions to Command your animal companion, which gives it 3 actions this turn, if you have the Companion's Cry feat.
`encounter/as <companion>=strike <attack>=<target>`: Has your Commanded companion Strike, such as `encounter/as Ash=strike jaws=#3`. Its multiple attack penalty is its own, not yours.
`encounter/as <companion>=act <action>`: Has your Commanded companion take an action, such as `encounter/as Ash=act stride` or `encounter/as #7=act trip=#3`.
%t **Note:** Your companion acts only on your turn, and only with the actions you give it by Commanding it. You can Command it once each turn. Command a Minion also Commands it, but only Command an Animal works with Companion's Cry.
%t **Note:** With Mature Animal Companion or Imposing Destrier, your companion can use 1 action of its own on your turn without a Command, to Strike or Stride, or to Burrow, Climb, Fly, or Swim if it has that Speed. If it does, you can't Command it that round.
%t **Note:** Your companion has no reactions and can't cast spells. While your group is exploring, it acts without your turn or a Command.
%t **Note:** Command an Animal aimed at any other animal, including another character's companion, is the general action, with a Nature check against the animal's Will DC.

## Support

`encounter/as <companion>=act support`: Has your Commanded companion Support you, which gives you its type's support benefit until the start of your next turn, such as `encounter/as Ash=act support`. The game tells the room what the benefit does.
`encounter/strike <attack>=<target>/support`: Makes a Strike against a creature in your Supporting companion's reach, which gains the support benefit, such as `encounter/strike longsword=#3/support`.
%t **Note:** Your companion can Support you only if it hasn't used another action that turn, and after it Supports you, it can use only basic move actions that turn: Crawl, Leap, Step, or Stride, or Burrow, Fly, or Swim if it has that Speed.
%t **Note:** The game applies the extra damage of a bear, bird, boar, scorpion, or shark, and leaves an ape's, cat's, or wolf's condition on the creature your Strike damages. A nimble or savage companion's dice are doubled. A bird's Dazzled lasts until the creature's bleed ends.
%t **Note:** Other companions' support benefits are about where creatures stand or the reactions they can use, so the game tells the room what the benefit does and the GM applies it. A horse's and a riding drake's benefits need you to be riding them. For more information about riding, see "Riding" in this file.

## Spells on Your Companion

`encounter/cast <spell>=<companion>`: Casts a spell on your animal companion, such as `encounter/cast magic hide=Ash`. The spell's effect lands on your companion.
%t **Note:** A spell for your animal companion, such as Heal Companion, Magic Hide, Enlarge Companion, or Apex Companion, works only on your own companion. Canopy Crawler also works on you.
%t **Note:** Enlarge Companion and Apex Companion make your companion larger, which counts when someone mounts it.
`encounter/act instinctive support`: Gives your animal companion 2 actions this turn, as if you Commanded it, right after you cast a non-cantrip spell on your companion alone, if you have the Instinctive Support feat. Your companion must use Support first, such as `encounter/as Ash=act support`.
%t **Note:** Use it before you do anything else. If your companion has already acted or been Commanded this turn, it can't take these actions.

## Advanced Maneuvers

A nimble or savage companion has its type's advanced maneuver, which `sheet/companion` shows.
`encounter/as <companion>=act <maneuver>=<target>`: Has your Commanded companion use its advanced maneuver, such as `encounter/as Ash=act takedown` or `encounter/as Ash=act grab and sting=#3`.
%t **Note:** The game makes the maneuver's Strikes, rolls its saves, and applies what it does, such as knocking a creature prone or Grabbing it. Its Strikes count toward your companion's multiple attack penalty but cost no actions beyond the maneuver's own.
%t **Note:** A maneuver that needs a hit, such as Takedown, Bear Hug, or Shred, works only right after that Strike hits. A maneuver that needs a Grabbed creature, such as Constrict or Death Roll, works on the creature your companion has Grabbed.
%t **Note:** The game can't see where your companion moves, so it tells the room about a maneuver's Stride, Step, or Fly, and you describe it in your pose. For Boar Charge, add `/moved` if your boar moved at least 20 feet, such as `encounter/as Tusker=act boar charge=#3/moved`, for its +2 to the attack.
%t **Note:** For Cat Pounce or Darting Attack, add the attack to use, such as `encounter/as Ash=act cat pounce=#3/claw`. Without it, your companion uses its first attack.
%t **Note:** Badger Rage lasts 1 minute. While it rages, your badger deals more damage with its jaws and claws, takes a -1 penalty to AC, and can't use concentrate actions except Seek.
%t **Note:** Your companion's maneuver needs a Command: it isn't a Strike or Stride, so a mature companion can't use it as its own action. Fire Breath can be used once in each encounter.

## Riding

`encounter/act mount=<companion>`: Mounts an animal companion, your own or an ally's, if it's at least one size larger than you, such as `encounter/act mount=Ash`.
`encounter/act mount`: Dismounts from the companion you're riding.
%t **Note:** While you're mounted, you take a -2 circumstance penalty to Reflex saves, and Mount is the only move action you can use.
%t **Note:** When you ride your own companion, you and it share one multiple attack penalty. If you Strike and then your companion Strikes, its Strike takes a -5 penalty.
%t **Note:** A companion carrying a rider can use only its land Speed, and can't move in a turn it Supports you. A companion with the mount special, such as a horse, can do both.
%t **Note:** If your mount leaves the encounter, falls unconscious, or dies, you're no longer mounted. `encounter/view` shows who is riding whom.
%t **Note:** A horse's support adds damage to a melee Strike you make while riding it after moving at least 10 feet. Add `moved` to the Strike, such as `encounter/strike lance=#3/support/moved`. A riding drake's support deals its fire damage only while you're riding it.
%t **Note:** With Fell Rider, your first Demoralize in a turn your mount Supports you gains a +1 circumstance bonus. With Heal Mount, *lay on hands* cast on your companion restores 10 Hit Points, plus 10 for each rank above 1st.
