---
toc: Pathfinder Second Edition - Encounters
summary: Your familiar in encounters - joining, Commanding it, and its abilities.
aliases:
- e_familiar
- encounter_familiar
- minion
- minions
- command_a_minion
- lifelink
- phase_familiar
- patron_familiar
- patron_familiar_abilities
- euphoric_breath
- blood_link
- shed_spirit
- stitching_strike
- patrons_claim
- patrons_presence
---

# Familiars in Encounters

Your familiar joins an encounter only when you say it's there, since you may have left it somewhere safe. It has an ID like any other combatant, so anyone can target it by its ID or its name, but it has no place in the turn order: it acts on your turn.

For more information about familiars and pets, see `help familiars`.

## Joining and Leaving

`encounter/familiar`: Brings your familiar into the encounter you're in. Join the encounter first with `encounter/join`.
`encounter/familiar/leave`: Takes your familiar out of the encounter, such as when it flees or you send it away.
`encounter/familiar <character>`: Brings a character's familiar into the encounter. Only the GM can use it.
`encounter/familiar/leave <character>`: Takes a character's familiar out of the encounter. Only the GM can use it.
%t **Note:** Only an approved familiar can join an encounter. Until staff approve it, you can still cast its spells, because they are yours.
%t **Note:** Your familiar's AC and saves are yours, without your status and circumstance bonuses and penalties, so your being frightened doesn't change its AC. `encounter/view` shows its stats beneath yours.
%t **Note:** Your familiar leaves the encounter when you do. Two combatants can't share a name, so if another combatant already has your familiar's name, it can't join. If a character with your familiar's name joins after it, your familiar's ID is added to its name, such as `Smudge #7`.
`encounter/sheet/familiar`: Shows your familiar's sheet as it stands in the encounter: its ID, the actions it has this turn, its conditions and effects, and its hit points and stats with those conditions counted.
`encounter/sheet/familiar <character or familiar>`: Shows another familiar's sheet in the encounter, by its master's name or by the familiar's ID or name, such as `encounter/sheet/familiar #7`.

## Commanding Your Familiar

`encounter/act command a minion=<familiar>`: Spends 1 of your actions to Command your familiar, which gives it 2 actions this turn, such as `encounter/act command a minion=Smudge`.
`encounter/as <familiar>=act <action>`: Has your Commanded familiar take an action, such as `encounter/as Smudge=act stride` or `encounter/as #7=act escape`.
%t **Note:** Your familiar acts only on your turn, and only with the actions you give it by Commanding it. A familiar with the Independent ability has 1 action each turn without a command, or 2 when you Command it.
`encounter/as <familiar>=cast <spell>=<target>`: Has your familiar cast the spell its Spellcasting ability gives it today, once a day, such as `encounter/as Smudge=cast fear=#3`. It uses your tradition, spell attack modifier, and spell DC, and doesn't use one of your spell slots.
%t **Note:** If the spell has a drawback that affects its caster, it affects both you and your familiar. Apply it to you both.
%t **Note:** Your familiar has no reactions and can't make Strikes or cast other spells. It can't use actions with the attack trait except Escape and Force Open, and it can use manipulate actions only if it has the Manual Dexterity ability that day.
%t **Note:** Your familiar never gains item bonuses on its own checks. You're told when your familiar takes damage.
`encounter/act lifelink`: Takes the damage that just reduced your familiar to 0 Hit Points, if you have the Lifelink master ability today. Your familiar's Hit Points go back to what they were, and you take the damage instead. This uses your reaction.
%t **Note:** The game tells you when you can use Lifelink. Use it before anything else changes your Hit Points or your familiar's. If your homunculus's Blood Link hurt you when it fell, Lifelink undoes that damage.
`encounter/cast phase familiar`: Casts the Phase Familiar hex against the damage your familiar just took, if you know it. Your familiar takes the damage again with resistance 5 to all damage, 2 more for each rank above 1, and immunity to precision damage. This uses your reaction and a Focus Point.
%t **Note:** The game tells you when you can cast Phase Familiar. Cast it before anything else changes your Hit Points or your familiar's. Like any hex, it readies your patron's familiar ability.
%t **Note:** With Familiar Focus or Restorative Familiar, your familiar can spend 2 actions once a day to restore 1 of your Focus Points or heal you, such as `encounter/as Smudge=act familiar focus` or `encounter/as Smudge=act restorative familiar`. It can use each again after your next rest. While your group is exploring, your familiar can use them without your turn or a command, so a GM can start `encounter/explore` to let you use them after a fight.

