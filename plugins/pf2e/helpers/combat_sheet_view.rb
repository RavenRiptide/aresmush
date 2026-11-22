module AresMUSH
  module Pf2e

    # The Combat tab of a character's profile, as plain data: what `csheet` shows outside an encounter. Its
    # Strikes, armor class and saves come from the helpers `csheet` reads them from. Conditions, effects,
    # temporary hit points and hero points belong to a scene or an encounter, so they aren't here.
    module CombatSheetView

      def self.of(char)
        combat = char.combat
        shield = Pf2eCombat.get_equipped_shield(char)
        ac = Pf2eCombat.calculate_ac(char)

        { name: char.name,
          hp: char.hp ? Pf2eHP.get_max_hp(char) : nil,
          ac: ac,
          ac_with_shield: shield ? ac + shield.ac_bonus.to_i : nil,
          ac_breakdown: ac_breakdown(char),
          perception: combat ? { value: Pf2eCombat.get_perception(char), rank: combat.perception } : nil,
          class_dc: combat ? { value: Pf2eCombat.get_class_dc(char), rank: combat.class_dc } : nil,
          archetype_dcs: SheetView.archetype_dcs(char),
          saves: SheetView.saves(char),
          iwr: SheetView.iwr(IWR.sheet_rows(IWR.of(char))),
          movement: SheetView.movement(Movement.for(char, :combat => true)) }
          .merge(strikes(char))
          .merge(crit_spec: crit_spec(char), crit_spec_sources: Pf2e.crit_spec_sources(char).sort)
      end

      # The sum `sheet/breakdown ac` opens with: the base, then each attribute by name and each other kind
      # of bonus summed.
      def self.ac_breakdown(char)
        figure = Stat.of(char, 'ac')
        summed = PF2StatBreakdownTemplate.new('AC', figure, 'ac').summed_terms

        { total: figure['total'].to_i, base: figure['base'].to_i, basis: figure['basis'].to_s,
          terms: summed.map { |value, word| { value: value.to_i, label: word } } }
      end

      # Weapons, unarmed attacks, and a note when a stance or a battle form changes what they Strike with.
      def self.strikes(char)
        if BattleForms.strikeless?(char)
          source = ActiveEffects.bare_name(BattleForms.active(char)['effect'])

          return { weapons: [], unarmed: [], strike_note: t('pf2e.profile_sheet_no_strikes', :name => char.name, :source => source) }
        end

        replacing = Pf2eCombat.granted_strikes(char).select { |strike| strike['replace_all'] }

        if replacing.any?
          source = replacing.first['source'].to_s.sub(/\A(?:Stance|Spell Effect|Effect): /, '')
          note = t('pf2e.profile_sheet_strikes_replaced', :name => char.name, :source => source,
                   :attacks => replacing.map { |strike| strike['name'] }.join(', '))

          return { weapons: [], unarmed: replacing.map { |strike| granted(char, strike) }, strike_note: note }
        end

        weapons = Pf2egear::Inventory.held(char, 'weapons').select { |w| w.equipped && !Pf2eCombat.rune_lender?(w.name) }
        unarmed = (char.combat&.unarmed_attacks || {}).map do |name, info|
          unarmed_strike(char, name, info, Pf2eCombat.get_unarmed_prof(char, name, info))
        end

        { weapons: weapons.map { |weapon| weapon_strike(char, weapon) },
          unarmed: unarmed + Pf2eCombat.granted_strikes(char).map { |strike| granted(char, strike) },
          strike_note: nil }
      end

      def self.weapon_strike(char, weapon)
        strike = Pf2eCombat.attack_descriptor(char, weapon)
        damage = Pf2eCombat.damage_breakdown(char, weapon.name, weapon)

        { name: weapon.nickname.presence || weapon.name, item: ProfileSheet.item(weapon.name, 'item'),
          attack: Pf2eCombat.get_wpattack_bonus(char, weapon), rank: Pf2eCombat.get_weapon_prof(char, weapon.name),
          damage: damage['formula'], critical: damage['critical'],
          range: strike['range'].to_i.positive? ? strike['range'].to_i : nil,
          traits: traits(weapon.traits), runes: Array(strike['runes']).map { |one| titleized(one) } }
      end

      # Read as a Strike reads it, so what a feat or an effect does to the attack shows.
      def self.unarmed_strike(char, name, info, prof)
        attack = Pf2eCombat.unarmed_descriptor(name, info, prof, char)
        damage = Pf2eCombat.damage_breakdown(char, name, nil, false, [], attack)

        { name: name, attack: Stat.total(char, 'attack', attack), rank: prof.to_s,
          damage: damage['formula'], materials: materials(attack), traits: traits(attack['traits']) }
      end

      # An attack a feat, an item or an effect gives them.
      def self.granted(char, strike)
        damage = Pf2eCombat.damage_breakdown(char, strike['name'], nil, false, [], strike)

        { name: strike['name'], attack: Stat.total(char, 'attack', strike), rank: strike['prof'].to_s,
          damage: damage['formula'], materials: materials(strike), source: strike['source'], traits: traits(strike['traits']) }
      end

      def self.materials(attack)
        Array(attack['materials']).map { |one| one.to_s.tr('-', ' ') }
      end

      def self.traits(list)
        ProfileSheet.items(Array(list).map { |trait| titleized(trait) }, 'trait')
      end

      def self.titleized(trait)
        trait.to_s.split('_').map { |word| word.sub(/\A[a-z]/) { |c| c.upcase } }.join(' ')
      end

      def self.crit_spec(char)
        access = Pf2e.crit_spec_access(char)

        access.keys.sort.filter_map do |group|
          effect = Pf2e.crit_spec_effect(group)
          next if effect.blank?

          { group: group, weapons: access[group], effect: effect }
        end
      end
    end
  end
end
