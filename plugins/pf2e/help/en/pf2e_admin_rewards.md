---
toc: Pathfinder Second Edition - Admin
summary: Staff commands to add rewards for an encounter.
aliases:
- pf2eadmin_rewards
- pf2eadmin rewards
---
# Pathfinder 2E -- Admin commands for Encounter Rewards

`encounter/award [<encounter ID>]`: Shows PF2e's recommended rewards for an encounter, and what staff have already paid for it. The recommendation includes XP (based on a party of four), accomplishments staff can add, and GM Core's treasure for the encounter's threat level.
%t **Note:** The recommendation is only a guideline. Staff decide what each character is actually paid.
`encounter/award [<encounter ID>=]<character>=<xp>/<amount> <coin>`: Pays `<character>` the XP and money staff decide on for the encounter. The game records the payment on the encounter and in the character's XP and money history.
%t **Example**:
%t `encounter/award 12=Aria=80/135 gp` pays Aria 80 XP and 135 gp for encounter 12.
