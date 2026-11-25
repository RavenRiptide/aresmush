module AresMUSH
  module Pf2egear

    # The Inventory tab of a character's profile, as plain data: what `gear` shows, with each bag's contents.
    module InventoryView

      def self.of(char)
        { name: char.name,
          money: Pf2egear.display_money(char.pf2_money.to_i),
          bulk: bulk(char),
          weapons: Inventory.held(char, 'weapons').map { |item| worn(char, item, 'weapons', Pf2eCombat.get_weapon_prof(char, item.name)) },
          armor: Inventory.held(char, 'armor').map { |item| worn(char, item, 'armor', Pf2eCombat.get_armor_prof(char, item.name)) },
          shields: listed(char.shields).map { |item| worn(char, item, 'shields', nil).merge(hp: Pf2egear.display_shield_hp(item)) },
          worn: own(listed(char.magic_items)).map { |item| magic_item(char, item) },
          gear: own(listed(char.gear)).map { |item| counted(item) },
          companion_worn: companion_worn(char),
          consumables: listed(char.consumables).map { |item| counted(item) },
          bags: Array(char.bags.to_a).map { |bag| bag_of(bag) } }
      end

      def self.listed(collection)
        collection ? Pf2egear.items_in_inventory(collection.to_a) : []
      end

      # What the character keeps for themselves: an item their animal companion wears has a section of its own.
      def self.own(items)
        items.reject { |item| Pf2e::Companion::Gear.worn?(item) }
      end

      # What their animal companion wears, which they still own: `{ name, items }`, or nil when it wears nothing.
      def self.companion_worn(char)
        items = Pf2e::Companion::Gear.worn_items(char)
        return nil if items.empty?

        # Anyone may open a profile, so an unnamed companion is "Rowan's animal companion".
        { name: Pf2e::Companion::Gear.wearer_name(char, nil, :staff => true),
          items: items.map do |item|
            facts = Pf2e::Companion::Gear.facts(item)
            { item: named(item), kind: worn_kind(item, facts), bulk: bulk_word(item),
              invested: facts['investable'] ? facts['invested'] : nil }
          end }
      end

      def self.worn_kind(item, facts)
        return 'Barding' if facts['armor']

        item.is_a?(PF2MagicItem) ? 'Magic item' : 'Adventuring gear'
      end

      def self.bulk_word(item)
        item.bulk.to_f == 0.1 ? 'L' : item.bulk.to_i.to_s
      end

      # Whether an item is invested, or nil for one without the invested trait.
      def self.invested(item)
        return nil unless item.respond_to?(:invested) && Pf2e.has_trait?(item.traits, 'invested')

        !!item.invested
      end

      def self.named(item)
        Pf2e::ProfileSheet.item(item.name, 'item', Pf2egear.get_item_name(item))
      end

      # A weapon, a suit of armor or a shield.
      def self.worn(char, item, category, rank)
        held = category == 'weapons' ? Pf2e::SpellReservoir.stored(item) : nil

        { item: named(item), bulk: bulk_word(item), rank: rank, equipped: !!item.equipped, invested: invested(item),
          runes: Pf2egear.rune_summary(item, category),
          reservoir: held ? t('pf2e.reservoir_contains_mark', :spell => held['spell'], :rank => held['rank']) : nil }
      end

      def self.magic_item(char, item)
        { item: named(item), bulk: bulk_word(item), invested: invested(item), inert: !!Pf2e::BoundItems.inert_for(char, item) }
      end

      def self.counted(item)
        { item: named(item), quantity: item.respond_to?(:quantity) ? item.quantity.to_i : 1 }
      end

      def self.bag_of(bag)
        { item: named(bag), load: Bulk.fill(bag), contents: Inventory.bag_contents(bag).map { |item| counted(item) } }
      end

      # The Bulk they carry against what slows them and what they can carry at most. Shown only where the
      # game counts encumbrance.
      def self.bulk(char)
        return nil unless Global.read_config('pf2e_gear_options', 'use_encumbrance')

        { carried: Bulk.carried(char), encumbered_at: Pf2egear.encumbered_at(char), maximum: Pf2egear.max_bulk(char),
          encumbered: Bulk.encumbered?(char) }
      end
    end
  end
end