## Specific Familiars

`encounter/as <fey dragonet>=act euphoric breath=<targets>`: Has your Commanded fey dragonet use Euphoric Breath, such as `encounter/as Feyfly=act euphoric breath=#3,#4`. Each target attempts a Fortitude save against the higher of your class DC and spell DC, and the game applies the outcome. Your fey dragonet can use it once in each encounter.

A homunculus's Blood Link works in encounters: while you are unconscious and dying, your homunculus acts on your turn as if you had Commanded it, and if it is destroyed, you take 2d10 mental damage.

## Witch Feat Activities

Some witch feats give your familiar an activity of its own. Your Commanded familiar uses it with its 2 actions, and each target attempts a basic save against your spell DC. `sheet/familiar` lists the activities your familiar has, with their damage at your level.

`encounter/as <familiar>=act shed spirit=<enemy>,<ally>`: Has your familiar use Shed Spirit (Spirit Familiar) on the enemy, such as `encounter/as Smudge=act shed spirit=#4,#2`. If the enemy takes damage, the ally regains Hit Points equal to half of it.
%t **Note:** Specify the enemy first and the ally second. If you don't specify an ally, nobody regains Hit Points.
`encounter/as <familiar>=act stitching strike=<enemy>`: Has your familiar use Stitching Strike (Stitched Familiar). An enemy that fails its Reflex save is immobilized for 1 round, and `encounter/act escape` ends it early against your spell DC.
`encounter/as <familiar>=act patron's claim=<target>`: Has your familiar use Patron's Claim. A target that fails its Fortitude save and takes damage is drained 2, or drained 4 on a critical failure, and you regain 1 Focus Point.
`encounter/as <familiar>=act patron's presence`: Has your familiar extend Patron's Presence, a 15-foot emanation that lasts until the end of your next turn.
`encounter/as <familiar>=enter patron's presence=<enemy>,<enemy>`: Marks enemies inside Patron's Presence, as the map shows. Each attempts a Will save against your spell DC, and on a failure is stupefied 2, or stupefied 3 on a critical failure, while it remains inside.
`encounter/as <familiar>=leave patron's presence=<enemy>`: Marks that an enemy has left Patron's Presence, which ends the stupefied condition the aura gave it.
%t **Note:** An enemy still inside attempts the save again when its turn starts, unless the aura has already made it stupefied. To keep the aura up for up to 1 minute, have your Commanded familiar Sustain it with `encounter/as <familiar>=act sustain`.
%t **Note:** Your familiar can use each activity once in each encounter. To see the command for one, use `encounter/how <activity>`.

## Patron Familiar Abilities

A witch's familiar has its patron's familiar ability, which works when you Cast or Sustain a hex. When you do with your familiar in the encounter, the game tells you the ability is ready, and you can use it once that turn as a free action.

`encounter/act familiar of restored spirit=<target>`: Gives one willing creature temporary Hit Points equal to 2 + half your level, until the start of your next turn.
`encounter/act familiar of balanced luck=<target>/<+1 or -1>`: Gives one creature a +1 status bonus or a -1 status penalty to its AC until the start of your next turn, such as `encounter/act familiar of balanced luck=#4/-1`.
`encounter/act familiar of keen senses/<sense>`: Gives your familiar scent, tremorsense, or wavesense until the start of your next turn, such as `encounter/act familiar of keen senses/scent`. Your familiar can then Point Out as a free action.
`encounter/act familiar of ongoing misery=<target>/<condition>`: Makes one condition with a timed duration last 1 round longer, such as `encounter/act familiar of ongoing misery=#4/slowed`. Each case of a condition can be prolonged only once.
`encounter/act familiar of stalking night=<target>`: Makes an enemy adjacent to your familiar, to which your familiar is concealed, hidden, or undetected, Frightened 1.
%t **Note:** Familiar of Freezing Rime and Familiar of Flowing Script change the battlefield, which the game can't track, so it describes them when you hex. Describe the ice or the distraction in your pose.
%t **Note:** Each hex you Cast or Sustain readies the ability again. An ability you don't use that turn is lost.
