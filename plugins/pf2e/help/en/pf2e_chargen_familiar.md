---
toc: Pathfinder Second Edition - Chargen
summary: Setting up your familiar or pet in chargen.
aliases:
- chargen_familiar
- cg_familiar
- cg_pet
- familiar_details
- specific_familiar
- specific_familiars
- pet_abilities
---

# Pathfinder 2E Chargen - Familiars

When a feat or class feature gives you a familiar or pet in chargen, you set its details before you submit your application. Staff review them with your application and approve your familiar when they approve you. `cg/review` shows your familiar's details and reminds you while any are still missing.

For more information about familiars and pets, see `help familiars`.

## Details

`familiar/name <name>`: Sets your familiar's name, such as `familiar/name Smudge`.
`familiar/species <species>`: Sets what kind of creature your familiar is, such as `familiar/species black cat`.
`familiar/form <form>`: Sets whether your familiar lives on land (`land`) or in water (`aquatic`), such as `familiar/form aquatic`. An aquatic familiar breathes water and has a swim Speed of 25 feet in place of a land Speed.
%t **Note:** A name is one word, like a character's name: it starts with a letter, can use only the letters A to Z, apostrophes, and hyphens, and is 2 to 30 characters long, such as `Cor'lana`. It can't be a restricted name or another character's name.
%t **Note:** A species can be several words. It starts with a letter, can use only letters, spaces, apostrophes, hyphens, and periods, and is at most 40 characters long. It can't use a restricted name.

## Specific Familiars

A specific familiar is a particular kind of magical creature, such as a pipefox, with abilities of its own. It uses some of your familiar's abilities each day.

`familiar/specific <specific familiar>`: Makes your familiar a specific familiar, such as `familiar/specific Pipefox`. The specific familiars are Aeon Wyrd, Fey Dragonet, Homunculus, Pipefox, Poppet, and Spellslime.
`familiar/specific none`: Makes your familiar an ordinary familiar again.
`familiar/choose <choice>=<option>`: Makes a choice your specific familiar has (`<choice>`) with the option you specify (`<option>`), such as `familiar/choose skill=Arcana` for a pipefox. After you choose a specific familiar, the game tells you which choices it has.
%t **Note:** Your familiar needs at least as many abilities each day as the specific familiar uses. A spellslime also needs a master who casts spells from spell slots.
%t **Note:** A specific familiar can't be aquatic. A familiar from Rat Familiar, Leshy Familiar, or Alchemical Familiar is a particular creature already, so it can't be a specific familiar.

## Pets and Leshy Familiars

A pet from the Pet feat has two pet abilities, which you choose when you gain it and which don't change from day to day.

`familiar/pet <ability>, <ability>`: Chooses your pet's two abilities, such as `familiar/pet Darkvision, Tough`. For Fast Movement, specify the Speed it increases in parentheses, such as `familiar/pet Fast Movement (land), Climber`.
`familiar/choose ability=<Plant or Fungus>`: Chooses whether your leshy familiar has the plant or fungus ability, such as `familiar/choose ability=Fungus`.
%t **Note:** If your pet's species naturally has one of the pet abilities, such as an owl's fly Speed, choose that ability. Staff check this when they approve your pet.
