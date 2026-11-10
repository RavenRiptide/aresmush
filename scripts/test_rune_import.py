"""python -m unittest scripts/test_rune_import.py"""
import collections
import os
import sys
import unittest

import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import import_foundry_runes as runes  # noqa: E402


def item(name, usage='etched-onto-a-weapon', book='Pathfinder GM Core', level=8, price=50000,
         rarity='common', traits=None):
    return {'name': name, 'usage': usage, 'book': book, 'level': level, 'price': price, 'rarity': rarity,
            'traits': traits or ['magical']}


class JoiningTableAndPack(unittest.TestCase):

    def test_a_graded_rune_joins_its_pack_item(self):
        self.assertEqual(runes.joined('greaterAnchoring'), runes.joined('Anchoring (Greater)'))

    def test_a_reinforcing_rune_joins_without_the_word_rune(self):
        self.assertEqual(runes.joined('Minor Reinforcing'), runes.joined('Reinforcing Rune (Minor)'))

    def test_a_potency_rune_joins_by_its_bonus(self):
        self.assertEqual(runes.joined('Weapon Potency (+1)'), runes.joined('Weapon Potency (+1)'))
        self.assertNotEqual(runes.joined('Weapon Potency (+1)'), runes.joined('Armor Potency (+1)'))

    def test_two_words_join_one_camel_slug(self):
        self.assertEqual(runes.joined('ghostTouch'), runes.joined('Ghost Touch'))


class Naming(unittest.TestCase):

    def test_the_grade_goes_in_front(self):
        self.assertEqual(runes.shown('Striking (Greater)'), 'Greater Striking')
        self.assertEqual(runes.shown('Weapon Potency (+1)'), '+1 Weapon Potency')
        self.assertEqual(runes.shown('Reinforcing Rune (Minor)'), 'Minor Reinforcing')

    def test_a_pack_only_rune_gets_a_slug_in_the_tables_style(self):
        self.assertEqual(runes.slug_of('Energy-Resistant (Greater)'), 'greaterEnergyResistant')
        self.assertEqual(runes.slug_of("Forgefather's Seal"), 'forgefathersSeal')


class Prices(unittest.TestCase):

    def test_coins_are_counted_in_copper(self):
        self.assertEqual(runes.price_of({'value': {'gp': 500}}), 50000)
        self.assertEqual(runes.price_of({'value': {'pp': 1, 'gp': 2, 'sp': 3, 'cp': 4}}), 1234)

    def test_no_price_is_nothing(self):
        self.assertEqual(runes.price_of({}), 0)
        self.assertEqual(runes.price_of(None), 0)


class Books(unittest.TestCase):

    def test_only_the_three_books_come_in(self):
        for book in ('Pathfinder GM Core', 'Pathfinder Player Core', 'Pathfinder Player Core 2'):
            self.assertTrue(runes.in_books(item('Flaming', book=book)))

        self.assertFalse(runes.in_books(item('Bane', book='Pathfinder Lost Omens Gods & Magic')))
        self.assertFalse(runes.in_books(None))


class Usages(unittest.TestCase):

    def test_holy_excludes_unholy_despite_the_key_naming_holy(self):
        refused = collections.Counter()

        self.assertEqual(runes.usage_of(item('Holy', 'etched-onto-weapon-wo-holy-rune'), refused),
                         ('weapon', ['unholy']))
        self.assertEqual(runes.usage_of(item('Unholy', 'etched-onto-weapon-wo-unholy-rune'), refused),
                         ('weapon', ['holy']))

    def test_a_usage_nothing_checks_is_refused_and_counted(self):
        refused = collections.Counter()

        self.assertIsNone(runes.usage_of(item('Cunning', 'etched-onto-piercing-or-slashing-weapon'), refused))
        self.assertEqual(sum(refused.values()), 1)

    def test_each_usage_names_the_kind_of_item(self):
        for usage, _excludes in runes.USAGES.values():
            self.assertIn(runes.kind_of(usage), ('weapon', 'armor', 'shield'))


class Entries(unittest.TestCase):

    def test_the_pack_gives_level_price_rarity_and_usage(self):
        refused = collections.Counter()
        table = {'level': 9, 'price': 100, 'rarity': 'common', 'traits': ['magical']}
        pack = item('Shockwave', 'etched-onto-bludgeoning-weapon', level=13, price=300000, rarity='uncommon')

        entry = runes.entry_of('shockwave', table, 'weapon', refused, {}, pack)

        self.assertEqual((entry['level'], entry['price'], entry['rarity']), (13, 300000, 'uncommon'))
        self.assertEqual(entry['usage'], 'bludgeoning-weapon')

    def test_a_pack_only_rune_has_no_rules_and_its_kind_from_its_usage(self):
        entry = runes.pack_entry(item('Energy-Resistant', 'etched-onto-armor', price=42000),
                                 collections.Counter())

        self.assertEqual(entry['kind'], 'armor')
        self.assertEqual(entry['slug'], 'energyResistant')
        self.assertEqual(entry['rules'], [])


class Rendering(unittest.TestCase):

    def test_it_writes_usage_and_excludes(self):
        entries = {'Holy': {'slug': 'holy', 'kind': 'weapon', 'usage': 'weapon', 'excludes': ['unholy'],
                            'level': 11, 'price': 140000, 'rarity': 'common', 'traits': ['holy'], 'rules': []}}

        written = yaml.safe_load(runes.rendered(entries))

        self.assertEqual(list(written), ['pf2e_runes'])
        self.assertEqual(written['pf2e_runes']['Holy']['excludes'], ['unholy'])
        self.assertEqual(written['pf2e_runes']['Holy']['usage'], 'weapon')

    def test_the_fundamental_runes_are_a_file_of_their_own(self):
        fundamental = {'shield': {'reinforcing': {1: {'name': 'Minor Reinforcing', 'level': 4, 'price': 7500,
                                                      'rarity': 'common', 'hardness': {'increase': 3, 'max': 8},
                                                      'hp': {'increase': 44, 'max': 64}}}}}

        written = yaml.safe_load(runes.rendered_fundamental(fundamental))

        self.assertEqual(list(written), ['pf2e_fundamental_runes'])
        self.assertEqual(written['pf2e_fundamental_runes']['shield']['reinforcing'][1]['hardness'],
                         {'increase': 3, 'max': 8})


if __name__ == '__main__':
    unittest.main()
