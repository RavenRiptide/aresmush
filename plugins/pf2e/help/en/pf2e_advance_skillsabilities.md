---
toc: Pathfinder Second Edition - Advancement
summary: Commands related to advancement, skills, and attributes.
aliases:
- advanceskills
- advanceattributes
- advancelanguages
---

# Advancement - Raising Skills and Attributes, and Learning Languages

See `help advance` for more information about advancement.

## Raising Attributes and Skills

At levels 5, 10, 15, and 20, you boost four attributes. Some levels also let you raise a skill to the next proficiency rank, or train an untrained skill.

**Commands**:
`advance/raise attributes=<attribute1> <attribute2> <attribute3> <attribute4>`: Boosts four different attributes.
%t **Note:** A boost to an attribute at +4 or higher is a partial boost, which your sheet marks (P). A second partial boost raises the modifier by 1.
`advance/raise skill=<skill>`: Raises a skill to the next proficiency rank, such as `advance/raise skill=Nature`.
`advance/raise skill choice=<skill>`: Raises the skill you choose from a skill choice, such as one a Dedication feat gives you, to the next proficiency rank.
%t **Note:** A swashbuckler's Stylish Tricks gives a skill choice at levels 3, 7, and 15, for Acrobatics or your style's skill. It comes in addition to the regular skill increase at those levels.
`advance/language <language>`: Learns a language, when raising your Intelligence modifier or a feat gives you one.
`lang/info <category>`: Lists the languages in a category (`<category>`): `common`, `uncommon`, `rare`, or `secret`. Use it to find a language to learn with `advance/language`.
%t **Note:** `advance/language` learns only common and uncommon languages. To learn a rare language, spend RPP; you can also spend RPP on a common or uncommon one. You learn secret languages only from specific game features, such as the druid's Wildsong. For more information about RPP spends, see [Character Spends](/wiki/mechanics:characterspends).

When a feat gives you training in a skill you're already trained in, you get an open skill slot instead. Raising your Intelligence modifier also gives you one. To fill an open skill slot, train an untrained skill with `advance/raise skill`.

**Examples**:
%t `advance/raise attributes=Strength Dexterity Constitution Wisdom`: Boosts Strength, Dexterity, Constitution, and Wisdom.
%t `advance/raise skill choice=Stealth`: Raises Stealth, when a skill choice offers Stealth or Thievery.
%t `advance/language Sylhart`: Learns the Sylhart language.
%t `lang/info uncommon`: Lists the uncommon languages.
