module AresMUSH
  module Pf2e

    # What an attack does when it hits, assembled the way Foundry assembles it.
    #
    # The shape of a damage roll in PF2e is a number of dice of a size, plus a flat amount, per kind of
    # damage, with some kinds kept apart from the rest: persistent damage is rolled again each round,
    # splash damage applies whether or not the attack hit, and precision damage is lost against
    # anything immune to it. Those are `category` on a rule, and they are why this returns a structure
    # rather than one string.
    #
    # Three things the reader it replaced got wrong, all in the same direction:
    #
    #   * A striking rune adds dice, and it was adding both a die *and* a flat bonus of the same size.
    #   * Strength adds to damage for a melee attack, a propulsive one, or a thrown one that is neither
    #     splash nor a bomb (`actor/helpers.ts:420`). It was added to every attack, so a crossbow got
    #     the archer's Strength.
    #   * A Thief rogue adds Dexterity instead of Strength, but only with a finesse weapon. The racket
    #     was read without that condition.
    #
    # `helpers.ts:378` builds the domains, so a rune that says `{item|id}-damage` reaches the weapon it
    # is on and a feat that says `sword-weapon-group-damage` reaches every sword.
    module Damage

      STRIKING = 'power'.freeze

      # PF2e's own words for the kinds of damage that are rolled apart from the main body of a roll.
      APART = %w{persistent splash precision}.freeze

      # What a weapon does, with everything that modifies it.
      #
      #   { 'instances' => [ { 'damage_type' =>, 'dice' => [ [ n, die ] ], 'modifier' =>,
      #                        'category' => } ],
      #     'formula' => '2d12+1d6 fire+7', 'conditional' => [ … ] }
      def self.of(char, attack, options = [])
        domains = Domains.for('damage', attack, damage_attribute(char, attack))
        sources = Effects.sources(char)
        context = Effects.context(char)
        held = Effects.options(char) + Array(options)

        dice = Effects.damage_dice(sources, domains, context, held)
        flat = Effects.modifiers(sources, domains, context, held)

        met_dice, unmet_dice = dice.partition { |row| row['met'] }
        met_flat, unmet_flat = flat.partition { |row| row['met'] }

        instances = assemble(char, attack, met_dice, met_flat)

        { 'instances' => instances,
          'formula' => render(instances),
          'conditional' => unmet_dice + unmet_flat }
      end

      def self.formula(char, attack, options = [])
        of(char, attack, options)['formula']
      end

      # ------------------------------------------------------------------------------

      # The weapon's own dice, then everything else grouped by the kind of damage it deals. A row that
      # names no kind deals the weapon's kind, which is what makes a plain +2 a bonus to the whole hit
      # rather than to something of its own.
      def self.assemble(char, attack, dice, flat)
        base = base_instance(char, attack)
        instances = { [ base['damage_type'], nil ] => base }

        (dice + flat).reject { |row| row['critical'] }.each do |row|
          key = [ row['damage_type'] || base['damage_type'], apart(row['category']) ]
          into = instances[key] ||= { 'damage_type' => key.first, 'category' => key.last,
                                      'dice' => [], 'modifier' => 0, 'sources' => [] }

          add(into, row)
        end

        instances.values.reject { |instance| empty?(instance) }
      end

      def self.add(instance, row)
        instance['sources'] << row['source']

        if row['die'] && row['dice'].to_i.positive?
          instance['dice'] << [ row['dice'].to_i, row['die'] ]
        else
          instance['modifier'] += row['value'].to_i
        end
      end

      # A category we keep apart, or nothing. An unrecognised one is treated as part of the main roll,
      # because a number in the wrong pile still adds up and a number dropped does not.
      def self.apart(category)
        APART.include?(category.to_s) ? category.to_s : nil
      end

      # The weapon's own dice and the attribute modifier that goes with them.
      #
      # A striking rune raises the number of dice - `weapon.ts:263` reads it as the difference between
      # the weapon's dice and its printed dice - and adds nothing flat.
      def self.base_instance(char, attack)
        die = attack['die']
        count = 1 + attack['striking'].to_i
        attribute = damage_attribute(char, attack)

        { 'damage_type' => attack['damage_type'] || 'B',
          'category' => nil,
          'dice' => die ? [ [ count, die ] ] : [],
          'modifier' => attribute ? Pf2e.ability_mod(char, attribute) : 0,
          'sources' => [ attack['name'], attribute ].compact }
      end

      # Which attribute adds to this attack's damage, or nothing.
      #
      # `actor/helpers.ts:420`: Strength for a melee attack, a propulsive one, or a thrown one that is
      # neither splash nor a bomb. A Thief rogue reads Dexterity instead, and only with a finesse
      # weapon - the racket says "when you attack with a finesse or thrown weapon".
      def self.damage_attribute(char, attack)
        return nil unless strength_based?(attack)

        thief?(char) && Pf2e.has_trait?(attack['traits'], 'finesse') ? 'Dexterity' : 'Strength'
      end

      def self.strength_based?(attack)
        traits = attack['traits']

        return true unless attack['ranged']
        return true if Pf2e.has_trait?(traits, 'propulsive')

        Pf2e.has_trait?(traits, 'thrown') && !Pf2e.has_trait?(traits, 'splash') && !attack['bomb']
      end

      def self.thief?(char)
        (char.pf2_base_info || {})['specialize'].to_s.casecmp?('Thief')
      end

      def self.empty?(instance)
        instance['dice'].empty? && instance['modifier'].zero?
      end

      # `2d12+1d6 fire+7`, with anything kept apart named: `1d6 persistent bleed`.
      def self.render(instances)
        instances.map { |instance| render_instance(instance) }.join(' + ')
      end

      def self.render_instance(instance)
        dice = merge(instance['dice']).map { |count, die| "#{count}#{die}" }
        flat = instance['modifier'].zero? ? [] : [ instance['modifier'].to_s ]
        body = (dice + flat).join('+').gsub('+-', '-')

        [ body, instance['category'], instance['damage_type'] ].compact.join(' ')
      end

      # Two rows of the same die size are one roll of that many dice.
      def self.merge(dice)
        dice.group_by(&:last).map { |die, rows| [ rows.sum(&:first), die ] }
      end

    end
  end
end
