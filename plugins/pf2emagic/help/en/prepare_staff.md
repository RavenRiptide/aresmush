---
toc: Pathfinder Second Edition - Magic
summary: Preparing a staff, expending spells on it, and Staff Nexus.
aliases:
- prepare_staff
- unprepare_staff
- staff_nexus
- makeshift_staff
---

# Preparing a Staff

You can prepare one staff a day, if at least one of its spells is on a spell list you cast from. Only you can cast from it that day. For more information about casting from a staff, see `help e/gear`.

**Commands**:
`prepare/staff <staff>`: Prepares a staff you carry for the day. It gets charges equal to the rank of your highest spell slot.
`prepare/staff <staff>/<rank> = <spell>`: Expends a spell you prepared at `<rank>` and haven't cast, adding `<rank>` charges to the staff. A prepared caster can expend one spell a day on a staff. If you've already prepared the staff today, this adds to it.
`prepare/staff`: Shows the staff you prepared today, its charges, and the spells you expended on it.
`unprepare/staff`: Takes back today's staff and returns the spells you expended on it. You can't take it back once you've cast from it.
%t **Note:** A wizard with the Staff Nexus thesis can expend two spells from 8th level and three from 16th. Expend each with its own `prepare/staff` command, such as `prepare/staff Staff of Fire/3 = fireball`, then `prepare/staff Staff of Fire/2 = mist`.
%t **Note:** Your staff's charges fade when the GM rests you, and you prepare a staff again.

**Staff Nexus**:
`prepare/staff makeshift staff`: Prepares your makeshift staff on its own.
%t **Note:** You choose your makeshift staff's two spells in chargen; see `help addspell`. Prepared on its own, it has no charges until you expend a spell on it. Any other staff you prepare contains your makeshift staff's two spells as well as its own, and gets its usual charges.
