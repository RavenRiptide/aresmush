#!/usr/bin/env python3
"""Foundry's property runes, as a catalogue of `rules:` like every other catalogue here.

A property rune is the one piece of their mechanics that does not live in their packs: the packs carry
a rune as an item with an empty `rules` array, and what the rune *does* is a table in their code
(`src/module/item/physical/runes.ts`). So this reads that table and writes the same rule elements the
rest of our catalogues carry, which is what makes a *flaming* rune add its 1d6 fire rather than being a
word on an item sheet.

The table is TypeScript rather than JSON, so it is evaluated by node after the type annotations and the
handful of function-valued fields are taken out. Nothing is translated on the way through: a rune's
`damage.additional` is what Foundry turns into damage dice (`getPropertyRuneDamage`), and it becomes a
`DamageDice` row with the same fields. What we cannot read is refused and counted, never flattened.

Selectors are `{item|id}-…`, because a rune belongs to the weapon it is etched on: `Pf2e::Effects`
builds one source per rune per weapon and the weapon's own damage domain is the one it reaches.

Only runes from GM Core, Player Core, and Player Core 2 come in. The table has no book, and no word on
what a rune may be etched onto; the rune's item in their equipment pack has both, along with the book's
level, price, and rarity. So the pack decides which runes come in and what they cost and fit, and the
table adds what they do. A rune in those books that the table lacks comes in from its pack item alone,
with no rules.

The fundamental runes - potency, striking, resilient, reinforcing - are written to a file of their own,
`pf2e_fundamental_runes.yml`, one row per grade, because the vendor prices each grade and a reinforcing rune
changes the shield's Hardness and HP.

Usage: scripts/import_foundry_runes.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import collections
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import foundry_source  # noqa: E402
import import_foundry_rules as wording  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')
SOURCE = 'src/module/item/physical/runes.ts'
PACK = os.path.join('packs', 'pf2e', 'equipment')
OUT = 'pf2e_runes.yml'
OUT_FUNDAMENTAL = 'pf2e_fundamental_runes.yml'

# Their price is in gold; this game counts copper.
GOLD = 100
COINS = {'pp': 1000, 'gp': 100, 'sp': 10, 'cp': 1}

# The books this game takes runes from, as their packs name them.
BOOKS = {'Pathfinder GM Core', 'Pathfinder Player Core', 'Pathfinder Player Core 2'}

# What a pack item's `usage` says a rune is etched onto, as the word the fit check reads. A usage not
# here is refused, so a rune never comes in that nothing can check.
#
# Their two holy keys are named backwards: *holy* carries `weapon-wo-holy-rune`, whose label reads "a
# weapon without an unholy rune". The label is the rule, so each becomes a weapon rune that excludes
# the other.
USAGES = {
    'etched-onto-a-weapon': ('weapon', []),
    'etched-onto-melee-weapon': ('melee-weapon', []),
    'etched-onto-thrown-weapon': ('thrown-weapon', []),
    'etched-onto-bludgeoning-weapon': ('bludgeoning-weapon', []),
    'etched-onto-slashing-melee-weapon': ('slashing-melee-weapon', []),
    'etched-onto-piercing-or-slashing-melee-weapon': ('piercing-or-slashing-melee-weapon', []),
    'etched-onto-weapon-wo-holy-rune': ('weapon', ['unholy']),
    'etched-onto-weapon-wo-unholy-rune': ('weapon', ['holy']),
    'etched-onto-armor': ('armor', []),
    'etched-onto-light-armor': ('light-armor', []),
    'etched-onto-med-heavy-armor': ('medium-or-heavy-armor', []),
    'etched-onto-lm-nonmetal-armor': ('light-or-medium-nonmetal-armor', []),
    'etched-onto-a-shield': ('shield', []),
}

# The fundamental runes, by the table that holds them and the item they go on.
FUNDAMENTALS = (('FUNDAMENTAL_WEAPON_RUNE_DATA', 'weapon'), ('FUNDAMENTAL_ARMOR_RUNE_DATA', 'armor'),
                ('FUNDAMENTAL_SHIELD_RUNE_DATA', 'shield'))

# What a rune may do that we can read, and what each becomes. Everything else is refused below.
#
#   damage.additional  -> DamageDice, or FlatModifier where it is a flat amount
#   attack.dosAdjustments -> AdjustDegreeOfSuccess
#   attack.notes, damage.notes -> Note, in English, keeping the effects its text links
#
# The rest is named in REFUSALS with the reason.
REFUSALS = {
    'ignoredResistances': 'ignores a resistance, which is the target\'s and not reachable from here',
    'adjustments': 'adjusts a modifier by way of a function rather than a value',
    'strikeAdjustments': 'changes the weapon itself by way of a function',
}

# Foundry's own spelling of an outcome, onto the spelling their packs use - which is the one
# `Pf2e::Degree` reads.
OUTCOMES = {'criticalSuccess': 'to-critical-success', 'success': 'to-success',
            'failure': 'to-failure', 'criticalFailure': 'to-critical-failure'}

DEGREES = {'criticalSuccess', 'success', 'failure', 'criticalFailure'}


def source_text(checkout):
    """The rune table, from a working tree that has it or from the checkout's own history."""
    path = os.path.join(checkout, SOURCE)

    if os.path.exists(path):
        return open(path, encoding='utf-8').read()

    found = subprocess.run(['git', '-C', checkout, 'show', f'HEAD:{SOURCE}'],
                           capture_output=True, text=True, encoding='utf-8')

    if found.returncode != 0:
        raise SystemExit(f'no {SOURCE} in {checkout}')

    return found.stdout


