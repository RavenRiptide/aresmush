module AresMUSH
  module Pf2e

    # Who may buy an item from the vendor. A common item is anyone's. An uncommon, rare or unique one can be
    # bought only by a character whose build names it: a feat, a class feature or a class carries an
    # `item_access` list, read from config each time, so a feat taken back takes its access with it.
    #
    # Every other uncommon or rare item is reached through a request: its formula bought with RPP and money,
    # and the item crafted from it. Staff never open the vendor for one.
    #
    #   item_access:
    #     - category: weapons        # the catalogue, by any name a player may type for it
    #       traits: [ khazad ]       # uncommon items carrying any of these traits
    #       names: [ Kukri ]         # these items, whatever their rarity
    #       from_choice: true        # the item the source's own feat choice picked, whatever its rarity
    #       favored_weapon: true     # the character's deity's favored weapon, whatever its rarity
    #
    # A trait opens uncommon items only, because each source that grants access by trait says
    # "uncommon weapons with the ... trait". A source that names an item opens it even when it is rare.
    module ItemAccess

      # Most to least restrictive, so an item marked twice reads as the rarer.
      RARER = %w{unique rare uncommon}.freeze

      # An item's rarity, from its traits or, for a rune, its own `rarity` field.
      def self.rarity(info)
        info = {} unless info.is_a?(Hash)
        said = ([ info['rarity'] ] + Array(info['traits'])).compact.map { |one| one.to_s.downcase }

        RARER.find { |one| said.include?(one) } || 'common'
      end

      def self.common?(info)
        rarity(info) == 'common'
      end

      # The catalogue's canonical name for whatever a player or a config block calls it: `weapon` and
      # `weapons` are both `weapons`.
      def self.canonical(name)
        row = Pf2egear::Inventory.row(name)

        row ? row['names'].first : name.to_s.downcase
      end

      # One entry per `item_access` row the character's build declares, with picks and favored weapons
      # resolved to names: { 'source', 'category', 'traits', 'names' }. Worked out once so a list of items
      # can be checked against it without reading the character again for each one.
      def self.of(char)
        sources(char).flat_map do |source, info|
          Array(info['item_access']).select { |row| row.is_a?(Hash) }.map { |row| resolve(char, source, row) }
        end
      end

      def self.accessible?(char, category, name, info)
        allows?(of(char), category, name, info)
      end

      def self.allows?(entries, category, name, info)
        return true if common?(info)

        wanted = canonical(category)

        Array(entries).any? { |entry| matches?(entry, wanted, name, info) }
      end

      def self.matches?(entry, category, name, info)
        return false unless entry['category'] == category
        return true if entry['names'].any? { |one| one.casecmp?(name.to_s) }

        rarity(info) == 'uncommon' &&
          Array(info['traits']).any? { |trait| entry['traits'].include?(trait.to_s.downcase) }
      end

      # The character's feats, class features and class, each with its config, where that config
      # declares access.
      def self.sources(char)
        feats = (char.pf2_feats || {}).values.flatten.map(&:to_s).uniq
                                     .map { |name| [ name, Global.read_config('pf2e_feats', name) ] }
        features = (char.pf2_features || {}).values.flatten.map { |one| Effects.feature_named(one.to_s) }.uniq
                                           .map { |name| [ name, Global.read_config('pf2e_class_features', name) ] }
        charclass = (char.pf2_base_info || {})['charclass'].to_s
        klass = charclass.empty? ? [] : [ [ charclass, Global.read_config('pf2e_class', charclass) ] ]

        (feats + features + klass).select { |_name, info| info.is_a?(Hash) && info['item_access'] }
      end

      def self.resolve(char, source, row)
        names = Array(row['names']).map(&:to_s)
        names += chosen(char, source) if row['from_choice']
        names << favored_weapon(char) if row['favored_weapon']

        { 'source' => source,
          'category' => canonical(row['category']),
          'traits' => Array(row['traits']).map { |trait| trait.to_s.downcase },
          'names' => names.compact.map(&:to_s).reject(&:empty?) }
      end

      # What the source's own feat choice picked.
      def self.chosen(char, source)
        Pf2e.recorded_choices(char).select { |name, _label, _level| name.to_s.casecmp?(source.to_s) }
                                   .map { |_name, label, _level| label.to_s }
      end

      def self.favored_weapon(char)
        return nil unless char.respond_to?(:pf2_faith)

        deity = (char.pf2_faith || {})['deity']

        deity.blank? ? nil : Global.read_config('pf2e_deities', deity, 'fav_weapon')
      end
    end
  end
end
