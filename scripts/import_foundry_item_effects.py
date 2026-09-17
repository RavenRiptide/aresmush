#!/usr/bin/env python3
"""Foundry's equipment rules, as `modifies:` blocks on our item catalogue.

Their pf2e system is the reference implementation of these items, so a bonus copied from their
data is a bonus we have not got wrong. What we had before was hand-written: fifty-one items with
a `bonus:` hash, ten of which granted a conditional bonus unconditionally - a Skeleton Key that
helped with Thievery generally rather than with picking a lock.

Only FlatModifier is imported, and only where every selector maps to a domain we have. A rule's
`predicate` is carried across verbatim as `when:`; a rule we cannot express is reported and left
out, never flattened, because a conditional bonus imported without its condition is an item
strictly better than the rules allow.

An item also declares options of its own, with RollOption - a Clandestine Cloak declares
`clandestine-cloak` and predicates its own bonuses on it. Those come across as `grants_options:`,
so wearing the cloak is enough to get what the cloak gives. Only the options some imported row
actually needs are taken, and only where the RollOption carries no predicate of its own; an option
we cannot establish leaves its rows conditional rather than granting them for free.

Usage: scripts/import_foundry_item_effects.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import collections
import glob
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')

# Which of our catalogues holds which kind of item, and whether an item there can be worn or
# invested at all. A bonus on something that is never worn would never apply.
CATALOGUES = ['pf2e_magicitem.yml', 'pf2e_armor.yml', 'pf2e_weapons.yml', 'pf2e_shields.yml',
              'pf2e_gear.yml', 'pf2e_consumables.yml']

# A selector we can express, as the domain we express it as. Foundry's skill selectors are already
# our domains; the rest are named here so an unknown selector is a refusal rather than a guess.
DOMAINS = {'ac': 'ac', 'perception': 'perception', 'saving-throw': 'saving-throw',
           'fortitude': 'fortitude', 'reflex': 'reflex', 'will': 'will',
           'skill-check': 'skill-check', 'initiative': 'perception',
           'land-speed': 'speed', 'speed': 'speed', 'class-dc': 'class-dc',
           'spell-attack': 'spell-attack', 'spell-dc': 'spell-dc'}

SKILLS = ['acrobatics', 'arcana', 'athletics', 'crafting', 'deception', 'diplomacy',
          'intimidation', 'medicine', 'nature', 'occultism', 'performance', 'religion',
          'society', 'stealth', 'survival', 'thievery']

TYPES = {'item', 'circumstance', 'status', 'ability', 'proficiency', 'potency', 'untyped'}


def domain_for(selector):
    if not isinstance(selector, str):
        return None
    slug = selector.strip().lower()
    if slug in DOMAINS:
        return DOMAINS[slug]
    if slug in SKILLS:
        return slug
    if slug.endswith('-lore'):
        return slug
    return None


def documents(node):
    if isinstance(node, list):
        for item in node:
            yield from documents(item)
    elif isinstance(node, dict):
        if 'system' in node and 'type' in node:
            yield node
        for value in node.values():
            yield from documents(value)


def foundry_rules(checkout):
    """name -> (FlatModifier rules, options the item declares for itself)."""
    found = collections.defaultdict(lambda: ([], []))
    base = os.path.join(checkout, 'packs', 'pf2e', 'equipment')

    for path in glob.glob(os.path.join(base, '**', '*.json'), recursive=True):
        try:
            doc = json.load(open(path))
        except Exception:
            continue
        for document in documents(doc):
            system = document.get('system') or {}
            modifiers, options = found[document.get('name')]
            for rule in (system.get('rules') or []):
                if not isinstance(rule, dict):
                    continue
                if rule.get('key') == 'FlatModifier':
                    modifiers.append(rule)
                # A RollOption with a predicate of its own is a state we cannot establish, so its
                # option is not offered and the rows needing it stay conditional.
                elif rule.get('key') == 'RollOption' and rule.get('option') and not rule.get('predicate'):
                    options.append(rule['option'])

    return found


def as_row(rule):
    """One `modifies:` row, or a reason we cannot express the rule."""
    selectors = rule.get('selector')
    selectors = selectors if isinstance(selectors, list) else [selectors]

    domains = [domain_for(one) for one in selectors]
    if any(domain is None for domain in domains):
        unknown = [s for s, d in zip(selectors, domains) if d is None]
        return None, f'selector {unknown}'

    value = rule.get('value')
    if not isinstance(value, (int, str)):
        return None, f'value {value!r}'
    if isinstance(value, str) and '{item|id}' in value:
        return None, 'value names the item by id'

    kind = rule.get('type') or 'untyped'
    if kind not in TYPES:
        return None, f'type {kind!r}'

    # Damage is its own arithmetic and not a figure on the sheet yet.
    if rule.get('damageType') or rule.get('damageCategory') or rule.get('critical'):
        return None, 'damage'

    row = {'domain': domains[0] if len(domains) == 1 else domains,
           'type': kind,
           'value': value if isinstance(value, str) else int(value)}

    predicate = rule.get('predicate')
    if predicate:
        row['when'] = predicate

    return row, None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    theirs = foundry_rules(args.checkout)
    if not theirs:
        raise SystemExit(f'no equipment rules under {args.checkout}')

    refused = collections.Counter()
    written = 0
    items = 0
    report = []

    for name in CATALOGUES:
        path = os.path.join(CONFIG, name)
        if not os.path.exists(path):
            continue
        text = open(path).read()
        additions = {}

        for item, (rules, declared) in theirs.items():
            if not item or not re.search(rf'^  {re.escape(item)}:$', text, re.M):
                continue
            rows = []
            for rule in rules:
                row, why = as_row(rule)
                if row:
                    rows.append(row)
                else:
                    refused[why] += 1
            if not rows:
                continue

            # Only the options the rows we imported actually ask about.
            wanted = json.dumps([row.get('when') for row in rows])
            needed = [option for option in dict.fromkeys(declared) if f'"{option}"' in wanted]

            additions[item] = (rows, needed)

        for item, (rows, needed) in additions.items():
            items += 1
            written += len(rows)
            report.append((name, item, rows, needed))

        if args.write and additions:
            open(path, 'w').write(insert(text, additions))

    print(f'{items} items in our catalogue, {written} modifies rows'
          f'{" written" if args.write else " (dry run)"}')
    print('\nrules refused rather than flattened:')
    for why, count in refused.most_common(12):
        print(f'  {count:5d}  {why}')
    granting = sum(1 for _n, _i, _r, needed in report if needed)
    print(f'{granting} items declare an option their own rows need')

    print('\nfirst twenty items:')
    for name, item, rows, needed in report[:20]:
        print(f'  {item} ({name})' + (f'  grants {needed}' if needed else ''))
        for row in rows:
            when = f"  when {json.dumps(row['when'])}" if 'when' in row else ''
            print(f"      {row['domain']} {row['type']} {row['value']}{when}")


def yaml_rows(entry, indent='    '):
    """`modifies:` as YAML, at the indentation an item's keys sit at."""
    rows, needed = entry
    out = []
    if needed:
        out.append(f'{indent}grants_options:')
        out.extend(f'{indent}  - {option}' for option in needed)
    out.append(f'{indent}modifies:')
    for row in rows:
        domain = row['domain']
        if isinstance(domain, list):
            out.append(f'{indent}  - domain:')
            out.extend(f'{indent}      - {one}' for one in domain)
        else:
            out.append(f'{indent}  - domain: {domain}')
        out.append(f"{indent}    type: {row['type']}")
        out.append(f"{indent}    value: \"{row['value']}\"")
        if 'when' in row:
            out.append(f"{indent}    when: {json.dumps(row['when'])}")
    return out


def insert(text, additions):
    """A `modifies:` block under each named item, replacing one already there."""
    lines = text.split('\n')
    out = []
    pending = None

    for line in lines:
        header = re.match(r'^  ([^\s#][^:]*):$', line)
        if header:
            if pending:
                out.extend(yaml_rows(additions[pending]))
            pending = header.group(1) if header.group(1) in additions else None
            out.append(line)
            continue
        # Drop a block already present, so a re-run replaces rather than duplicates.
        if re.match(r'^    (?:modifies|grants_options):$', line):
            pending_drop = True
            out.append('\x00')
            continue
        out.append(line)

    if pending:
        out.extend(yaml_rows(additions[pending]))

    text = '\n'.join(out)
    text = text if text.endswith('\n') else text + '\n'
    text = re.sub(r'\x00\n(?:      .*\n|    .*\n)*?(?=  \S|\Z)', '', text)

    return text


main()