def literal(text, name):
    """The object literal assigned to `name`, as source."""
    start = text.index(f'const {name}')
    # The declaration carries a type of its own, which is braces too: the value is after the `=`.
    opening = text.index('{', text.index('=', start))
    depth = 0

    for i in range(opening, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[opening:i + 1]

    raise SystemExit(f'{name} is not closed')


def without_functions(block, dropped):
    """The literal with its function-valued fields taken out, and their names recorded.

    Eight fields in the table are arrow functions - "double the critical specialization effect for a
    pick" and the like. A function is behaviour we cannot carry across as data, so the field is removed
    and the rune keeps whatever else it has.
    """
    out = []
    i = 0
    # `key: (args) => …` or `key: (args): Type => …`
    pattern = re.compile(r'(\w+):\s*(?=\()')

    while i < len(block):
        found = pattern.search(block, i)

        if not found:
            out.append(block[i:])
            break

        after = skip_arrow(block, found.end())

        if after is None:
            out.append(block[i:found.end()])
            i = found.end()
            continue

        dropped[found.group(1)] += 1
        out.append(block[i:found.start()])
        i = after

    return ''.join(out)


def skip_arrow(text, start):
    """The index past an arrow function beginning at `start`, or None if that is not one."""
    end = matching(text, start, '(', ')')

    if end is None:
        return None

    rest = text[end:]
    arrow = re.match(r'\s*(?::\s*[\w<>|\[\] ]+)?\s*=>\s*', rest)

    if not arrow:
        return None

    body = end + arrow.end()

    if text[body] == '{':
        closing = matching(text, body, '{', '}')
        return past_comma(text, closing)

    # An expression body, which runs to the comma that ends the field.
    depth = 0

    for i in range(body, len(text)):
        if text[i] in '([{':
            depth += 1
        elif text[i] in ')]}':
            if depth == 0:
                return i
            depth -= 1
        elif text[i] == ',' and depth == 0:
            return i + 1

    return len(text)


def matching(text, start, opener, closer):
    depth = 0

    for i in range(start, len(text)):
        if text[i] == opener:
            depth += 1
        elif text[i] == closer:
            depth -= 1
            if depth == 0:
                return i + 1

    return None


def past_comma(text, index):
    rest = re.match(r'\s*,', text[index:])

    return index + rest.end() if rest else index


def evaluated(block):
    """The literal as data. Node reads it, because it is JavaScript and not JSON."""
    # `new Predicate([…])` is a predicate written the long way; the argument is the predicate.
    block = re.sub(r'new Predicate\(', '(', block)
    # Numeric separators and Infinity are JavaScript's, and JSON has neither.
    block = re.sub(r'(\d)_(\d)', r'\1\2', block)
    block = block.replace('Infinity', '1e999')

    with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False) as handle:
        handle.write(f'console.log(JSON.stringify({block}));\n')
        script = handle.name

    try:
        found = subprocess.run(['node', script], capture_output=True, text=True, encoding='utf-8')

        if found.returncode != 0:
            raise SystemExit(f'node could not read the table: {found.stderr.strip()[:400]}')

        return json.loads(found.stdout)
    finally:
        os.unlink(script)


