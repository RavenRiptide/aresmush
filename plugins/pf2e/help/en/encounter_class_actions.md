---
toc: Pathfinder Second Edition - Encounters
summary: Class and ancestry feats in an encounter, such as Flurry of Blows, Quick Draw, and Reactive Strike.
aliases:
- e_classfeats
- e_class
- e_ancestryfeats
- flurry_of_blows
- reactive_strike
- opportune_riposte
- nimble_dodge
- quick_draw
- brandishing_draw
- quick_bomber
- finishers
- deadly_aim
- drain_bonded_item
- "dragon's_rage_breath"
- dragons_rage_breath
- inspired_stratagem
- devise_a_stratagem
- stratagem
- strategic_strike
- hunt_prey
- hunters_edge
---
# Pathfinder 2E Encounters - Class and Ancestry Feat Actions

These feat actions take more syntax than `encounter/act <action>=<target>`. For more information about other actions, see `help e/act`.

## Actions that Strike

`encounter/act <action>=<target>[/<weapon>][/<detail>...]`: Uses a feat action that includes a Strike, such as Flurry of Blows, Deadly Aim, Sudden Charge, or a finisher. The game makes the action's Strikes against the target with the weapon you specify, or with your first weapon the action allows, and applies the action's rules. Each Strike counts toward your multiple attack penalty. You roleplay anything else the action does.
%t **Examples**:
%t `encounter/act flurry of blows=#3`
%t `encounter/act deadly aim=#4/shortbow/range 2`
%t `encounter/act sudden charge=#3/greatsword/flanking`
`encounter/act <action>=<target>/<weapon>`: **Quick Draw, Brandishing Draw, and Quick Bomber.** Draws the weapon or bomb you specify from what you carry, and Strikes with it.
%t **Note:** For Brandishing Draw, you can specify a one-action finisher to Strike with: `encounter/act brandishing draw=#3/rapier/bleeding finisher`.
%t **Note:** Quick Bomber only throws a bomb you already carry. Make one first with `encounter/alchemy`.

## Reactions

`encounter/act <reaction>=<target>[/<weapon>]`: **Reactive Strike and Opportune Riposte.** Strikes with the weapon you specify, or with your first weapon that works. The Strike spends your reaction, and doesn't use or add to your multiple attack penalty.
%t **Example**:
%t `encounter/act reactive strike=#3/longsword`
`encounter/act <reaction>`: **Nimble Dodge, and other reactions that raise your AC.** Answers a hit you just took: the game applies the bonus to that attack, and undoes the hit if it becomes a miss. The game tells you when a reaction like this could turn a hit into a miss.
%t **Example**:
%t `encounter/act nimble dodge`
`encounter/act inspired stratagem=<ally>`: Only works on an ally you reviewed stratagems with at your daily preparations.

## Devise a Stratagem

`encounter/act devise a stratagem=<target>`: **Investigator.** Rolls your d20 ahead of time against the target and starts you on an attack stratagem. Your next Strike against that target this round uses the roll in place of the d20, adds your Intelligence modifier if it's higher than your Strength or Dexterity modifier, and deals your Strategic Strike damage if it hits.
%t **Note:** The roll replaces the d20 only for an agile, finesse, or ranged weapon. A Strike with any other weapon rolls as usual and uses up the stratagem.
%t **Example**:
%t `encounter/act devise a stratagem=#3`, then `encounter/strike rapier=#3`
`encounter/act devise a stratagem/<stratagem>`: Changes your stratagem after you see the roll, at no cost in actions. Choose `skill`, or `defensive` if you have the Defensive Stratagem feat. With either one, you can't Strike the target until the start of your next turn.
%t **Example**:
%t `encounter/act devise a stratagem/skill`

## Hunt Prey

`encounter/act hunt prey=<target>`: **Ranger.** Makes the target your prey. Your hunter's edge then applies to it: Flurry's lower multiple attack penalty, Outwit's bonuses, or Precision's extra damage on your first hit against it each round.
%t **Note:** You can have only one prey at a time. Hunting another creature moves your prey to it.
%t **Note:** With Animal Companion, your companion shares your prey and your hunter's edge, including if it joins the encounter later. With Masterful Companion, it gains your edge's Masterful Hunter benefit instead.
%t **Example**:
%t `encounter/act hunt prey=#3`, then `encounter/strike longbow=#3`

## Other class actions

`encounter/act drain bonded item/<spell>`: **Wizard.** Recovers a spell you prepared today and have already cast, so you can cast it again with `encounter/cast`.
`encounter/act dragon's rage breath=<target>,<target>`: **Barbarian.** While you're raging, breathes your Dragon Instinct's damage, and your targets roll a basic Reflex save against your class DC. You can use it once every 10 minutes.
