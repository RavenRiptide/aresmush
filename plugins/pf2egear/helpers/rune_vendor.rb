module AresMUSH
  module Pf2egear

    # Buying a rune for an item a character holds: `quote` says what it would cost or why it can't be had,
    # and `etch!` takes the money and etches it.
    #
    # Fundamental runes come from `pf2e_fundamental_runes.yml`, property runes from `pf2e_runes.yml` by way of
    # `RuneFit`, the fit staff's `etch` asks too. The vendor sells what a character could buy as an item:
    # their level or lower, and common unless a feat or class opens it (`Pf2e::ItemAccess`). Raising a rune
    # the item has - a higher potency, greater flaming over flaming - costs the difference between the two
    # prices, the rule for upgrading a rune. Whatever is paid is added to the item's price, so selling the item
    # returns half of it, as it would the item bought whole.
    module RuneVendor

      # The fundamental runes an item takes, by its category.
      KINDS = { 'weapons' => 'weapon', 'armor' => 'armor', 'shields' => 'shield' }.freeze

      # Where each fundamental rune is kept on an item: striking and resilient share `power`.
      STORED = { 'potency' => 'potency', 'striking' => 'power', 'resilient' => 'power',
                 'reinforcing' => 'reinforcing' }.freeze

      # Words a player may leave out of a fundamental rune's name: "+1 potency" is the +1 Weapon Potency rune
      # on a weapon.
      UNSAID = %w{weapon armor rune}.freeze

      # `{ 'kind' => 'fundamental' | 'property', 'rune' => name, 'cost' => copper, ... }`, or an Err.
      def self.quote(char, item, category, name)
        kind = KINDS[Inventory.canonical(category).to_s]

        return Pf2e::Err.new(:no_runes, 'pf2egear.rune_buy_no_runes') unless kind && item.respond_to?(:runes)
        return Pf2e::Err.new(:temporary, 'pf2egear.rune_buy_temporary', 'item' => label(item)) if temporary?(item)

        held = Pf2e::Equipment.held_by(item)

        return Pf2e::Err.new(:in_encounter, 'pf2egear.item_in_encounter', 'item' => label(item), 'id' => held.id) if held

        found = fundamental(kind, name)

        found ? fundamental_quote(char, item, found) : property_quote(char, item, category, name)
      end

      # Takes the money, etches the rune, and adds what was paid to the item's price.
      def self.etch!(char, item, quote)
        runes = item.runes || {}

        if quote['kind'] == 'fundamental'
          runes['fundamental'] = (runes['fundamental'] || {}).merge(quote['stored'] => quote['grade'])
        else
          list = Pf2egear.property_list(item) - [ quote['replaces'] ].compact + [ quote['rune'] ]
          property = runes['property'].is_a?(Hash) ? runes['property'] : {}
          runes['property'] = property.merge('list' => list.sort)
        end

        item.update(:runes => runes, :price => item.price.to_i + quote['cost'])
        Pf2egear.pay_player(char, -quote['cost'], 'Item Vendor', "Rune: #{quote['rune']} on #{label(item)}")
      end

      # The fundamental rune a name means on this kind of item: `[ kind, rune, grade, row ]`, or nil.
      def self.fundamental(kind, name)
        wanted = words(name)

        (fundamentals[kind] || {}).each do |rune, grades|
          grades.each do |grade, row|
            return [ kind, rune, grade.to_i, row ] if words(row['name']) == wanted
          end
        end

        nil
      end

      def self.fundamentals
        Global.read_config('pf2e_fundamental_runes') || {}
      end

      def self.words(name)
        (Pf2e::Domains.slug(name).split('-') - UNSAID).sort
      end

      def self.fundamental_quote(char, item, found)
        kind, rune, grade, row = found
        stored = STORED[rune]
        current = (item.runes || {}).dig('fundamental', stored).to_i
        refused = refuse(char, row['name'], row)

        return refused if refused
        return Pf2e::Err.new(:has_grade, 'pf2egear.rune_buy_has_grade', 'rune' => row['name'], 'item' => label(item)) if grade <= current

        potency = (item.runes || {}).dig('fundamental', 'potency').to_i

        if stored == 'power' && grade > potency
          return Pf2e::Err.new(:needs_potency, 'pf2egear.rune_buy_needs_potency', 'rune' => row['name'], 'grade' => grade)
        end

        was = current.positive? ? fundamentals.dig(kind, rune, current) : nil
        cost = row['price'].to_i - (was ? was['price'].to_i : 0)

        Pf2e::Ok.new(:state => { 'kind' => 'fundamental', 'rune' => row['name'], 'stored' => stored, 'grade' => grade,
                                 'cost' => cost, 'replaces' => was && was['name'] })
      end

      def self.property_quote(char, item, category, name)
        fit = RuneFit.property(item, category, name)

        return fit if fit.err?

        rune, replaces = fit.state['rune'], fit.state['replaces']
        info = Pf2egear.rune_entry(rune)
        refused = refuse(char, rune, info)

        return refused if refused

        was = replaces ? Pf2egear.rune_entry(replaces)['price'].to_i : 0

        Pf2e::Ok.new(:state => { 'kind' => 'property', 'rune' => rune, 'replaces' => replaces,
                                 'cost' => info['price'].to_i - was })
      end

      # What the vendor won't sell this character: a rune above their level, or an uncommon or rare one
      # nothing they have opens.
      def self.refuse(char, name, info)
        if info['level'].to_i > char.pf2_level.to_i
          return Pf2e::Err.new(:too_high, 'pf2egear.rune_buy_too_high', 'rune' => name, 'level' => info['level'])
        end

        return nil if Pf2e::ItemAccess.accessible?(char, 'runes', name, info)

        Pf2e::Err.new(:rare, 'pf2egear.rune_buy_rare', 'rune' => name, 'rarity' => Pf2e::ItemAccess.rarity(info))
      end

      # An item that lasts a day or an encounter: a rune on it would go with it.
      def self.temporary?(item)
        item.respond_to?(:expires) && !item.expires.to_s.empty?
      end

      def self.label(item)
        item.respond_to?(:nickname) && item.nickname ? item.nickname : item.name
      end
    end
  end
end