def titled(slug):
    """`greaterAnchoring` as a player would type it."""
    spaced = re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', slug)

    return spaced[0].upper() + spaced[1:]


def dice_row(entry, slug):
    """One of a rune's extra damage dice, as a `DamageDice`."""
    row = {'key': 'DamageDice', 'selector': '{item|id}-damage', 'slug': slug,
           'diceNumber': entry.get('diceNumber', 1), 'dieSize': entry.get('dieSize', 'd6')}

    for field, key in (('damageType', 'damageType'), ('category', 'category'),
                       ('damageCategory', 'category'), ('critical', 'critical'),
                       ('predicate', 'predicate')):
        if entry.get(field) is not None:
            row[key] = entry[field]

    return row


def flat_row(entry, slug):
    """A rune's extra damage that is an amount rather than dice."""
    row = {'key': 'FlatModifier', 'selector': '{item|id}-damage', 'slug': slug,
           'value': entry['modifier']}

    for field, key in (('type', 'type'), ('damageType', 'damageType'),
                       ('damageCategory', 'damageCategory'), ('category', 'damageCategory'),
                       ('critical', 'critical'), ('predicate', 'predicate')):
        if entry.get(field) is not None:
            row[key] = entry[field]

    return row


def outcome_row(entry, slug, refused):
    """A rune that turns one outcome into another: *keen* makes a near miss a critical hit."""
    named = entry.get('adjustments')

    if not isinstance(named, dict) or not named:
        refused['a degree adjustment that is not a mapping'] += 1
        return None

    adjustment = {}

    for outcome, change in named.items():
        amount = (change or {}).get('amount')

        if outcome not in DEGREES or amount not in OUTCOMES:
            refused[f'a degree adjustment of {amount!r}'] += 1
            return None

        adjustment[outcome] = OUTCOMES[amount]

    row = {'key': 'AdjustDegreeOfSuccess', 'selector': '{item|id}-attack', 'slug': slug,
           'adjustment': adjustment}

    if entry.get('predicate'):
        row['predicate'] = entry['predicate']

    return row


def note_row(entry, slug, roll, found):
    """A rune's words for a roll: *crushing*'s clumsy and enfeebled on a critical hit. `roll` is attack or
    damage, which is the domain the note is shown with. The title and text are their localisation keys,
    read in English as the rules importer reads a pack's notes."""
    row = {'key': 'Note', 'selector': f'{{item|id}}-{roll}', 'slug': slug}

    for field in ('outcome', 'predicate', 'title', 'text'):
        if entry.get(field):
            row[field] = entry[field]

    return wording.worded(row, found)


def rules_of(rune, slug, refused, found=None):
    """Everything this rune does that we can read."""
    rows = []
    damage = rune.get('damage') or {}
    attack = rune.get('attack') or {}

    for entry in damage.get('additional') or []:
        rows.append(flat_row(entry, slug) if 'modifier' in entry else dice_row(entry, slug))

    for entry in attack.get('dosAdjustments') or []:
        row = outcome_row(entry, slug, refused)

        if row:
            rows.append(row)

    for roll, holder in (('attack', attack), ('damage', damage)):
        for entry in holder.get('notes') or []:
            rows.append(note_row(entry, slug, roll, found or {}))

    for holder, field in ((damage, 'ignoredResistances'), (damage, 'adjustments')):
        for _ in holder.get(field) or []:
            refused[REFUSALS[field]] += 1

    return rows


def joined(name):
    """The one spelling a rune's table slug and its pack item's name share. The pack writes `Anchoring
    (Greater)` and `Reinforcing Rune (Minor)` where the table writes `greaterAnchoring` and "Minor
    Reinforcing": the grade goes in front, the word "rune" goes, and so does everything but letters and
    digits."""
    text = re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', name).lower()
    text = re.sub(r'\brune\b', '', text).strip()
    graded = re.match(r'(.*?)\s*\((.*)\)\s*$', text)

    if graded:
        text = f'{graded.group(2)} {graded.group(1)}'

    return re.sub(r'[^a-z0-9]', '', text)


