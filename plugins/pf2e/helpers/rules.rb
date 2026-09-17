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
              'dice' => Formula.value(row['diceNumber'] || 1, context),
              'die' => row['dieSize'],
              'damage_type' => row['damageType'],
              'category' => row['category'],
              'critical' => row['critical'] }
          }
        }
      ].freeze

      BY_KEY = KINDS.each_with_object({}) { |row, out| out[row['key']] = row }.freeze

      def self.clamp(value, row)
        low = row['min'] ? Formula.value(row['min']) : nil
        high = row['max'] ? Formula.value(row['max']) : nil

        value = [ value, low ].max if low
        value = [ value, high ].min if high

        value
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

        strays = row.keys.map(&:to_s) - kind['fields']

        return if strays.empty?

        Global.logger.warn "PF2e #{row['key']} on #{name.inspect} has fields nothing reads: #{strays.join(', ')}."
      end
    end
  end
end
