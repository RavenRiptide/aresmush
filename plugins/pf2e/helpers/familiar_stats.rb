module AresMUSH
  module Pf2e
    module Familiar

      # A familiar's statistics, from its master and the abilities it has (Player Core p. 212, and the Pet
      # feat for a pet). It reads and never writes.
      #
      #   Level            the master's
      #   Hit Points       5 per level, plus what its abilities add (Tough)
      #   AC and saves     the master's, less circumstance and status bonuses and penalties; item bonuses
      #                    stay, because they are part of the master's figure (a Spellslime's AC is its own)
      #   Perception,      level + the source's attribute modifier, or level + 3 if that is higher; a pet
      #   Acrobatics,      with no spellcasting source uses 3
      #   Stealth
      #   Other skills     level, plus what an ability adds (Skilled adds the attribute modifier)
      #   Attack           level
      #   Speed            25 feet on land, or a 25-foot swim Speed and no land Speed for an aquatic form
      #   Senses           low-light vision, plus what its abilities give
      #   Traits           minion, and animal unless an ability or a specific familiar replaces it
      #
      # Abilities are `[ { 'name' => 'Skilled', 'choice' => 'Occultism' } ]`, the choice being what its
      # ChoiceSet asks (a list for an ability that asks twice, such as Resistance). Their rules apply with
      # the familiar as `@actor`, so `@actor.level` is the familiar's level and `@actor.masterAttributeModifier`
      # the master's attribute modifier.
      module Stats

        SPEED = 25
        HP_PER_LEVEL = 5
        SAVES = %w{Fortitude Reflex Will}.freeze
        KEPT_SKILLS = %w{Acrobatics Stealth}.freeze

        # The master's modifiers a familiar doesn't share.
        UNSHARED = %w{circumstance status}.freeze

        # nil for a character with no familiar. `form` is 'land' or 'aquatic'; `specific` a name from
        # pf2e_specific_familiars.yml; `options` what is true of it today (Poppet's `self:reinforced`).
        def self.of(master, abilities = [], form: 'land', specific: nil, options: [])
          main = Familiar.main_source(master)
          return nil unless main

          key = [ :familiar_stats, master.class.name, master.id.to_s, abilities, form.to_s, specific.to_s, options ]
          ReadCache.kept(key) { build(master, main, abilities, form.to_s, specific, Array(options)) }
        end

        def self.build(master, main, abilities, form, specific, options)
          level = master.pf2_level.to_i
          attribute = attribute_of(master, main)
          modifier = attribute ? Pf2e.ability_mod(master, attribute) : nil
          special = specific_config(specific)

          sources = abilities.filter_map { |one| ability_source(one, level) }
          sources << Effects.source(specific, special['rules'], 'item' => { 'level' => level }) if special['rules']

          context = context_of(level, modifier, sources, options)
          kept = level + [ 3, modifier.to_i ].max

          { 'source' => main['name'],
            'level' => level,
            'size' => 'tiny',
            'attribute' => attribute,
            'hp' => HP_PER_LEVEL * level + flat(sources, [ 'hp' ], options, context),
            'ac' => special['ac'] ? Formula.value(special['ac'], context).to_i : shared(master, 'ac'),
            'saves' => SAVES.each_with_object({}) { |save, out| out[save] = shared(master, 'save', save) },
            'perception' => kept,
            'attack' => level,
            'skills' => skills(sources, level, kept, options, context),
            'other_skills' => level,
            'speeds' => speeds(sources, abilities, form, special, options, context),
            'senses' => senses(sources, special, options),
            'traits' => traits(sources, abilities, form, special, options, context),
            'immunities' => declared(sources, 'Immunity', options, context).map { |one| one['type'] }.uniq,
            'resistances' => strongest(declared(sources, 'Resistance', options, context)),
            'weaknesses' => strongest(declared(sources, 'Weakness', options, context)),
            'ability_count' => ability_count(master) }
        end

        # ------------------------------------------------------------------------------------------------
        # What it shares with its master
        # ------------------------------------------------------------------------------------------------

        # The master's figure without the bonuses and penalties a familiar doesn't share.
        def self.shared(master, kind, name = nil)
          figure = Stat.of(master, kind, name)
          unshared = Array(figure['modifiers']).select { |row| row['enabled'] && UNSHARED.include?(row['type'].to_s.downcase) }

          figure['total'].to_i - unshared.sum { |row| Modifiers.value_of(row) }
        end

        # The attribute its Perception, Acrobatics and Stealth may use: the master's class key attribute for
        # a class's familiar (Familiar, Leshy Familiar, Alchemical Familiar, the witch's), the archetype's for
        # a dedication's (Witch Dedication), and none for a pet.
        def self.attribute_of(master, main)
          return Stat.class_attribute(master, nil) if main['feature']

          details = Global.read_config('pf2e_feats', main['name']) || {}

          archetype = Array(details['assoc_archetype']).first
          return Array((Global.read_config('pf2e_archetype', archetype) || {})['key_abil']).first if archetype

          charclass = (master.pf2_base_info || {})['charclass']
          Array(details['assoc_charclass']).include?(charclass) ? Stat.class_attribute(master, nil) : nil
        end

        # How many abilities it may have each day, from the master's `familiarAbilities` fact. A witch's
        # count includes their patron's ability (Foundry's formula counts it), which is free and named apart,
        # so it is left out here.
        def self.ability_count(master)
          held = Paths.held(master, 'familiarabilities-value').to_i

          held - (patron_ability(master) ? 1 : 0)
        end

        # The witch patron's ability: a witch's familiar has it always, and a dedicant's doesn't ("you don't
        # gain any other effects the patron would usually grant").
        def self.patron_ability(master)
          info = master.pf2_base_info || {}
          return nil unless info['charclass'] == 'Witch' && Familiar.witch_feature?(master)

          (Global.read_config('pf2e_familiar_abilities') || {}).find do |_name, details|
            details['kind'] == 'patron' && details['patron'].to_s == info['specialize'].to_s
          end&.first
        end

        # Abilities it has without choosing them, outside the count: the patron's, and each source's
        # `familiar_innate` (Alchemical Familiar's Construct). Merged sources keep theirs. `choose` lists
        # each set the player picks one from at approval (Leshy Familiar's Plant or Fungus).
        def self.innate(master)
          held = Familiar.sources(master).reject { |one| one['feature'] }
                         .map { |one| (Global.read_config('pf2e_feats', one['name']) || {})['familiar_innate'] }
                         .select { |one| one.is_a?(Hash) }

          { 'abilities' => ([ patron_ability(master) ].compact + held.flat_map { |one| Array(one['abilities']) }).uniq,
            'choose' => held.map { |one| Array(one['choose']) }.reject(&:empty?) }
        end

        # ------------------------------------------------------------------------------------------------
        # What its abilities give
        # ------------------------------------------------------------------------------------------------

        def self.specific_config(name)
          return {} if name.blank?

          found = Global.read_config('pf2e_specific_familiars', name)
          found.is_a?(Hash) ? found : {}
        end

        # An ability as a source its rules are read from, with its choice where its ChoiceSets read it.
        def self.ability_source(one, level)
          name = one['name'].to_s
          details = Global.read_config('pf2e_familiar_abilities', name)
          return nil unless details.is_a?(Hash)

          rules = Array(details['rules'])
          selections = selections(rules, one['choice'])

          Effects.source(name, rules, 'item' => { 'level' => level, 'flags' => { 'system' => { 'rulesSelections' => selections } } })
        end

        # Each ChoiceSet's flag, with the answer the player gave in the order the sets ask, stored as the
        # set's own value ('Occultism' answers Skilled with `occultism`).
        def self.selections(rules, choice)
          answers = Array(choice).map(&:to_s)
          sets = rules.select { |row| row['key'] == 'ChoiceSet' && row['flag'] }

          sets.each_with_index.each_with_object({}) do |(set, index), out|
            answer = answers[index]
            next if answer.blank?

            listed = set['choices'].is_a?(Array) ? set['choices'] : []
            found = listed.find { |one| [ one['label'], one['value'] ].any? { |held| held.to_s.casecmp?(answer) } }

            out[set['flag']] = found ? found['value'] : Domains.slug(answer)
          end
        end

        # What a formula on its rules may read. The flags are what its own rules write for others to read:
        # Resistance records the kinds it chose, and Major Resistance reads them.
        def self.context_of(level, modifier, sources, options)
          actor = { 'level' => level, 'masterAttributeModifier' => modifier.to_i }
          flags = Rules.writes(sources, options, 'actor' => actor).each_with_object({}) do |write, out|
            next unless write['path'].to_s.start_with?(Paths::FLAG)

            name = write['path'].delete_prefix(Paths::FLAG)
            out[name] = Paths::MODES.fetch(write['mode'], Paths::MODES['override']).call(out[name], write['value'])
          end

          { 'actor' => actor.merge('flags' => { 'system' => flags }) }
        end

        def self.flat(sources, domains, options, context)
          Rules.gather(sources, domains, options, 'FlatModifier') { |row, _source| Formula.value(row['value'], context).to_i }.sum
        end

        def self.declared(sources, kind, options, context)
          Rules.declarations(sources, options, kind, context).flat_map do |one|
            Array(one['type']).map { |type| one.merge('type' => type.to_s) }
          end
        end

        # One resistance or weakness to a kind: the strongest.
        def self.strongest(declared)
          declared.group_by { |one| one['type'] }.map { |type, ones| { 'type' => type, 'value' => ones.map { |one| one['value'].to_i }.max } }
        end

        # Acrobatics and Stealth at the kept modifier, and any skill an ability raises above the level.
        def self.skills(sources, level, kept, options, context)
          raised = (Global.read_config('pf2e_skills') || {}).keys.each_with_object({}) do |skill, out|
            next if KEPT_SKILLS.include?(skill)

            bonus = flat(sources, [ Domains.slug(skill) ], options, context)
            out[skill] = level + bonus unless bonus.zero?
          end

          KEPT_SKILLS.each_with_object({}) { |skill, out| out[skill] = kept }.merge(raised)
        end

        # Fast Movement makes one of its speeds 40 feet; Foundry leaves that to the player's choice, so its
        # rule doesn't carry it and this applies it.
        def self.speeds(sources, abilities, form, special, options, context)
          base = if form == 'aquatic' then { 'swim' => SPEED }
                 elsif special['no_land_speed'] then {}
                 else { 'land' => SPEED }
                 end

          granted = Rules.speeds(sources, options, context).transform_values { |one| one['value'].to_i }
          speeds = base.merge(granted) { |_movement, held, given| [ held, given ].max }

          fast = abilities.find { |one| one['name'].to_s == 'Fast Movement' }
          movement = fast && Array(fast['choice']).first.to_s.downcase
          speeds[movement] = 40 if movement.present? && speeds.key?(movement)

          speeds
        end

        def self.senses(sources, special, options)
          granted = Rules.senses(sources, options).map do |one|
            range = one['range'] ? " #{one['range']} feet" : ''
            acuity = one['acuity'] ? " (#{one['acuity']})" : ''

            "#{one['sense'].to_s.tr('-', ' ')}#{acuity}#{range}"
          end

          ([ 'low-light vision' ] + granted + Array(special['senses'])).uniq
        end

        def self.traits(sources, abilities, form, special, options, context)
          replaced = Array(special['traits']).any? || abilities.any? do |one|
            (Global.read_config('pf2e_familiar_abilities', one['name'].to_s) || {})['changes_trait']
          end

          held = [ 'minion' ] + (replaced ? [] : [ 'animal' ]) + Array(special['traits']).map(&:to_s)
          held << 'aquatic' if form == 'aquatic'

          changes = Rules.contributions(sources, 'ActorTraits', options, context)
          added = changes.flat_map { |one| one['add'] }
          removed = changes.flat_map { |one| one['remove'] }

          (held + added).uniq - removed
        end
      end
    end
  end
end
