module AresMUSH
  module Pf2e

    # A shifting rune's Shift Weapon: the weapon takes the shape of another melee weapon that needs the same
    # number of hands. Only the encounter's copy of it changes, so the weapon is back in the shape it was
    # bought in once the encounter ends.
    #
    # Its runes and material stay with it. A property rune that can't apply to the new shape (a vorpal rune
    # on a warhammer) is suppressed, kept aside on the item until it takes a shape the rune applies to.
    module ShiftingRune

      NAME = 'Shift Weapon'.freeze

      # What a weapon's shape is: everything its catalogue row says about how it strikes.
      SHAPE = %w{wp_damage wp_damage_2h wp_damage_type wp_type category traits hands range reload group bulk}.freeze

      def self.act(scene, said, out)
        holder = scene.actor.holder
        carriers = RuneActions.carriers(holder, NAME)
        weapon = carriers.find { |one| said['words'].any? { |word| named?(one, word) } } || carriers.first
        wanted = said['words'].map { |word| shape_named(word) }.compact.find { |name| name != weapon.name }

        return Err.new(:needs_shape, 'pf2e.shift_needs_shape', 'weapon' => weapon.name) unless wanted

        info = Global.read_config('pf2e_weapons', wanted)
        refused = unfit(weapon, wanted, info)

        return refused if refused

        before = weapon.name
        weapon.update(SHAPE.to_h { |field| [ field.to_sym, info[field] ] }
                           .merge(:name => wanted, :shape_of => weapon.shape_of || before))
        quiet = suppress!(weapon)

        out['lines'] << Telling.event('pf2e.act_announced', :actor => scene.actor.label, :action => NAME,
                                                           :cost => Actions.cost(NAME), :target => '')
        out['lines'] << Telling.event('pf2e.shift_shaped', :actor => scene.actor.label, :from => before, :to => wanted)
        out['lines'] << Telling.event('pf2e.shift_suppressed', :runes => quiet.join(', ')) if quiet.any?
        nil
      end

      # A word naming the weapon by its name, its nickname, or the shape it was bought as.
      def self.named?(weapon, word)
        [ weapon.name, weapon.nickname, weapon.shape_of ].compact.any? { |one| Domains.slug(one) == Domains.slug(word) }
      end

      # The catalogue's spelling of a weapon a word names.
      def self.shape_named(word)
        (Global.read_config('pf2e_weapons') || {}).keys.find { |name| Domains.slug(name) == Domains.slug(word) }
      end

      # Why the weapon can't take this shape: another melee weapon, wielded in as many hands, that isn't a
      # specific magic weapon or a staff of its own.
      def self.unfit(weapon, wanted, info)
        if !info.is_a?(Hash) || !info['wp_type'].to_s.casecmp?('melee')
          return Err.new(:not_melee, 'pf2e.shift_not_melee', 'shape' => wanted)
        end

        unless info['hands'].to_i == weapon.hands.to_i
          return Err.new(:other_hands, 'pf2e.shift_other_hands', 'weapon' => weapon.name, 'shape' => wanted,
                         'hands' => weapon.hands.to_i)
        end

        if !info['runes'].nil? || Array(info['traits']).any? { |trait| trait.to_s.casecmp?('magical') } || !Staves.info(wanted).nil?
          return Err.new(:specific, 'pf2e.shift_specific', 'shape' => wanted)
        end

        nil
      end

      # Every property rune etched on it, suppressed or not, sorted by whether it applies to the shape it has
      # now. Answers the ones suppressed.
      def self.suppress!(weapon)
        runes = weapon.runes || {}
        property = runes['property'].is_a?(Hash) ? runes['property'] : { 'list' => Array(runes['property']) }
        all = Array(property['list']) + Array(property['suppressed'])
        quiet = all.reject { |one| Pf2egear::RuneFit.applies?(weapon, one) }

        weapon.update(:runes => runes.merge('property' => property.merge('list' => all - quiet, 'suppressed' => quiet)))
        quiet
      end
    end
  end
end
