#!/usr/bin/env python3
"""Foundry's actions, as a catalogue of things a character can do.

Two kinds of thing are actions. Their `actions` pack holds the basic, skill and class actions - Take
Cover, Rage, Hunt Prey. And a great many feats are themselves actions - a stance, a reaction - which our
feat catalogue already holds, so only what makes them actions is added here: what they cost, and the
effect they put on the one who uses them.

That effect is Foundry's `selfEffect`: using Rage puts you under Effect: Rage. It names an effect in
`pf2e_effects.yml`, and using the action is what applies it.

The rules an action carries for as long as a character owns it are counted rather than written: they
belong with how a use of it becomes a roll - Power Attack's extra die - which is not built yet.

Usage: scripts/import_foundry_actions.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import collections
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import import_foundry_rules as rules  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')
OUT = 'pf2e_actions.yml'
DESCRIPTION = 1200

# What an action costs, in Foundry's own words.
TYPES = {'action', 'reaction', 'free', 'passive'}


# Their actions pack is filed by whose an action is: these folders are everyone's, and any other - a
# class, an archetype, an ancestry, a heritage - belongs to whoever has the feat or feature of its name.
COMMON = {'basic', 'skill', 'exploration', 'downtime'}


def documents(checkout, pack):
    base = os.path.join(checkout, 'packs', 'pf2e', pack)

    for path in sorted(glob.glob(os.path.join(base, '**', '*.json'), recursive=True)):
        try:
            doc = json.load(open(path))
        except Exception:
            continue

        if isinstance(doc, dict) and isinstance(doc.get('system'), dict) and doc.get('name'):
            doc['_folders'] = os.path.relpath(os.path.dirname(path), base).split(os.sep)
            yield doc


def effect_names():
    import yaml

    return set((yaml.safe_load(open(os.path.join(CONFIG, 'pf2e_effects.yml'))) or {}).get('pf2e_effects', {}))


def stocked_feats():
    import yaml

    names = set()

    for path in glob.glob(os.path.join(CONFIG, 'pf2e_feat_*.yml')):
        for block in (yaml.safe_load(open(path)) or {}).values():
            if isinstance(block, dict):
                names |= set(block)

    return names


def entry_of(doc, source, effects, counted):
    system = doc['system']
    kind = (system.get('actionType') or {}).get('value') or 'passive'
    cost = (system.get('actions') or {}).get('value')
    effect = (system.get('selfEffect') or {}).get('name')

    for rule in system.get('rules') or []:
        if isinstance(rule, dict):
            counted[rule.get('key')] += 1

    entry = {'from': source, 'type': kind if kind in TYPES else 'passive',
             'traits': (system.get('traits') or {}).get('value') or []}

    # Whose it is: everyone's, or what kind of thing grants it - a class, an archetype, a heritage.
    if source == 'action':
        folders = doc.get('_folders') or ['']
        entry['for'] = 'everyone' if folders[0] in COMMON else folders[0]

    if cost:
        entry['cost'] = cost
    if system.get('category'):
        entry['category'] = system['category']
    if system.get('frequency'):
        entry['frequency'] = {'max': system['frequency'].get('max', 1), 'per': system['frequency'].get('per')}
    if effect:
        entry['self_effect'] = effect if effect in effects else None
        if effect not in effects:
            counted[f'a self-effect our catalogue lacks: {effect}'] += 1
    if source == 'action':
        entry['description'] = rules.plain((system.get('description') or {}).get('value'), DESCRIPTION)

    return entry


def value(held):
    if isinstance(held, bool):
        return 'true' if held else 'false'
    if held is None:
        return 'null'
    if isinstance(held, (int, float)):
        return str(held)

    return json.dumps(held, ensure_ascii=False)


def rendered(entries):
    lines = ['---', 'pf2e_actions:']

    for name, entry in sorted(entries.items()):
        lines.append(f'  {json.dumps(name, ensure_ascii=False)}:')

        for field in ('from', 'for', 'type', 'cost', 'category', 'traits', 'frequency', 'self_effect',
                      'description'):
            if field in entry and entry[field] is not None:
                lines.append(f'    {field}: {value(entry[field])}')

    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    effects = effect_names()
    feats = stocked_feats()
    counted = collections.Counter()
    entries = {}

    for doc in documents(args.checkout, 'actions'):
        entries[doc['name']] = entry_of(doc, 'action', effects, counted)

    # A feat that is an action - a stance, a reaction - is one because of what it costs; the feat itself
    # stays where it is.
    feat_actions = 0
    for doc in documents(args.checkout, 'feats'):
        kind = ((doc['system'].get('actionType') or {}).get('value'))
        if doc['name'] in feats and kind in ('action', 'reaction', 'free') and doc['name'] not in entries:
            entries[doc['name']] = entry_of(doc, 'feat', effects, collections.Counter())
            feat_actions += 1

    if args.write:
        open(os.path.join(CONFIG, OUT), 'w').write(rendered(entries))

    selves = sum(1 for entry in entries.values() if entry.get('self_effect'))

    print('written' if args.write else 'dry run')
    print(f'  {len(entries)} actions: {len(entries) - feat_actions} from their actions, {feat_actions} feats')
    print(f'  {selves} put an effect on whoever uses them')
    print('\nwhat their actions carry that is not read yet:')
    for why, count in counted.most_common(20):
        print(f'  {count:5d}  {why}')


if __name__ == '__main__':
    main()
