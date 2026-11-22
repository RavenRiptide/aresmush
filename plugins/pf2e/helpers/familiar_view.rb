module AresMUSH
  module Pf2e

    # The Familiar tab of a character's profile, as plain data: an approved familiar's or pet's stats and
    # abilities, from the same reads as `sheet/familiar`. Anyone may open a profile, so its sentences name
    # the familiar and its master instead of speaking to the master.
    module FamiliarView

      # The casting source whose spells a witch's familiar contains, or nil for a familiar with no spells.
      def self.spell_source(char)
        main = Familiar.main_source(char)
        return nil unless main && main['kind'] == 'spellbook'

        main['feature'] ? 'Witch' : Array(Familiar::Choices.feat(main['name'])['assoc_archetype']).first.to_s
      end

      def self.of(char)
        approved = Familiar.approved_record(char)
        return nil unless approved

        main = Familiar.main_source(char)
        stats = Familiar::SheetView.stats(char, approved)
        name = approved['name'].presence || t('pf2e.familiar_sheet_unnamed')
        pet = Familiar::Choices.plain_pet?(char)
        speeds = stats['speeds'] || {}
        skilled = stats['skilled'] || (stats['skills'].keys - Familiar::Stats::KEPT_SKILLS)

        { name: name, master: char.name, pet: pet, image: FamiliarPicture.path(char),
          species: capitalized(approved['species']), form: capitalized(approved['form'].presence || 'land'),
          source: Familiar::SheetView.source_label('char' => char, 'main' => main),
          level: stats['level'].to_i, size: capitalized(stats['size']),
          traits: ProfileSheet.items(Array(stats['traits']).map { |trait| capitalized(trait) }.sort, 'trait'),
          hp: stats['hp'], ac: stats['ac'].to_i, perception: stats['perception'].to_i, attack: stats['attack'].to_i,
          saves: (stats['saves'] || {}).map { |save, value| { name: capitalized(save), value: value.to_i } },
          resistances: Array(stats['resistances']).map { |one| "#{one['type'].to_s.tr('-', ' ')} #{one['value']}" },
          weaknesses: Array(stats['weaknesses']).map { |one| "#{one['type'].to_s.tr('-', ' ')} #{one['value']}" },
          immunities: Array(stats['immunities']).map { |one| one.to_s.tr('-', ' ') },
          speed: speeds['land'] ? speeds['land'].to_i : nil,
          special_movement: speeds.except('land').map { |movement, value| { movement: movement, feet: value.to_i } },
          senses: Array(stats['senses']),
          skills: (stats['skills'] || {}).map { |skill, value| { name: skill, value: value.to_i, skilled: skilled.include?(skill) } },
          other_skills: stats['other_skills'].to_i,
          pet_abilities: pet ? abilities(approved['pet_abilities']) : nil,
          specific: specific(char, approved),
          today: pet ? nil : today(char),
          spells: spells(char, name),
          notes: t('pf2e.profile_familiar_notes', :name => name, :char => char.name) }
      end

      def self.capitalized(text)
        Familiar::SheetView.capitalized(text)
      end

      # Abilities as named things, each with the choice it was taken with: "Resistance (fire, cold)".
      def self.abilities(list)
        Array(list).map do |one|
          choice = Array(one['choice']).join(', ')

          ProfileSheet.item(one['name'], 'familiar_ability', choice.empty? ? nil : "#{one['name']} (#{choice})")
        end
      end

      # A specific familiar: what it gives and the names of its own abilities.
      def self.specific(char, approved)
        named = approved['specific']
        return nil if named.blank?

        info = Familiar::Stats.specific_config(named)
        given = Familiar.fixed_abilities(char).select do |one|
          Array(info['abilities']).include?(one['name']) || Array(info['porter']).include?(one['name'])
        end

        { name: ProfileSheet.item(named, 'specific_familiar'), uses: info['uses'].to_i,
          count: Familiar::Stats.ability_count(char), gives: abilities(given), specials: (info['specials'] || {}).keys }
      end

      # The abilities picked at today's preparations, the patron's, and the ones it has for free.
      def self.today(char)
        picked = Familiar::Daily.today(char).map do |one|
          one['name'] == Familiar::Daily::REINFORCED ? one.merge('name' => t('pf2e.familiar_sheet_reinforced')) : one
        end
        catalogue = Familiar::Daily.catalogue
        innate = Familiar::Stats.innate(char)
        patron = Familiar::Stats.patron_ability(char)
        free = Familiar.fixed_abilities(char).map { |one| one['name'] } & (innate['abilities'] + innate['choose'].flatten) - [ patron ]
        familiar, master = picked.partition { |one| (catalogue[one['name']] || {})['kind'] != 'master' }

        { picked: Familiar::Daily.today(char).size, budget: Familiar::Daily.budget(char),
          familiar: abilities(familiar), master: abilities(master),
          patron: patron ? ProfileSheet.item(patron, 'familiar_ability') : nil,
          free: ProfileSheet.items(free, 'familiar_ability') }
      end

      # How many witch spells a witch's familiar contains.
      def self.spells(char, name)
        source = spell_source(char)
        return nil unless source

        known = char.magic ? Pf2emagic::Entries.known(char.magic, source) : {}
        counted = known.each_with_object(Hash.new(0)) do |(rank, list), out|
          out[rank.to_s.casecmp?('cantrip') ? 'cantrips' : 'spells'] += Array(list).count { |one| !one.to_s.casecmp?(Pf2emagic::Entries::OPEN) }
        end

        { source: source, cantrips: counted['cantrips'], spells: counted['spells'],
          text: t('pf2e.profile_familiar_spells', :name => name, :char => char.name, :cantrips => counted['cantrips'], :spells => counted['spells']) }
      end
    end
  end
end