def shown(name):
    """A pack item's name as a player types it: `Striking (Greater)` is "Greater Striking", `Weapon
    Potency (+1)` is "+1 Weapon Potency", and `Reinforcing Rune (Minor)` is "Minor Reinforcing"."""
    text = re.sub(r'\s+Rune\b', '', name).strip()
    graded = re.match(r'(.*?)\s*\((.*)\)\s*$', text)

    return f'{graded.group(2)} {graded.group(1)}' if graded else text


def slug_of(name):
    """A slug in the table's own style, for a rune only the pack has: "Greater Energy Resistant" is
    `greaterEnergyResistant`."""
    words = re.findall(r'[a-z0-9]+', shown(name).lower().replace("'", ''))

    return words[0] + ''.join(word.capitalize() for word in words[1:])


def price_of(price):
    """A pack item's price, `{"gp": 500}`, in copper."""
    return sum(int(amount) * COINS[coin] for coin, amount in (price or {}).get('value', price or {}).items()
               if coin in COINS)


def pack_runes(checkout):
    """Every rune item in their equipment pack, by its joined name: what it is etched onto, its book,
    level, price, rarity, and traits."""
    folder = os.path.join(checkout, PACK)

    if not os.path.isdir(folder):
        raise SystemExit(f'no {PACK} in {checkout}')

    items = {}

    for path in sorted(glob.glob(os.path.join(folder, '**', '*.json'), recursive=True)):
        for document in wording.documents(json.load(open(path, encoding='utf-8'))):
            held = document['system']
            usage = (held.get('usage') or {}).get('value') or ''

            if not usage.startswith('etched-onto-'):
                continue

            traits = held.get('traits') or {}
            items[joined(document['name'])] = {
                'name': document['name'], 'usage': usage,
                'book': (held.get('publication') or {}).get('title'),
                'level': (held.get('level') or {}).get('value', 1),
                'price': price_of(held.get('price')),
                'rarity': traits.get('rarity', 'common'),
                'traits': traits.get('value') or []}

    return items


def in_books(item):
    return bool(item) and item['book'] in BOOKS


def usage_of(item, refused):
    """What the rune is etched onto and the runes it can't share an item with, or None when we can't
    read it."""
    found = USAGES.get(item['usage'])

    if not found:
        refused[f"etched onto {item['usage'][len('etched-onto-'):]}, which nothing checks"] += 1

    return found


def kind_of(usage):
    """The kind of item a usage is for, which is what `etch/property` reads."""
    return next(kind for kind in ('weapon', 'armor', 'shield') if usage.endswith(kind))


def entry_of(slug, rune, kind, refused, found=None, item=None):
    """A property rune: what it does from the table, and from its pack item, when it has one, the book's
    level, price, and rarity and what it is etched onto."""
    rules = rules_of(rune, slug, refused, found) if kind == 'weapon' else []
    entry = {'slug': slug, 'kind': kind, 'level': rune.get('level', 1),
             'price': int(rune.get('price', 0) * GOLD), 'rarity': rune.get('rarity', 'common'),
             'traits': rune.get('traits') or [], 'rules': rules}

    if item:
        usage, excludes = usage_of(item, refused) or (None, [])
        entry.update(level=item['level'], price=item['price'], rarity=item['rarity'], usage=usage,
                     excludes=excludes)

    return entry


def pack_entry(item, refused):
    """A property rune in the books that the table lacks. It comes in from its pack item, with no rules."""
    found = usage_of(item, refused)

    if not found:
        return None

    usage, excludes = found

    return {'slug': slug_of(item['name']), 'kind': kind_of(usage), 'usage': usage, 'excludes': excludes,
            'level': item['level'], 'price': item['price'], 'rarity': item['rarity'],
            'traits': item['traits'], 'rules': []}


def fundamentals(text, found, items, dropped):
    """Each grade of each fundamental rune in the books, as `{weapon: {potency: {1: {...}}}}`, and the
    joined names of the pack items they took."""
    out = {}
    taken = set()

    for table, kind in FUNDAMENTALS:
        for rune, grades in evaluated(without_functions(literal(text, table), dropped)).items():
            for grade, data in sorted(grades.items(), key=lambda pair: int(pair[0])):
                if not data:
                    continue

                named = found.get(data.get('name')) or titled(data.get('slug') or rune)
                item = items.get(joined(named))

                if not in_books(item):
                    continue

                taken.add(joined(named))
                row = {'name': shown(item['name']), 'level': item['level'], 'price': item['price'],
                       'rarity': item['rarity']}

                for field, key in (('hardness', 'hardness'), ('maxHP', 'hp')):
                    if data.get(field):
                        row[key] = {'increase': data[field]['increase'], 'max': data[field]['max']}

                out.setdefault(kind, {}).setdefault(rune, {})[int(grade)] = row

    return out, taken


