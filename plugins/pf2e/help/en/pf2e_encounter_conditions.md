---
toc: Pathfinder Second Edition
summary: Being grabbed or held, conditions that limit your actions, and afflictions in an encounter.
aliases:
- encounter_conditions
- encounter conditions
---
# Pathfinder 2E Encounters - Conditions and Afflictions

For setting and clearing conditions, see `help heal` or [read it on the web](/help/pf2e_healing). For how conditions that come with effects work, see `help effects` or [read it on the web](/help/pf2e_effects).

## Grabbed and held

When a creature grabs you, it's holding you, and `encounter/view` shows who is holding you. While you're held:

- **Grabbed or restrained:** you're immobilized, and actions that move you are refused.
- **Grabbed:** anything that uses your hands (Interact, most spells) needs a DC 5 flat check first, and fails on a 4 or less. A spell lost this way is still spent, along with its actions.
- **Restrained:** Escape and Force Open are the only attack or manipulate actions you can use.
- `encounter/act escape` automatically targets whoever is holding you.
- The hold ends when its duration runs out, when you Escape, or when whoever is holding you drops.

**Swallowed or engulfed:** you're inside the creature. You're grabbed until you get out, you're slowed, and you take the creature's damage at the end of each of your turns. The creature is off-guard to you. A single hit of piercing or slashing damage equal to its Rupture value cuts you out, and so does a successful Escape.

## Other conditions that limit your actions

- **Prone:** you can only Crawl or Stand.
- **Raging:** you can't use concentrate actions other than Seek, unless they have the rage trait.
- **Fleeing or confused:** you can't Delay or Ready. While confused, you also can't use reactions, and each time an attack or spell hurts you, you roll a DC 11 flat check to snap out of it.
- **Deafened:** auditory actions need a DC 5 flat check, or they're lost. **Stupefied:** spells need a flat check against DC 5 plus the condition's value.
- **Blinded:** everything you attack is hidden from you, so you roll a DC 11 flat check before each attack. **Dazzled:** targets are concealed, so the check is DC 5.
- **Sickened:** you can't drink potions or elixirs. `encounter/use` takes an action.
- **Paralyzed:** you can still Recall Knowledge.

## Afflictions

Poisons, diseases, and curses have stages. You roll a save when you're first exposed: a failure puts you at stage 1, and a critical failure at stage 2. You roll again at the end of your turn once a stage measured in rounds has run its course. A success moves you down one stage and a critical success two; a failure moves you up one stage and a critical failure two. Below stage 1, you're cured. The effects of your current stage apply to you, and `encounter/view` shows the affliction next to each condition it gave you. Your turn reminder tells you when a save is due.
