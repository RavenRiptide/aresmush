#!/usr/bin/env python3
"""Foundry's rule elements, as `rules:` blocks on our conditions, items and feats.

Their pf2e system is the reference implementation of these mechanics, so a rule copied from their
data is a rule we have not got wrong. What this replaced was hand-written, and measurably wrong in
the same direction every time: of 51 item bonuses, 10 granted a conditional bonus unconditionally,
and of our 14 hand-written conditions, Unconscious penalised the wrong save.

Rows are copied field for field - `key`, `selector`, `value`, `type`, `predicate`, `diceNumber`,
`dieSize` - because a translation is a place to introduce an error. A rule is taken only when its
kind is one `Pf2e::Rules` implements, every selector maps to a domain we can reach, and every field
is one we read. Anything else is reported and left out, never flattened: a conditional bonus
imported without its condition is an item strictly better than the rules allow.

Usage: scripts/import_foundry_rules.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import collections
import glob
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')

# Which Foundry pack feeds which of our catalogues. A feat's name is matched against the merged feat
# config, which is spread over several files.
SOURCES = [
    ('conditions', ['pf2e_conditions.yml']),
    ('equipment', ['pf2e_magicitem.yml', 'pf2e_armor.yml', 'pf2e_weapons.yml', 'pf2e_shields.yml',
                   'pf2e_gear.yml', 'pf2e_consumables.yml']),
    ('feats', ['pf2e_feat_ancestry.yml', 'pf2e_feat_class.yml', 'pf2e_feat_dedication.yml',
               'pf2e_feat_general.yml', 'pf2e_feat_skill.yml']),
]

# The kinds Pf2e::Rules implements, and the fields it reads for each.
KINDS = {
    'FlatModifier': {'key', 'selector', 'value', 'type', 'ability', 'min', 'max', 'damageType',
                     'damageCategory', 'critical', 'predicate', 'slug', 'label', 'hideIfDisabled'},
    'DamageDice': {'key', 'selector', 'diceNumber', 'dieSize', 'damageType', 'category', 'critical',
                   'predicate', 'slug', 'label', 'hideIfDisabled', 'override', 'tags'},
    # placement and mergeable position a toggle in Foundry's character sheet, which is not a mechanic
    # and not an interface we have.
    'RollOption': {'key', 'option', 'domain', 'toggleable', 'value', 'predicate', 'slug', 'label',
                   'placement', 'mergeable'},
}

# A RollOption has no selector; it declares a circumstance rather than reaching a statistic.
SELECTORLESS = {'RollOption'}

TYPES = {'item', 'circumstance', 'status', 'ability', 'proficiency', 'potency', 'untyped'}

SKILLS = {'acrobatics', 'arcana', 'athletics', 'crafting', 'deception', 'diplomacy', 'intimidation',
          'medicine', 'nature', 'occultism', 'performance', 'religion', 'society', 'stealth',
          'survival', 'thievery'}

ATTRIBUTES = {'str', 'dex', 'con', 'int', 'wis', 'cha'}

# Domains Pf2e::Domains can produce that are not derived from a name.
PLAIN = ({'hp', 'ac', 'perception', 'saving-throw', 'fortitude', 'reflex', 'will', 'skill-check',
          'lore-skill-check', 'class-dc', 'class', 'spell-dc', 'spell-attack', 'all', 'check',
          'attack', 'attack-roll', 'strike-attack-roll', 'all-speeds', 'initiative'}
         | SKILLS
         | {f'{a}-based' for a in ATTRIBUTES}
         | {f'{a}-skill-check' for a in ATTRIBUTES}
         | {f'{a}-damage' for a in ATTRIBUTES}
         | {f'{a}-attack' for a in ATTRIBUTES})

# `{item|id}` is the item naming itself, which Pf2e::Effects resolves against the item's own id.
SELF_REFERENCE = re.compile(r'^\{item\|_?id\}(-.*)?$')

# A selector naming something off the weapon: its name, its group, its base type. These are domains
# we produce, so they are taken; an interpolation we cannot resolve is not.
DERIVED = re.compile(r'^[a-z0-9]+(?:-[a-z0-9]+)*-(?:damage|speed|attack|attack-roll'
                     r'|base-attack-roll|group-attack-roll|weapon-group-damage|base-damage'
                     r'|base-type-damage|strike-damage)$')

INTERPOLATION = re.compile(r'\{[^}]*\}')


def selector_ok(selector):
    if not isinstance(selector, str):
        return False
    slug = selector.strip()
    if SELF_REFERENCE.match(slug):
        return True
    if INTERPOLATION.search(slug):
        return False
    if slug in PLAIN or slug == 'damage' or slug.endswith('-lore'):
        return True
    return bool(DERIVED.match(slug))


def documents(node):
    if isinstance(node, list):
        for item in node:
            yield from documents(item)
    elif isinstance(node, dict):
        if 'system' in node and 'type' in node:
            yield node
        for value in node.values():
            yield from documents(value)


def foundry(checkout, pack):
    """name -> (rules, options the item declares for itself)."""
    found = collections.defaultdict(lambda: ([], []))
    base = os.path.join(checkout, 'packs', 'pf2e', pack)

    for path in glob.glob(os.path.join(base, '**', '*.json'), recursive=True):
        try:
            doc = json.load(open(path))
        except Exception:
            continue
        for document in documents(doc):
            rules, options = found[document.get('name')]
            for rule in ((document.get('system') or {}).get('rules') or []):
                if not isinstance(rule, dict):
                    continue
                if rule.get('key') in KINDS:
                    rules.append(rule)

    return found


def take(rule, refused):
    """The rule as we would write it, or None with a reason recorded."""
    fields = KINDS[rule['key']]

    if rule['key'] not in SELECTORLESS and 'selector' not in rule:
        refused['no selector'] += 1
        return None

    strays = set(rule) - fields
    if strays:
        refused[f'field {sorted(strays)}'] += 1
        return None

    if rule['key'] not in SELECTORLESS:
        selectors = rule['selector'] if isinstance(rule['selector'], list) else [rule['selector']]
        bad = [s for s in selectors if not selector_ok(s)]
        if bad:
            refused[f'selector {bad}'] += 1
            return None

    if rule['key'] == 'FlatModifier':
        if rule.get('type') and rule['type'] not in TYPES:
            refused[f"type {rule['type']!r}"] += 1
            return None
        if not isinstance(rule.get('value'), (int, str)):
            refused[f"value {rule.get('value')!r}"] += 1
            return None

    # Keep only the fields we read, in a stable order, so a re-run produces the same file.
    order = ['key', 'option', 'domain', 'toggleable', 'selector', 'type', 'ability', 'value', 'min',
             'max', 'diceNumber', 'dieSize', 'damageType', 'damageCategory', 'category', 'critical',
             'override', 'label', 'predicate']

    return {field: rule[field] for field in order if field in rule}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    refused = collections.Counter()
    totals = collections.Counter()

    for pack, catalogues in SOURCES:
        theirs = foundry(args.checkout, pack)
        if not theirs:
            raise SystemExit(f'no {pack} under {args.checkout}')

        for name in catalogues:
            path = os.path.join(CONFIG, name)
            if not os.path.exists(path):
                continue
            text = open(path).read()
            additions = {}

            for item, (rules, declared) in theirs.items():
                if not item or not re.search(rf'^  {re.escape(item)}:$', text, re.M):
                    continue
                rows = [row for row in (take(rule, refused) for rule in rules) if row]
                if not rows:
                    continue
                additions[item] = (rows, [])

            totals[pack] += len(additions)
            totals[f'{pack} rows'] += sum(len(rows) for rows, _ in additions.values())

            if args.write and additions:
                open(path, 'w').write(insert(text, additions))

    print('written' if args.write else 'dry run')
    for pack, _ in SOURCES:
        print(f"  {pack}: {totals[pack]} entries, {totals[f'{pack} rows']} rules")
    print('\nrules refused rather than flattened:')
    for why, count in refused.most_common(20):
        print(f'  {count:5d}  {why}')


def yaml_value(value, indent):
    """A rule's field as YAML: a scalar inline, anything structured as JSON, which YAML reads."""
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value)
    return json.dumps(value)


def yaml_rows(entry, indent='    '):
    rows, _unused = entry
    out = [f'{indent}rules:']
    for row in rows:
        first = True
        for field, value in row.items():
            lead = '  - ' if first else '    '
            out.append(f'{indent}{lead}{field}: {yaml_value(value, indent)}')
            first = False
    return out


def insert(text, additions):
    """A `rules:` block under each named entry, replacing one already there.

    Walked line by line rather than matched: an entry's keys sit at four spaces and a block's rows at
    six or more, so a block being replaced ends at the first line that is not one of its rows.
    """
    out = []
    pending = None
    dropping = False

    for line in text.split('\n'):
        if dropping:
            if re.match(r'^ {6,}\S', line) or not line.strip():
                continue
            dropping = False

        if re.match(r'^    (?:rules|grants_options|modifies|affected_stat):\s*$', line):
            dropping = True
            continue

        header = re.match(r'^  ([^\s#][^:]*):$', line)
        if header:
            if pending:
                out.extend(yaml_rows(additions[pending]))
            pending = header.group(1) if header.group(1) in additions else None

        out.append(line)

    if pending:
        out.extend(yaml_rows(additions[pending]))

    text = '\n'.join(out)

    return text if text.endswith('\n') else text + '\n'


main()
