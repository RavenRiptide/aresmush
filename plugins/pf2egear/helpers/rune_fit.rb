module AresMUSH
  module Pf2egear

    # Whether a property rune can be etched onto an item, for staff's `etch/property` and the vendor's
    # `buy/rune` alike, so the two never disagree.
    #
    # A rune's `usage`, from its pack item, says what it is etched onto (`pf2e_runes.yml`); a usage this
    # doesn't know refuses the rune, so a new one is never etched without a test. Beyond that: a staff and a
    # specific magic weapon or armor take no property runes; an item holds as many as its potency rune is worth; holy and unholy never share an
    # item; and a rune of a family the item already holds replaces a weaker one and is refused beside a
    # stronger. Energy-resistant runes are a family per damage type, since each must resist a different one.
    module RuneFit

      # Each usage, as the test of an item and the words that say what it is for.
      USAGES = {
        'weapon' => [ ->(_item) { true }, 'a weapon' ],
        'melee-weapon' => [ ->(item) { melee?(item) }, 'a melee weapon' ],
        'thrown-weapon' => [ ->(item) { thrown?(item) }, 'a thrown weapon' ],
        'bludgeoning-weapon' => [ ->(item) { damage_types(item).include?('B') }, 'a bludgeoning weapon' ],
        'slashing-melee-weapon' => [ ->(item) { melee?(item) && damage_types(item).include?('S') },
                                     'a slashing melee weapon' ],
        'piercing-or-slashing-melee-weapon' => [ ->(item) { melee?(item) && (damage_types(item) & %w{P S}).any? },
                                                 'a piercing or slashing melee weapon' ],
        'armor' => [ ->(_item) { true }, 'armor' ],
        'light-armor' => [ ->(item) { armor_category(item) == 'light' }, 'light armor' ],
        'medium-or-heavy-armor' => [ ->(item) { %w{medium heavy}.include?(armor_category(item)) },
                                     'medium or heavy armor' ],
        'light-or-medium-nonmetal-armor' => [ ->(item) { %w{light medium}.include?(armor_category(item)) && !metal?(item) },
                                              'light or medium armor that isn\'t metal' ]
      }.freeze

      # A property rune's kind, as the inventory category it goes on. Shields take no property runes.
      KINDS = { 'weapon' => 'weapons', 'armor' => 'armor' }.freeze

      # Our armor has no material. Its group says it: chain, plate, and composite armor are metal; leather and
      # cloth are not.
      NONMETAL_GROUPS = %w{leather cloth}.freeze

      # What happens if the rune is etched: `{ 'rune' => the name to store, 'replaces' => a weaker rune of its
      # family it takes the place of, or nil }`, or an Err saying why it can't be.
      def self.property(item, category, name)
        found = rune(name)

        return found if found.err?

        stored, info = found.state['rune'], found.state['info']
        kind = Inventory.canonical(category).to_s

        return Pf2e::Err.new(:staff, 'pf2egear.rune_property_staff', 'item_name' => item.name) if Pf2e::Staves.staff?(item)
        return wrong_kind(stored, info) unless KINDS[info['kind'].to_s] == kind
        return Pf2e::Err.new(:specific, 'pf2egear.rune_property_specific', 'item_name' => item.name) if specific?(item, kind)

        usage = USAGES[info['usage'].to_s]

        return wrong_usage(stored, info['usage'] ? "something nothing checks (#{info['usage']})" : 'nothing') unless usage
        return wrong_usage(stored, usage[1]) unless usage[0].call(item)

        held = Pf2egear.property_list(item)
        excluded = held.find { |one| Array(info['excludes']).include?(Pf2egear.rune_entry(one)&.dig('slug')) }

        return Pf2e::Err.new(:excluded, 'pf2egear.rune_property_excludes', 'rune_name' => stored, 'other' => excluded) if excluded

        kin = held.find { |one| family(one) == family(stored) }

        if kin && level(kin) >= level(stored)
          return Pf2e::Err.new(:has_stronger, 'pf2egear.rune_property_has_stronger', 'rune_name' => stored, 'held' => kin)
        end

        if !kin && held.size >= Pf2egear.rune_slots(item)
          return Pf2e::Err.new(:no_slot, 'pf2egear.rune_property_no_slot', 'slots' => Pf2egear.rune_slots(item))
        end

        Pf2e::Ok.new(:state => { 'rune' => stored, 'replaces' => kin })
      end

      # The rune a name means, as it is stored, and its catalogue entry. A choice rune needs its choice.
      def self.rune(name)
        info = Pf2egear.rune_entry(name)

        return Pf2e::Err.new(:unknown, 'pf2egear.rune_property_unknown', 'rune_name' => name) unless info

        choices = RUNE_CHOICES[info['slug']]

        if choices && !Pf2egear.rune_choice(name)
          return Pf2e::Err.new(:needs_choice, 'pf2egear.rune_property_needs_choice',
                               'rune_name' => Pf2egear.rune_named(name), 'choices' => choices.join(', '))
        end

        Pf2e::Ok.new(:state => { 'rune' => Pf2egear.rune_spelled(name), 'info' => info })
      end

      # Whether the item holds this very rune (with the same choice), whatever spelling either uses.
      def self.held(item, name)
        wanted = Pf2e::Domains.slug(Pf2egear.rune_spelled(name) || name)

        Pf2egear.property_list(item).find do |one|
          Pf2e::Domains.slug(Pf2egear.rune_spelled(one) || one) == wanted
        end
      end

      # The family a rune belongs to: its slug without the grade, and its choice. Greater Flaming and
      # Flaming are one family; Energy Resistant (Fire) and Energy Resistant (Acid) are two.
      def self.family(name)
        slug = Pf2egear.rune_entry(name)&.dig('slug') || Pf2e::Domains.slug(name)
        base = slug.sub(/\A(?:#{RUNE_GRADES.join('|')})(?=[A-Z])/, '').downcase

        [ base, Pf2egear.rune_choice(name) ].compact.join(':')
      end

      def self.level(name)
        Pf2egear.rune_entry(name)&.dig('level').to_i
      end

      # A specific magic weapon or armor - one with an entry of its own, like Searing Blade - can't gain
      # property runes, though its fundamental runes can be raised (GM Core p. 224). Its catalogue row says so
      # by carrying runes of its own or the magical trait.
      def self.specific?(item, kind)
        row = Global.read_config("pf2e_#{kind}", item.name)

        return false unless row.is_a?(Hash)

        !row['runes'].nil? || Array(row['traits']).any? { |trait| trait.to_s.casecmp?('magical') }
      end

      def self.wrong_kind(stored, info)
        Pf2e::Err.new(:wrong_kind, 'pf2egear.rune_property_wrong_kind', 'rune_name' => stored, 'kind' => info['kind'])
      end

      def self.wrong_usage(stored, what)
        Pf2e::Err.new(:wrong_usage, 'pf2egear.rune_property_wrong_usage', 'rune_name' => stored, 'usage' => what)
      end

      def self.melee?(item)
        item.wp_type.to_s.casecmp?('melee')
      end

      def self.thrown?(item)
        Array(item.traits).any? { |trait| trait.to_s.match?(/\Athrown\b/i) }
      end

      # The damage types a weapon deals. Whether a versatile type counts (a `Versatile (B)` weapon for
      # *shockwave*) waits on a ruling, so for now it is the weapon's own type only.
      def self.damage_types(item)
        [ item.wp_damage_type.to_s.upcase ]
      end

      def self.armor_category(item)
        item.category.to_s.downcase
      end

      def self.metal?(item)
        !NONMETAL_GROUPS.include?(item.group.to_s.downcase)
      end
    end
  end
end
