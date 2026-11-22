module AresMUSH
  module Pf2e

    # The Sheet tab of a character's profile, as plain data: what `sheet` shows outside an encounter. Numbers
    # are numbers and ranks are words (`trained`, `expert`); the portal lays them out. Every figure comes from
    # the helper the in-game sheet reads it from, so the two can't disagree on a number.
    module SheetView

      SAVES = %w{fortitude reflex will}.freeze
      WEAPON_CATEGORIES = %w{simple martial unarmed advanced bomb}.freeze

      # How the sheet heads each bucket of feats, in the order it lists them.
      FEAT_BUCKETS = [ [ 'ancestry', 'Ancestry' ], [ 'charclass', 'Class' ], [ 'dedication', 'Archetype' ],
                       [ 'skill', 'Skill' ], [ 'general', 'General' ] ].freeze

      def self.of(char)
        base = char.pf2_base_info || {}
        faith = char.pf2_faith || {}

        { name: char.name, level: char.pf2_level.to_i,
          identity: identity(char, base, faith),
          traits: ProfileSheet.items(char.pf2_traits.map(&:capitalize).sort, 'trait'),
          size: size_word((char.pf2_movement || {})['Size']),
          attributes: attributes(char),
          defenses: defenses(char),
          iwr: iwr(IWR.sheet_rows(Actors.of(char).sheet_iwr)),
          movement: movement(Movement.for(char)),
          senses: Array(char.pf2_special).sort,
          proficiencies: proficiencies(char, faith),
          skills: skills(char),
          feats: feats(char),
          features: features(char),
          languages: ProfileSheet.items(DraftSheet.of(char).languages.sort, 'language'),
          known_for: Array(char.pf2_known_for).sort }
      end

      SIZES = { 'T' => 'Tiny', 'S' => 'Small', 'M' => 'Medium', 'L' => 'Large', 'H' => 'Huge', 'G' => 'Gargantuan' }.freeze

      # The sheet keeps a size as its letter; a trait names it in full.
      def self.size_word(size)
        SIZES[size.to_s.strip.upcase] || size.presence
      end

      def self.identity(char, base, faith)
        charclass = base['charclass'].to_s
        subclass = base['specialize'].to_s

        { charclass: charclass, ancestry: base['ancestry'], heritage: base['heritage'], background: base['background'],
          subclass_label: (Global.read_config('pf2e', 'subclass_names') || {})[charclass] || 'Specialty',
          subclass: subclass.empty? ? nil : subclass,
          subclass_option: base['specialize_info'].presence,
          archetypes: archetype_labels(char),
          faith: char.group('Faith'), region: char.group('Region'),
          deity: faith['deity'].presence, alignment: faith['alignment'].presence, sanctification: faith['sanctification'].presence }
      end

      # "Sorcerer (Imperial)", one per archetype taken, with its specialty and the choice made within it.
      def self.archetype_labels(char)
        info = char.pf2_archetypeinfo || {}

        (1..4).filter_map do |index|
          name = info["archetype#{index}"].to_s.strip
          next if name.empty?

          specialty = info["archetype_specialty#{index}"].to_s.strip
          choice = info["archetype_specialty_choice#{index}"].to_s.strip
          shown = name.sub(/ Archetype$/, '')

          next shown if specialty.empty?

          "#{shown} (#{choice.empty? ? specialty : "#{specialty} - #{choice}"})"
        end
      end

      # The class's key attribute is marked, and so is one an invested apex item raises.
      def self.attributes(char)
        raised = Apex.attribute(char).to_s
        key = char.combat&.key_abil.to_s

        Array(char.abilities.to_a).map do |row|
          score = Pf2eAbilities.get_score(char, row.name).to_i

          { name: row.name, modifier: Pf2eAbilities.abilmod(score), partial: score > 18 && score.odd?,
            key: key.casecmp?(row.name.to_s), apex: raised.casecmp?(row.name.to_s) }
        end
      end

      def self.defenses(char)
        combat = char.combat

        { hp: char.hp ? Pf2eHP.get_max_hp(char) : nil,
          ac: Pf2eCombat.calculate_ac(char),
          perception: combat ? { value: Pf2eCombat.get_perception(char), rank: combat.perception } : nil,
          class_dc: combat ? { value: Pf2eCombat.get_class_dc(char), rank: combat.class_dc } : nil,
          archetype_dcs: archetype_dcs(char),
          saves: saves(char) }
      end

      def self.saves(char)
        SAVES.map do |save|
          { name: save.capitalize, value: Pf2eCombat.get_save_bonus(char, save), rank: Pf2eCombat.get_save_from_char(char, save) }
        end
      end

      def self.archetype_dcs(char)
        dcs = Pf2eCombat.get_archetype_class_dcs(char)

        dcs.keys.sort.map do |archetype|
          info = dcs[archetype]

          { name: archetype.sub(/ Archetype$/, ''), value: info['dc'], rank: info['prof'], attribute: info['key_abil'].to_s }
        end
      end

      # [ word, what ] rows, as the sheet lists resistances, immunities and weaknesses.
      def self.iwr(rows)
        rows.map { |word, shown| { label: word, value: shown.to_s.sub(/\.\z/, '') } }
      end

      def self.movement(result)
        special = Movement.special_text(result)
        conditional = Movement.conditional_text(result)

        { speed: Movement.speed_text(result),
          special: special == 'None.' ? nil : special,
          conditional: conditional == 'None.' ? nil : conditional }
      end

      def self.proficiencies(char, faith)
        combat = char.combat
        return { weapons: [], individual: [], groups: [], armor: [] } unless combat

        weapon = combat.weapon_prof || {}

        { weapons: WEAPON_CATEGORIES.select { |kind| weapon[kind] }.map { |kind| { name: kind.capitalize, rank: weapon[kind] } },
          individual: individual_weapons(char, faith),
          groups: (combat.weapon_group_prof || {}).keys.sort.map do |group|
            ranks = (combat.weapon_group_prof || {})[group] || {}

            { name: group, ranks: %w{simple martial unarmed advanced}.to_h { |kind| [ kind.to_sym, ranks[kind] || ranks[kind.to_sym] ] } }
          end,
          armor: (combat.armor_prof || {}).keys.sort.map { |kind| { name: kind.capitalize, rank: combat.armor_prof[kind] } } }
      end

      # The weapons a character is trained in by name: the ones a feat let them choose, and their deity's.
      def self.individual_weapons(char, faith)
        deity = deity_weapon(char, faith)
        names = Pf2e.chosen_weapons(char).dup
        names << deity if deity && names.none? { |name| name.to_s.casecmp?(deity) }

        names.sort.map do |name|
          { name: name, rank: Pf2eCombat.get_weapon_prof(char, name), deity: !!(deity && name.to_s.casecmp?(deity)) }
        end
      end

      # The deity's favored weapon, for a character whose class makes them trained in it.
      def self.deity_weapon(char, faith)
        return nil unless char.combat&.weapon_prof&.dig('deity')
        return nil if faith['deity'].blank?

        favored = Global.read_config('pf2e_deities', faith['deity'], 'fav_weapon')
        return nil if favored.blank?

        (Global.read_config('pf2e_weapons') || {}).keys.find { |weapon| weapon.to_s.casecmp?(favored.to_s) }
      end

      # The skills they are trained in, including one a daily choice trains them in for the day.
      def self.skills(char)
        char.skills.to_a
            .reject { |row| row.prof_level.to_s.strip.empty? || Pf2eSkills.rolling_prof(char, row.name).to_s == 'untrained' }
            .sort_by(&:name)
            .map do |row|
              { name: row.name, kind: Pf2eSkills.lore?(row.name) ? 'lore' : 'skill',
                value: Pf2eSkills.get_skill_bonus(char, row.name), rank: Pf2eSkills.rolling_prof(char, row.name).to_s,
                attribute: Pf2eSkills.get_linked_attr(row.name).to_s[0..2].upcase }
            end
      end

      # Each bucket's feats, one entry per taking, with the choice each was taken for.
      def self.feats(char)
        buckets = DraftSheet.of(char).feats_by_bucket

        groups = FEAT_BUCKETS.filter_map do |bucket, heading|
          names = Array(buckets[bucket])
          next if names.empty?

          { type: heading, items: feat_items(char, names) }
        end

        # A feat a daily choice lends them for the day (Combat Flexibility).
        lent = DailyChoices.feats(char).map do |one|
          ProfileSheet.item(one['feat'], 'feat', DailyChoices.label('pick' => one['feat'], 'choice' => one['choice']))
        end
        groups << { type: 'Today', items: lent } unless lent.empty?

        groups
      end

      def self.feat_items(char, names)
        Pf2e.feat_display_list(char, names).map do |label|
          name = names.find { |one| label == one || label.start_with?("#{one} (") } || label

          ProfileSheet.item(name, 'feat', label)
        end.sort_by { |found| found[:label] || found[:name] }
      end

      # Only the highest step of a progression shows, as on `sheet`.
      def self.features(char)
        { class: ProfileSheet.items(FeatureLadders.collapse(Pf2e.feature_display_list(char, 'charclass_features')), 'feature'),
          archetype: ProfileSheet.items(FeatureLadders.collapse(Pf2e.feature_display_list(char, 'archetype_features')), 'feature') }
      end
    end
  end
end
