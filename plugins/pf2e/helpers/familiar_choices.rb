module AresMUSH
  module Pf2e
    module Familiar

      # What a player picks for their familiar from closed lists: a specific familiar (Player Core 2
      # pp. 170-171), a plain Pet's two abilities, and the choices those make (a Pipefox's Skilled skill, a
      # Homunculus's Porter, Leshy Familiar's Plant or Fungus). Each answer is matched against config without
      # regard to case and stored as config spells it. Each check returns Ok carrying what to store, or an Err.
      module Choices

        # The longest list `parse_list` reads, so a pasted wall of text is refused before it is walked.
        LIST_MAX = 200

        # What `familiar/choose` calls each choice, by what asks for it: an ability a specific familiar gives,
        # one of its own choices, or Leshy Familiar's free Plant or Fungus.
        WORDS = { 'Skilled' => 'skill', 'Speech' => 'language', 'linguist' => 'language', 'porter' => 'ability',
                  'leshy' => 'ability' }.freeze

        # Skilled can't raise the skills a familiar already uses its master's attribute for.
        SKILLED_EXCEPT = %w{Acrobatics Stealth}.freeze

        # ----------------------------------------------------------------------------------------------
        # Reading a list
        # ----------------------------------------------------------------------------------------------

        # "Fast Movement (land), Tough" as [ { 'name' => 'Fast Movement', 'choice' => 'land' }, { 'name' => 'Tough' } ],
        # split on commas outside parentheses. nil when it can't be read: too long, parentheses that don't
        # pair, or one nested in another.
        def self.parse_list(text)
          raw = Details.clean(text)
          return nil if raw.empty? || raw.length > LIST_MAX

          parts = [ +'' ]
          depth = 0

          raw.each_char do |char|
            depth += 1 if char == '('
            depth -= 1 if char == ')'
            return nil if depth.negative? || depth > 1

            char == ',' && depth.zero? ? parts << +'' : parts.last << char
          end
          return nil unless depth.zero?

          parts.map(&:strip).map do |part|
            found = part.match(/\A([^()]+?)\s*(?:\(([^()]*)\))?\z/)
            return nil unless found

            choice = found[2].to_s.strip
            choice.empty? ? { 'name' => found[1].strip } : { 'name' => found[1].strip, 'choice' => choice }
          end
        end

        def self.find_in(list, answer)
          Array(list).find { |one| one.to_s.casecmp?(answer.to_s.strip) }
        end

        # ----------------------------------------------------------------------------------------------
        # Which familiar may pick what
        # ----------------------------------------------------------------------------------------------

        def self.feat(name)
          found = Global.read_config('pf2e_feats', name.to_s)
          found.is_a?(Hash) ? found : {}
        end

        # A pet from the Pet feat and nothing that gives a familiar: its two abilities are fixed when it is
        # gained, and it has no daily ones.
        def self.plain_pet?(char)
          held = Familiar.sources(char)

          held.any? && held.none? { |one| one['feature'] || feat(one['name'])['familiar'] == true }
        end

        # The source that keeps their familiar from being a specific familiar: a plain pet, or a familiar that
        # is a particular creature (`familiar_no_specific`: Rat Familiar's rat, Leshy Familiar's leshy,
        # Alchemical Familiar's construct). A merged source keeps that.
        def self.fixed_source(char)
          return Familiar.main_source(char)['name'] if plain_pet?(char)

          Familiar.sources(char).find { |one| !one['feature'] && feat(one['name'])['familiar_no_specific'] }&.fetch('name')
        end

        def self.specific_names
          (Global.read_config('pf2e_specific_familiars') || {}).keys
        end

        def self.specific_config(name)
          Stats.specific_config(name)
        end

        # The highest rank the master casts spells of from spell slots, or 0.
        def self.top_slot_rank(char)
          magic = char.magic
          return 0 unless magic

          Pf2emagic::Entries.slots_by_source(magic).values.flat_map do |slots|
            slots.select { |rank, count| !rank.to_s.casecmp?('cantrip') && count.to_i.positive? }.keys
          end.map(&:to_i).max.to_i
        end

        # familiar/specific: a name from the catalogue, or 'none' (stored as nil).
        def self.specific(char, raw)
          answer = Details.clean(raw)
          return Ok.new(:state => nil) if answer.casecmp?('none')

          name = find_in(specific_names, answer)
          return Err.new(:familiar_specific_unknown, 'pf2e.familiar_specific_unknown', 'list' => specific_names.join(', ')) unless name

          fixed = fixed_source(char)
          return Err.new(:familiar_specific_fixed, 'pf2e.familiar_specific_fixed', 'source' => fixed) if fixed

          info = specific_config(name)

          if Familiar.details(char)['form'] == 'aquatic' && !info['aquatic']
            return Err.new(:familiar_specific_aquatic, 'pf2e.familiar_specific_aquatic', 'name' => name)
          end

          uses = info['uses'].to_i
          count = Stats.ability_count(char)
          return Err.new(:familiar_specific_uses, 'pf2e.familiar_specific_uses', 'name' => name, 'uses' => uses, 'count' => count) if count < uses

          rank = (info['prereq'] || {})['slot_rank'].to_i
          return Err.new(:familiar_specific_slots, 'pf2e.familiar_specific_slots', 'name' => name, 'rank' => rank) if top_slot_rank(char) < rank

          Ok.new(:state => name)
        end

        # familiar/form: a specific familiar is aquatic only where its rules say it can be.
        def self.form_allowed(char, form)
          name = Familiar.details(char)['specific']
          return Ok.new(:state => form) if form != 'aquatic' || name.blank? || specific_config(name)['aquatic']

          Err.new(:familiar_form_specific, 'pf2e.familiar_form_specific', 'name' => name)
        end

        # ----------------------------------------------------------------------------------------------
        # A plain Pet's two abilities
        # ----------------------------------------------------------------------------------------------

        def self.pet_ability_names
          (Global.read_config('pf2e_familiar_abilities') || {}).select { |_name, info| info['pet'] }.keys
        end

        # familiar/pet: two different pet abilities, with Fast Movement naming one of the speeds the pet has.
        def self.pet_abilities(char, raw)
          return Err.new(:familiar_not_pet, 'pf2e.familiar_not_pet') unless plain_pet?(char)

          list = parse_list(raw)
          return Err.new(:familiar_list_unreadable, 'pf2e.familiar_list_unreadable') unless list
          return Err.new(:familiar_pet_two, 'pf2e.familiar_pet_two') unless list.size == 2

          picked = list.map do |one|
            name = find_in(pet_ability_names, one['name'])
            return Err.new(:familiar_pet_unknown, 'pf2e.familiar_pet_unknown', 'list' => pet_ability_names.join(', ')) unless name

            one.merge('name' => name)
          end

          return Err.new(:familiar_pet_twice, 'pf2e.familiar_pet_twice') if picked.map { |one| one['name'] }.uniq.size < 2

          picked.each_with_index.map do |one, index|
            next one.except('choice') unless (Global.read_config('pf2e_familiar_abilities', one['name']) || {})['choice']

            others = picked.reject.with_index { |_other, at| at == index }.map { |other| other.except('choice') }
            speeds = speeds_with(char, others)
            speed = find_in(speeds, one['choice'])
            return Err.new(:familiar_pet_choice, 'pf2e.familiar_pet_choice', 'ability' => one['name'], 'list' => speeds.join(', ')) unless speed

            one.merge('choice' => speed)
          end.then { |stored| Ok.new(:state => stored) }
        end

        # The speeds a pet has with these abilities, which Fast Movement may raise: never a burrow Speed, which
        # its own ChoiceSet leaves out.
        def self.speeds_with(char, abilities)
          stats = Stats.of(char, abilities, :form => Familiar.details(char)['form'].presence || 'land')
          (stats ? stats['speeds'].keys : []) & %w{land swim climb fly}
        end

        # ----------------------------------------------------------------------------------------------
        # familiar/choose
        # ----------------------------------------------------------------------------------------------

        # The choices their familiar has open, by the word `familiar/choose` takes:
        # { 'skill' => { 'label' => 'pf2e.familiar_choice_skilled', 'options' => [ … ] } }.
        def self.open_choices(char, shown = Familiar.details(char))
          out = {}
          info = specific_config(shown['specific'])

          Array(info['choices']).each do |asked|
            options = case asked
                      when 'Skilled' then (Global.read_config('pf2e_skills') || {}).keys - SKILLED_EXCEPT
                      when 'Speech' then known_languages(char)
                      when 'linguist' then common_languages - known_languages(char)
                      when 'porter' then Array(info['porter'])
                      end

            word = WORDS[asked]
            out[word] = { 'label' => "pf2e.familiar_choice_#{asked.downcase}", 'options' => options } if word && options
          end

          leshy = Array(Stats.innate(char)['choose'].first)
          out['ability'] ||= { 'label' => 'pf2e.familiar_choice_leshy', 'options' => leshy } unless leshy.empty?

          out
        end

        def self.known_languages(char)
          Array(char.pf2_lang).map(&:to_s).reject(&:empty?)
        end

        def self.common_languages
          (Global.read_config('pf2e_languages', 'common') || {}).keys
        end

        # familiar/choose <word>=<answer>: Ok carrying [ word, answer ].
        def self.choose(char, word, raw)
          open = open_choices(char)
          return Err.new(:familiar_choice_none, 'pf2e.familiar_choice_none') if open.empty?

          asked = open[word.to_s.strip.downcase]
          return Err.new(:familiar_choice_word, 'pf2e.familiar_choice_word', 'words' => open.keys.join(', ')) unless asked

          answer = find_in(asked['options'], Details.clean(raw))
          unless answer
            return Err.new(:familiar_choice_unknown, 'pf2e.familiar_choice_unknown', 'label' => t(asked['label']),
                           'list' => asked['options'].join(', '))
          end

          Ok.new(:state => [ word.to_s.strip.downcase, answer ])
        end

        # What approval still needs from these picks, as `familiar_field_*` keys: a plain Pet's two abilities,
        # and every choice open but not made (or made from a list that has since moved on).
        def self.missing(char, shown)
          gaps = []
          gaps << 'pet_abilities' if plain_pet?(char) && Array(shown['pet_abilities']).size != 2

          made = shown['choices'] || {}
          open_choices(char, shown).each do |word, asked|
            gaps << word unless find_in(asked['options'], made[word])
          end

          gaps
        end
      end
    end
  end
end
