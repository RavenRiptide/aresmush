module AresMUSH
  module Pf2e

    # The rule elements we implement, spelled the way Foundry spells them.
    #
    # A feat, an item or a condition carries a `rules:` list, and each row is a rule element: a `key`
    # naming what kind it is, a `selector` naming the domains it reaches, a `value`, and a `predicate`
    # saying when it applies. Those are Foundry's own field names, so a row lifted out of their packs
    # is copied rather than translated - which is the point, since their system is the reference
    # implementation of this game's mechanics and a translation is a place to introduce an error.
    #
    #   rules:
    #     - key: FlatModifier
    #       selector: hp
    #       value: "@actor.level"                # Toughness
    #     - key: FlatModifier
    #       selector: [ cha-based, int-based, wis-based ]
    #       type: status
    #       value: "-@item.badge.value"          # Stupefied, scaled by the condition's own value
    #     - key: DamageDice
    #       selector: strike-damage
    #       diceNumber: 1
    #       dieSize: d6
    #       damageType: fire
    #
    # Foundry ships 42 kinds. A row whose kind is not in the table below is refused rather than
    # ignored: an effect nobody applies is a sheet that is quietly wrong, and the import that wrote
    # these rows refuses the same kinds for the same reason.
    module Rules

      # A row's `slug` is the name other rules call it by: `AdjustModifier` names the modifier it
      # changes, and their data names ours as well as its own - `resilient`, `armor-check-penalty`,
      # `weapon-potency`. A row that does not say is slugged from whatever carries it.
      #
      # `value` and `diceNumber` are read by `Pf2e::Formula`, `predicate` by `Pf2e::Predicate`. Every
      # other field is taken as it stands.
      FORMULA_FIELDS = %w{value diceNumber}.freeze

      KINDS = [
        {
          'key' => 'FlatModifier',
          'fields' => %w{key selector value type ability min max damageType damageCategory critical
                         predicate slug label hideIfDisabled},
          # A number added to whatever the selector reaches, obeying the stacking rule for its type.
          #
          # `min` and `max` clamp it, which is how a bonus that scales with something says how far it
          # goes. `damageType` makes it a bonus to one kind of damage rather than to the whole roll.
          'contribute' => lambda { |row, source, context|
            { 'source' => row['ability'] ? row['ability'].to_s.capitalize : source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'type' => (row['type'] || Modifiers::UNTYPED).to_s.downcase,
              'value' => clamp(Formula.value(row['value'], context), row),
              'damage_type' => row['damageType'],
              'category' => row['damageCategory'],
              'critical' => row['critical'] }
          }
        },
        {
          'key' => 'DamageDice',
          'fields' => %w{key selector diceNumber dieSize damageType category critical predicate slug
                         label hideIfDisabled override tags},
          # Dice added to a damage roll. `category` separates persistent, precision and splash damage,
          # which are rolled and applied apart from the rest.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'dice' => Formula.value(row['diceNumber'] || 1, context),
              'die' => row['dieSize'],
              'damage_type' => row['damageType'],
              'category' => row['category'],
              'critical' => row['critical'] }
          }
        },
        {
          'key' => 'RollOption',
          'fields' => %w{key option domain toggleable value predicate label slug},
          # Declares a circumstance rather than a number. A rule on the same feat or item is then
          # predicated on it - a Clandestine Cloak declares `clandestine-cloak` and predicates its own
          # bonuses on it - so this contributes an option, not a modifier.
          #
          # `value` decides whether it holds without being asked for. Foundry defaults a toggleable one
          # to off and everything else to on; here an option a character has is on unless they turn it
          # off, because an item you are wearing should do what it says.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'option' => row['option'],
              'domain' => row['domain'] || Domains::ALL,
              'label' => row['label'],
              'default' => truthy(row['value'], context) }
          }
        }
      ].freeze

      # Fields that position a toggle in Foundry's character sheet. They are neither read nor complained
      # about: a field we ignore that changes the mechanics is a sheet that is quietly wrong, and one
      # that describes where a control sits in an interface we do not have is neither.
      PRESENTATION = { 'RollOption' => %w{placement mergeable} }.freeze

      BY_KEY = KINDS.each_with_object({}) { |row, out| out[row['key']] = row }.freeze

      # A RollOption's `value` is a boolean or a formula, not a number: `true` and `false` mean what they
      # say, and anything else is read as arithmetic and true when it comes to something other than zero.
      # An option that says nothing is on, which is this game's default rather than Foundry's.
      def self.truthy(value, context)
        return true if value.nil?
        return value if value == true || value == false

        !Formula.value(value, context).to_i.zero?
      rescue StandardError
        false
      end

      def self.clamp(value, row)
        low = row['min'] ? Formula.value(row['min']) : nil
        high = row['max'] ? Formula.value(row['max']) : nil

        value = [ value, low ].max if low
        value = [ value, high ].min if high

        value
      end

      # Rules that change how a check turned out. `AdjustDegreeOfSuccess` is not implemented, so this is
      # empty - but a check asks for its outcome through it, which is what makes implementing the kind a
      # change to `KINDS` rather than a change to `Pf2e::Check`.
      def self.adjustments(sources, domains, options)
        gather(sources, domains, options, 'AdjustDegreeOfSuccess') { |row| row['adjustment'] }
      end

      # Text shown with a roll. `Note` is likewise not implemented yet.
      def self.notes(sources, domains, options)
        gather(sources, domains, options, 'Note') { |row| row['text'] }
      end

      # Every row of a kind that reaches these domains and whose circumstances are met, as whatever the
      # block makes of it. The kinds above are read here rather than through `Effects.rows_of` because
      # they contribute neither a modifier nor dice: there is nothing to stack.
      def self.gather(sources, domains, options, key)
        return [] unless known?(key)

        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, key).select { |row| Domains.matches?(row['selector'], domains) }
                              .select { |row| Predicate.test(row['predicate'], held) }
                              .map { |row| yield(row) }
                              .compact
        end
      end

      def self.known?(key)
        BY_KEY.key?(key.to_s)
      end

      # The rows of one kind that a source carries, whatever else it carries.
      def self.of_kind(source, key)
        Array(source['rules']).select { |row| row['key'].to_s == key.to_s }
      end

      # What this row is worth, or nil when its kind is one we do not implement.
      def self.contribute(row, source, context)
        kind = BY_KEY[row['key'].to_s]

        return nil unless kind

        kind['contribute'].call(row, source, context)
      end

      # A field nobody reads is a rule that silently does something other than what it says, so it is
      # reported. Checked against the kind's own field list rather than one list for all of them,
      # because `dieSize` means nothing on a FlatModifier.
      def self.complain(name, row)
        kind = BY_KEY[row['key'].to_s]

        unless kind
          Global.logger.warn "PF2e rule on #{name.inspect} is a #{row['key'].inspect}, which nothing applies."
          return
        end

        strays = row.keys.map(&:to_s) - kind['fields'] -
                 Array(PRESENTATION[row['key'].to_s])

        return if strays.empty?

        Global.logger.warn "PF2e #{row['key']} on #{name.inspect} has fields nothing reads: #{strays.join(', ')}."
      end
    end
  end
end
