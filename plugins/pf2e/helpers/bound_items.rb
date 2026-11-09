module AresMUSH
  module Pf2e

    # Items a feat hands over: an egalrin's feather fan. A feat names its item in config,
    #
    #   bound_item: { category: magicitem, item: Egalrin Feather Fan }
    #
    # and the catalogue entry is `made_only`, so the item is never browsed, bought, sold, or learned as a
    # formula. The item records the feat in `bound_to`.
    #
    # It is made only at the two points a character's level is finished - approval and `advance/done` -
    # so nothing is made mid-draft for a reset to leave behind. It is usable only while they hold the feat,
    # which is worked out on every read rather than stored: a rollback past the feat makes it inert, and
    # taking the level again makes it work again, with nothing to put right either way.
    #
    # Later feats can add to what it holds (`bound_item_adds:`): Wind God's Fan adds a spell and an
    # activation to the fan.
    #
    # A class can hand one over for a subclass option it offers, as a list on the class:
    #
    #   bound_item: [ { subclass_option: Staff Nexus, category: weapons, item: Makeshift Staff } ]
    #
    # and the item is bound to the option, usable while they hold it.
    module BoundItems

      # What hands them an item: [ [ feat or option, block ] ]. Their own feats, not one a daily choice
      # lends them for the day, and their class's blocks for the subclass option they chose.
      def self.declared(char)
        feats = held_feats(char).filter_map do |name|
          info = Global.read_config('pf2e_feats', name)
          block = info.is_a?(Hash) ? info['bound_item'] : nil

          block.is_a?(Hash) && block['item'] ? [ name, block ] : nil
        end

        feats + class_declared(char)
      end

      def self.class_declared(char)
        base = char.respond_to?(:pf2_base_info) ? (char.pf2_base_info || {}) : {}
        info = Global.read_config('pf2e_class', base['charclass'].to_s)
        blocks = info.is_a?(Hash) ? Array(info['bound_item']).select { |one| one.is_a?(Hash) && one['item'] } : []

        blocks.select { |block| block['subclass_option'].to_s.casecmp?(base['specialize_info'].to_s) }
              .map { |block| [ block['subclass_option'].to_s, block ] }
      end

      def self.held_feats(char)
        (char.pf2_feats || {}).values.flatten.map(&:to_s).uniq
      end

      # Whether they hold what an item is bound to: a feat, or their class's subclass option.
      def self.holds_feat?(char, feat)
        held_feats(char).any? { |name| name.casecmp?(feat.to_s) } ||
          class_declared(char).any? { |source, _block| source.casecmp?(feat.to_s) }
      end

      def self.category(block)
        Pf2egear::Inventory.canonical(block['category'] || 'magicitem')
      end

      # The item bound to a feat, wherever it is carried.
      def self.item_for(char, feat, block)
        Pf2egear::Inventory.all(char, category(block)).find do |item|
          item.respond_to?(:bound_to) && item.bound_to.to_s.casecmp?(feat.to_s)
        end
      end

      # The commit step: an item made for each feat held without one, and each item's level kept at the
      # character's. Answers the names of the items made.
      def self.settle!(char)
        declared(char).filter_map do |feat, block|
          found = item_for(char, feat, block)

          if found
            found.update(:level => char.pf2_level.to_i) if found.respond_to?(:level) && found.level.to_i != char.pf2_level.to_i
            next nil
          end

          name = block['item'].to_s
          info = Global.read_config(Pf2egear::Inventory.config(category(block)), name)

          unless info.is_a?(Hash)
            Global.logger.warn "Bound item #{name} for #{feat} isn't in the #{category(block)} catalogue."
            next nil
          end

          made = Pf2egear.create_item(char, category(block), name, 1, info)
          made.update(:bound_to => feat, :level => char.pf2_level.to_i)

          name
        end
      end

      def self.bound?(item)
        item.respond_to?(:bound_to) && !item.bound_to.to_s.empty?
      end

      # Whether they may use it: anything not bound, and a bound item while they hold its feat.
      def self.usable?(holder, item)
        !bound?(item) || holds_feat?(holder, item.bound_to)
      end

      # The feat an inert item is waiting on, or nil when it works.
      def self.inert_for(holder, item)
        usable?(holder, item) ? nil : item.bound_to.to_s
      end

      # What it holds: its spells, and the activations a day its holder's feats give it, up to the most the
      # catalogue allows. { 'spells' => [ { 'name', 'rank' } ], 'activations' => n }, or nil for an item
      # that holds nothing.
      def self.holds(holder, item)
        info = Global.read_config(Pf2egear::Inventory.config(category_of(item)), item.name.to_s)
        base = info.is_a?(Hash) ? info['holds'] : nil

        return nil unless base.is_a?(Hash)

        adds = held_feats(holder).filter_map do |name|
          feat = Global.read_config('pf2e_feats', name)
          block = feat.is_a?(Hash) ? feat['bound_item_adds'] : nil

          block.is_a?(Hash) && block['item'].to_s.casecmp?(item.name.to_s) ? block : nil
        end

        spells = ([ base ] + adds).flat_map { |one| Array(one['spells']).select { |spell| spell.is_a?(Hash) } }
        activations = ([ base ] + adds).sum { |one| one['activations'].to_i }
        most = base['max_activations']

        { 'spells' => spells, 'activations' => most ? [ activations, most.to_i ].min : activations }
      end

      def self.category_of(item)
        Pf2egear::Inventory::CATEGORIES.find { |row| AresMUSH.const_get(row['model']) == item.class }&.dig('names')&.first
      end

      # The lines an item view adds for a bound item: what it holds, and whether it works.
      def self.describe(holder, item)
        return [] unless bound?(item)

        lines = []
        held = holds(holder, item)

        if held
          spells = held['spells'].map { |spell| "#{spell['name']} (rank #{spell['rank']})" }.join(', ')
          lines << t('pf2e.bound_item_holds', :spells => spells, :activations => held['activations'])
        end

        feat = inert_for(holder, item)
        lines << (feat ? t('pf2e.bound_item_inert', :feat => feat) : t('pf2e.bound_item_bound', :feat => item.bound_to))
        lines
      end
    end
  end
end
