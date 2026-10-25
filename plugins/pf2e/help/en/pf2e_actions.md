---
toc: Pathfinder Second Edition
summary: How actions outside of encounters work.
aliases:
- action
- actions
---
# Pathfinder 2E - Actions

An action is something a character does, such as Take Cover, Rage, a monk's stance, or a reaction. The game uses Foundry VTT's Pathfinder 2e actions from Player Core, Player Core 2, and GM Core (basic, skill, and class actions, plus every feat that is an action), so actions are listed under the names you'd expect.

Everyone has the basic, skill, exploration, and downtime actions. Any other action (from a class, archetype, heritage, or a feat that is an action) is available if you have the feat or feature it comes from. For example, a barbarian has Rage because they have the Rage class feature.

### Viewing actions
`action <name>`: Shows an action's cost, how often it can be used, and what it does. If using the action puts an effect on you, this also shows the effect, how long it lasts, and the command that applies it.
`action/search <words>`: Lists the actions whose names contain all of `<words>`.
`action/available [<mode>]`: Lists the actions you can use, grouped by cost. Name a mode to see only the actions for that mode: `combat` (or `encounter`), `exploration`, `downtime`, or `reactions`. `action/available/combat` also works.
%t **Note:** An action marked `*` puts an effect on you when you use it.

### Using actions
`action/use <name>[/<option>...]`: Uses an action. The game tells everyone in the scene that you're using an action, and it applies the effect of an action (like Rage, Take Cover, or a stance) onto your character. If you're in an encounter, the game counts the action's cost against your turn.
%t **Examples**:
%t `action/use rage`
%t `action/use mountain stance`
%t **Note:** Some effects need details that only you know, such as the rank you cast a spell at. Add these details as options after the action's name: `rank <n>`, `value <n>`, or an answer to a question the effect asks. These are the same options `effect/add` takes.

`action/use` is the same command as `encounter/act`. An action that rolls a check against someone needs a target, such as `encounter/act <name>=<target>`. In an encounter, `encounter/act` also rolls the action's check against its target and applies the outcome; see `help encounter actions`.

The encounter also tracks how often you've used each action. If you go over an action's limit, the game shows you, but doesn't stop you. You can tell the GM if you messed up, and they can undo your action for you.
