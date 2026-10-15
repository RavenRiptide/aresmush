#!/usr/bin/env python3
"""GM Core's tables for building creatures, from Archives of Nethys, as `game/config/pf2e_creature_benchmarks.yml`.

GM Core gives, for each creature level from -1 to 24, what a figure is at each band: a high AC, a
moderate Strike bonus, a low Hit Points range. The creature checker compares a saved creature's figures
with these (`Pf2e::CreatureBenchmarks`), and flags one above the highest band for its author and for the
admins who approve it.

The tables are read from the Archives' search index, the pages whose ids are listed below, so they are
transcribed by this script from the source and never typed from memory. A cell is kept as the book
prints it, made into data:

  +5            5
  -             nil (the book gives none at that level)
  8-7, +2 to +1 [8, 7], [2, 1]: a range, high end first
  1d6+1 (4)     { formula: 1d6+1, average: 4 }

Usage: scripts/import_creature_benchmarks.py [--write]
"""

import argparse
import datetime
import json
import os
import re
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'game', 'config', 'pf2e_creature_benchmarks.yml')
SEARCH = 'https://elasticsearch.aonprd.com/aon/_search'

# What each page's table is called here, and the GM Core page it is on.
TABLES = {
    'attribute': (2881, 114),
    'perception': (2882, 115),
    'skill': (2885, 116),
    'ac': (2889, 117),
    'save': (2890, 118),
    'hp': (2891, 118),
    'resistance': (2893, 119),
    'strike_attack': (2896, 120),
    'strike_damage': (2897, 120),
    'spell': (2899, 122),
    'area_damage': (2910, 124),
}


def fetched(rules_id):
    query = urllib.parse.urlencode({'q': f'url:"/Rules.aspx?ID={rules_id}"', 'size': 10})
    with urllib.request.urlopen(f'{SEARCH}?{query}') as answer:
        hits = json.load(answer)['hits']['hits']
    for hit in hits:
        markdown = hit['_source'].get('markdown') or ''
        if '<table' in markdown:
            return markdown[markdown.index('<table'):markdown.index('</table>')]
    raise SystemExit(f'No table found on Rules.aspx?ID={rules_id}')


def rows(table):
    found = re.findall(r'<tr>(.*?)</tr>', table, re.S)
    return [[cell.strip().strip('*').strip() for cell in re.findall(r'<td>(.*?)</td>', row, re.S)] for row in found]


def number(text):
    return int(text.replace('–', '-').replace('−', '-').replace('+', ''))


def cell(text):
    text = text.strip()
    if text in ('—', '-', '–', ''):
        return None
    damage = re.match(r'^(\d+d\d+(?:[+-]\d+)?) \((\d+)\)$', text)
    if damage:
        return {'formula': damage.group(1), 'average': int(damage.group(2))}
    spread = re.match(r'^([+-]?\d+)\s*(?:–|to)\s*([+-]?\d+)$', text.replace('−', '-'))
    if spread:
        return [number(spread.group(1)), number(spread.group(2))]
    return number(text)


def column(name):
    return re.sub(r'[^a-z]+', '_', name.lower()).strip('_')


def read(table):
    header, *body = rows(table)
    columns = [column(name) for name in header[1:]]
    levels = {number(row[0]): [cell(one) for one in row[1:]] for row in body}
    return {'columns': columns, 'levels': levels}


def yaml_value(value):
    if value is None:
        return 'null'
    if isinstance(value, list):
        return '[' + ', '.join(yaml_value(one) for one in value) + ']'
    if isinstance(value, dict):
        return '{ ' + ', '.join(f'{key}: {yaml_value(one)}' for key, one in value.items()) + ' }'
    return str(value)


def rendered(tables, day):
    lines = ['# GM Core\'s tables for building creatures (pp. 114-124), by creature level: what a figure is at each band.',
             f'# Written by scripts/import_creature_benchmarks.py from Archives of Nethys on {day}; run it again rather than',
             '# editing by hand. A range is [high end, low end]; damage is its formula and its average.',
             'pf2e_creature_benchmarks:']
    for name, held in tables.items():
        rules_id, page = TABLES[name]
        lines.append(f'  {name}:')
        lines.append(f'    source: "GM Core p. {page}, Archives of Nethys Rules.aspx?ID={rules_id}"')
        lines.append(f'    columns: [{", ".join(held["columns"])}]')
        lines.append('    levels:')
        for level, cells in held['levels'].items():
            lines.append(f'      {level}: {yaml_value(cells)}')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    tables = {name: read(fetched(rules_id)) for name, (rules_id, _page) in TABLES.items()}
    text = rendered(tables, datetime.date.today().isoformat())

    if args.write:
        open(OUT, 'w').write(text)
        print(f'written {OUT}')
    else:
        print(text[:2000])
    for name, held in tables.items():
        print(f'  {name}: {held["columns"]}, levels {min(held["levels"])} to {max(held["levels"])}')


if __name__ == '__main__':
    main()