def yaml_value(value, indent):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)

    return json.dumps(value)


def rendered(entries):
    lines = ['---', 'pf2e_runes:']

    for name, entry in sorted(entries.items()):
        lines.append(f'  {name}:')

        for field in ('slug', 'kind', 'usage', 'level', 'price', 'rarity'):
            if field in entry:
                lines.append(f'    {field}: {yaml_value(entry[field], 4)}')

        if entry.get('excludes'):
            lines.append('    excludes:')
            lines.extend(f'      - {yaml_value(one, 6)}' for one in entry['excludes'])

        lines.append('    traits:')
        lines.extend(f'      - {yaml_value(trait, 6)}' for trait in entry['traits'])

        if not entry['rules']:
            continue

        lines.append('    rules:')

        for row in entry['rules']:
            first = True

            for field, value in row.items():
                lead = '  - ' if first else '    '
                lines.append(f'    {lead}{field}: {yaml_value(value, 4)}')
                first = False

    return '\n'.join(lines) + '\n'


def rendered_fundamental(fundamental):
    """The fundamental runes, a file of their own: every config file is one root key."""
    lines = ['---', 'pf2e_fundamental_runes:']

    for kind, runes in fundamental.items():
        lines.append(f'  {kind}:')

        for rune, grades in runes.items():
            lines.append(f'    {rune}:')

            for grade, row in sorted(grades.items()):
                lines.append(f'      {grade}:')
                lines.extend(f'        {field}: {yaml_value(value, 8)}' for field, value in row.items())

    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    text = source_text(args.checkout)
    found = wording.strings(args.checkout)
    wording.effect_ids(args.checkout)
    items = pack_runes(args.checkout)
    dropped = collections.Counter()
    refused = collections.Counter()
    entries = {}
    taken = set()
    elsewhere = []
    unpacked = []

    for name, kind in (('WEAPON_PROPERTY_RUNES', 'weapon'), ('ARMOR_PROPERTY_RUNES', 'armor')):
        table = evaluated(without_functions(literal(text, name), dropped))

        for slug, rune in table.items():
            item = items.get(joined(slug))

            if not item:
                unpacked.append(titled(slug))
                continue
            if not in_books(item):
                elsewhere.append(titled(slug))
                continue

            taken.add(joined(slug))
            entry = entry_of(slug, rune, kind, refused, found, item)

            if entry['usage']:
                entries[titled(slug)] = entry

    fundamental, graded = fundamentals(text, found, items, dropped)
    taken |= graded
    alone = []

    for key, item in sorted(items.items()):
        if key in taken or not in_books(item):
            continue

        entry = pack_entry(item, refused)

        if entry:
            entries[titled(entry['slug'])] = entry
            alone.append(titled(entry['slug']))

    written = {os.path.join(CONFIG, OUT): rendered(entries),
               os.path.join(CONFIG, OUT_FUNDAMENTAL): rendered_fundamental(fundamental)}

    if args.write:
        for path, body in written.items():
            open(path, 'w', encoding='utf-8', newline='\n').write(body)

        foundry_source.record(args.checkout, __file__, list(written))

    carrying = sum(1 for entry in entries.values() if entry['rules'])
    rows = sum(len(entry['rules']) for entry in entries.values())

    print('written' if args.write else 'dry run')
    print(f'  {len(entries)} property runes, {carrying} of them carrying {rows} rules')
    print(f'  {sum(len(grades) for runes in fundamental.values() for grades in runes.values())} '
          'fundamental rune grades')
    print(f"\nfrom their packs alone, with no rules ({len(alone)}): {', '.join(alone)}")
    print(f'\nleft out, from another book ({len(elsewhere)}): {", ".join(sorted(elsewhere))}')
    print(f'\nleft out, with no pack item to give a book ({len(unpacked)}): {", ".join(sorted(unpacked))}')
    print('\nwhat a rune does that is not read:')

    for why, count in refused.most_common(10):
        print(f'  {count:5d}  {why}')

    for field, count in dropped.most_common(10):
        print(f'  {count:5d}  {field}, which is a function in their table')


if __name__ == '__main__':
    main()
