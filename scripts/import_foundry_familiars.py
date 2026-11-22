#!/usr/bin/env python3
"""Foundry's familiar abilities, as `game/config/pf2e_familiar_abilities.yml`.

Emblem of Ea takes the abilities in Player Core, Player Core 2 and GM Core. Each entry's description and
rule elements are Foundry's, filtered through the same `take` the rules importer uses, so a rule we can't
apply is reported and left out rather than flattened.

Foundry records neither which abilities are master abilities nor what an ability requires (that is prose
in its description), so both live in HAND below, and an ability in scope with no row there stops the
import. HAND is also where the ten pet abilities, the leshy-only pool, each Witch patron's ability and
the choices a player makes when picking an ability are written down.

Usage: scripts/import_foundry_familiars.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import collections
import glob
import json
import os
import sys

import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import foundry_source  # noqa: E402
import import_foundry_rules as rules  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')
OUT = 'pf2e_familiar_abilities.yml'
SECTION = 'pf2e_familiar_abilities'

BOOKS = {'Pathfinder Player Core', 'Pathfinder Player Core 2', 'Pathfinder GM Core'}

# Player Core prints Elemental (p. 212), and Foundry files it under Rage of Elements.
ALSO = {'Elemental'}

# The folder Foundry keeps other books' specific familiars in. Ours are hand-written in
# pf2e_specific_familiars.yml.
SPECIFIC_FOLDER = 'specific-familiary-abilities'

SKILLED = {'from': 'skills', 'except': ['Acrobatics', 'Stealth']}
RESISTED = {'from': 'list', 'options': ['acid', 'cold', 'electricity', 'fire', 'poison', 'sonic'], 'count': 2}
ELEMENTS = {'from': 'list', 'options': ['air', 'earth', 'fire', 'metal', 'water', 'wood']}
SAVES = {'from': 'list', 'options': ['Fortitude', 'Reflex', 'Will']}

# kind: familiar | master | patron. pet: one of the Pet feat's abilities. changes_trait: replaces the
# animal trait, and a familiar may have only one. prereq keys: abilities (all of these picked too), level,
# trait (the familiar's), slot_rank (they cast spells of this rank from slots), has_focus_pool, feature (they
# hold this class feature), specific (only this specific familiar), innate_ancestry_spell. pool: leshy
# (Leshy Familiar Secrets' extra pick). choice: what the player picks with it. repeatable: may be picked
# more than once, with a different choice each time.
HAND = {
    # The Pet feat's abilities (Player Core p. 259).
    'Amphibious': {'kind': 'familiar', 'pet': True},
    'Burrower': {'kind': 'familiar', 'pet': True},
    'Climber': {'kind': 'familiar', 'pet': True},
    'Darkvision': {'kind': 'familiar', 'pet': True},
    'Echolocation': {'kind': 'familiar', 'pet': True},
    'Fast Movement': {'kind': 'familiar', 'pet': True, 'choice': {'from': 'speeds'}},
    'Flier': {'kind': 'familiar', 'pet': True},
    'Manual Dexterity': {'kind': 'familiar', 'pet': True},
    'Scent': {'kind': 'familiar', 'pet': True},
    'Tough': {'kind': 'familiar', 'pet': True},

    # Familiar abilities (Player Core pp. 212-213).
    'Accompanist': {'kind': 'familiar'},
    # Foundry adds the trait and leaves the immunities in the description.
    'Construct': {'kind': 'familiar', 'changes_trait': True, 'prereq': {'abilities': ['Tough']},
                  'rules': [{'key': 'Immunity', 'type': ['death-effects', 'disease', 'doomed', 'drained', 'fatigued',
                                                         'healing', 'nonlethal-attacks', 'paralyzed', 'poison',
                                                         'sickened', 'spirit', 'unconscious', 'vitality', 'void']}]},
    'Damage Avoidance': {'kind': 'familiar', 'choice': SAVES},
    'Dragon': {'kind': 'familiar', 'changes_trait': True},
    'Elemental': {'kind': 'familiar', 'changes_trait': True, 'prereq': {'abilities': ['Resistance']},
                  'choice': ELEMENTS},
    'Focused Rejuvenation': {'kind': 'familiar'},
    'Fungus': {'kind': 'familiar', 'changes_trait': True},
    'Independent': {'kind': 'familiar'},
    'Kinspeech': {'kind': 'familiar', 'prereq': {'abilities': ['Speech'], 'level': 6, 'trait': 'animal'}},
    'Major Resistance': {'kind': 'familiar', 'prereq': {'abilities': ['Resistance'], 'level': 8}},
    "Master's Form": {'kind': 'familiar', 'prereq': {'abilities': ['Manual Dexterity', 'Speech']}},
    'Partner in Crime': {'kind': 'familiar'},
    'Plant': {'kind': 'familiar', 'changes_trait': True},
    'Plant Form': {'kind': 'familiar', 'prereq': {'trait': 'plant'}},
    'Resistance': {'kind': 'familiar', 'choice': RESISTED},
    'Skilled': {'kind': 'familiar', 'repeatable': True, 'choice': SKILLED},
    'Speech': {'kind': 'familiar', 'choice': {'from': 'languages'}},
    'Spellcasting': {'kind': 'familiar', 'prereq': {'slot_rank': 6}, 'choice': {'from': 'spells', 'ranks_below': 5}},
    'Toolbearer': {'kind': 'familiar', 'prereq': {'abilities': ['Manual Dexterity']}},
    'Touch Telepathy': {'kind': 'familiar'},
    'Valet': {'kind': 'familiar'},

    # Leshy familiar abilities, for Leshy Familiar Secrets' extra pick (Player Core).
    'Grasping Tendrils': {'kind': 'familiar', 'pool': 'leshy'},
    'Purify Air': {'kind': 'familiar', 'pool': 'leshy'},
    'Verdant Burst': {'kind': 'familiar', 'pool': 'leshy', 'prereq': {'slot_rank': 2}},

    # Player Core 2 p. 170.
    'Item Delivery': {'kind': 'familiar', 'prereq': {'abilities': ['Manual Dexterity']}},
    'Poison Reservoir': {'kind': 'familiar', 'prereq': {'specific': 'Homunculus'}},
    'Second Opinion': {'kind': 'familiar', 'prereq': {'abilities': ['Skilled']}},

    # Master abilities (Player Core p. 214, Player Core 2 p. 170).
    'Absorb Familiar': {'kind': 'master'},
    'Cantrip Connection': {'kind': 'master', 'repeatable': True, 'prereq': {'cantrips': True},
                           'choice': {'from': 'cantrips'}},
    'Familiar Focus': {'kind': 'master', 'prereq': {'has_focus_pool': True}},
    'Innate Surge': {'kind': 'master', 'prereq': {'innate_ancestry_spell': True}},
    'Lifelink': {'kind': 'master'},
    'Recall Familiar': {'kind': 'master'},
    'Restorative Familiar': {'kind': 'master'},
    'Share Senses': {'kind': 'master'},
    'Spell Battery': {'kind': 'master', 'prereq': {'slot_rank': 4}},
    'Spell Delivery': {'kind': 'master'},
    'Extra Alchemy': {'kind': 'master', 'prereq': {'feature': 'Advanced Alchemy'}},
    'Extra Vial': {'kind': 'master', 'prereq': {'feature': 'Versatile Vials'}},

    # Each Witch patron's familiar ability (Player Core), never picked: the patron gives it.
    'Familiar of Ongoing Misery': {'kind': 'patron', 'patron': 'Curse'},
    'Familiar of Balanced Luck': {'kind': 'patron', 'patron': 'Fate'},
    'Familiar of Restored Spirit': {'kind': 'patron', 'patron': 'Fervor'},
    'Familiar of Stalking Night': {'kind': 'patron', 'patron': 'Night'},
    'Familiar of Flowing Script': {'kind': 'patron', 'patron': 'Rune'},
    'Familiar of Keen Senses': {'kind': 'patron', 'patron': 'Wild'},
    'Familiar of Freezing Rime': {'kind': 'patron', 'patron': 'Winter'},
}

HEADER = """\
# Familiar and master abilities, written by scripts/import_foundry_familiars.py. Don't edit by hand:
# the descriptions and rules are Foundry's, and the kind, prerequisites and choices are the HAND table in
# that script. Specific familiars are hand-written in pf2e_specific_familiars.yml.
"""


def in_scope(doc, path):
    if SPECIFIC_FOLDER in path.replace('\\', '/').split('/'):
        return False

    book = ((doc.get('system') or {}).get('publication') or {}).get('title')

    return book in BOOKS or doc.get('name') in ALSO


def abilities(checkout):
    base = os.path.join(checkout, 'packs', 'pf2e', 'familiar-abilities')
    found = {}

    for path in sorted(glob.glob(os.path.join(base, '**', '*.json'), recursive=True)):
        if os.path.basename(path).startswith('_'):
            continue
        doc = json.load(open(path, encoding='utf-8'))
        if in_scope(doc, path):
            found[doc['name']] = doc

    return found


def entry(name, doc, words, refused):
    system = doc.get('system') or {}
    hand = HAND[name]
    out = {'kind': hand['kind']}

    for key in ('pet', 'changes_trait', 'pool', 'patron', 'repeatable', 'prereq', 'choice'):
        if key in hand:
            out[key] = hand[key]

    actions = (system.get('actions') or {}).get('value')
    if actions:
        out['actions'] = actions

    frequency = system.get('frequency') or {}
    if frequency.get('per'):
        out['frequency'] = f"{frequency.get('max', 1)}/{frequency['per']}"

    book = (system.get('publication') or {}).get('title', '')
    out['source'] = 'Player Core' if name in ALSO else book.replace('Pathfinder ', '')
    out['shortdesc'] = rules.plain((system.get('description') or {}).get('value'))

    # Rules the description states and Foundry's rules don't.
    taken = list(hand.get('rules') or [])
    for rule in system.get('rules') or []:
        if not isinstance(rule, dict) or rule.get('key') not in rules.KINDS:
            refused[f"{name}: {rule.get('key') if isinstance(rule, dict) else rule!r} isn't a kind we read"] += 1
            continue
        row = rules.take(rule, refused)
        if row:
            taken.append(rules.worded(row, words))

    if taken:
        out['rules'] = taken

    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    words = rules.strings(args.checkout)
    rules.effect_ids(args.checkout)

    theirs = abilities(args.checkout)
    if not theirs:
        raise SystemExit(f'no familiar abilities under {args.checkout}')

    unclassified = sorted(set(theirs) - set(HAND))
    missing = sorted(set(HAND) - set(theirs))
    if unclassified or missing:
        for name in unclassified:
            print(f'  in scope but not in HAND: {name}')
        for name in missing:
            print(f'  in HAND but not found in scope: {name}')
        raise SystemExit('HAND and Foundry disagree; classify or remove the abilities named')

    refused = collections.Counter()
    catalogue = {name: entry(name, theirs[name], words, refused) for name in sorted(theirs)}

    kinds = collections.Counter(one['kind'] for one in catalogue.values())
    print(f"{len(catalogue)} abilities: " + ', '.join(f'{count} {kind}' for kind, count in sorted(kinds.items())))
    for reason, count in sorted(refused.items()):
        print(f'  refused {count}: {reason}')

    if not args.write:
        print('(dry run; pass --write to write the catalogue)')
        return

    path = os.path.join(CONFIG, OUT)
    body = yaml.safe_dump({SECTION: catalogue}, sort_keys=False, default_flow_style=False, width=1000,
                          allow_unicode=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as handle:
        handle.write('---\n' + HEADER + body)

    foundry_source.record(args.checkout, __file__, [path])
    print(f'wrote {path}')


if __name__ == '__main__':
    main()
