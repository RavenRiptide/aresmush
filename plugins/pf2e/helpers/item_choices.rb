module AresMUSH
  module Pf2e

    # The choice a player makes when investing some items, and how the item's rules read it.
    #
    # Foundry writes the choice in one of two shapes. A `ChoiceSet` names a flag that the item's other rules
    # read: a Charm of Resistance's `damageType`. A `RollOption` that is always active and has suboptions is
    # the other shape, an Entertainer's Cincture's skill, and the choice is filed where Foundry files a
    # suboption, under the option's name camel-cased. A `RollOption` that isn't always active is a toggle the
    # player switches as they use the item, such as a Shadow Signet's, and `sheet/option` sets it.
    #
    # The choices are kept on the item (`PF2MagicItem#answers`), so they go wherever the item goes. An item
    # made for a deity (`made_for: deity` in its catalogue row) needs no choice when invested: the player
    # specifies the deity when buying it, and the item's rules read that deity's Divine Skill.
    module ItemChoices

      def self.made_for_deity?(info)
        (info || {})['made_for'].to_s == 'deity'
      end

      # `[ { 'key', 'prompt', 'answers' => [ [ value, label ] ] } ]`, in the order the rules ask them.
      def self.questions(name, info)
        return [] if made_for_deity?(info)

        built = Effects.source(name, Array((info || {})['rules']))

        sets = Rules.of_kind(built, 'ChoiceSet').filter_map do |row|
          set = Rules.choice_sets(built.merge('rules' => [ row ])).first
          answers = set ? set_answers(set) : []

          next nil if answers.empty? || set['owned']

          { 'key' => set['flag'].to_s, 'prompt' => row['prompt'], 'answers' => answers }
        end

        options = Rules.of_kind(built, 'RollOption').filter_map do |row|
          next nil unless row['alwaysActive'] && row['toggleable']

          answers = Rules.choices_of(row).map { |one| [ one['value'], (one['label'] || one['value']).to_s ] }

          next nil if answers.empty?

          { 'key' => Effects.camel(row['option']), 'prompt' => row['label'], 'answers' => answers }
        end

        # An apex item raising Intelligence: a skill and a language, chosen the first time it's invested.
        sets + options + Apex.questions(info)
      end

      # A set's answers with their labels: listed ones as listed, and a vocabulary's as its own words.
      def self.set_answers(set)
        listed = Array(set['choices'])

        return listed.map { |one| [ one['value'].to_s, (one['label'] || one['value']).to_s ] } if listed.any?

        Choices.offer(set, nil).map { |value| [ value.to_s, value.to_s.tr('-', ' ').split.map(&:capitalize).join(' ') ] }
      end

      # The value an answer typed for this question stands for, matched by value or by label, or nil.
      def self.match(question, typed)
        wanted = Domains.slug(typed)

        found = question['answers'].find do |value, label|
          value.to_s == typed.to_s || Domains.slug(value) == wanted || label.to_s.casecmp?(typed.to_s)
        end

        found&.first
      end

      def self.answers?(question, held)
        Array(held).any? { |one| question['answers'].any? { |value, _label| value.to_s == one.to_s } }
      end

      def self.labels(questions)
        Array(questions).flat_map { |one| one['answers'].map(&:last) }.join(', ')
      end

      # The answers an item is invested with: what it already held, with the one typed in place of whatever
      # answered the same question. An Err while a question is still open. `how` is what to type to answer,
      # for the refusal to show.
      def self.for_investing(name, info, held, typed, how: nil)
        questions = questions(name, info)
        held = Array(held).map(&:to_s)

        # Several choices are separated as the command separates its parts: a crown's skill and language.
        typed.to_s.split(%r{[=/]}).map(&:strip).reject(&:empty?).each do |one|
          question = questions.find { |asked| match(asked, one) }

          return Err.new(:bad_choice, 'pf2egear.invest_bad_choice', 'item' => name, 'choice' => one,
                         'choices' => labels(questions)) unless question

          held = held.reject { |kept| answers?(question, [ kept ]) } + [ match(question, one) ]
        end

        open = questions.select { |one| !answers?(one, held) }

        return Err.new(:needs_choice, 'pf2egear.invest_needs_choice', 'item' => name,
                       'cmd' => "#{how}#{'/<choice>' * open.size}", 'choices' => labels([ open.first ])) if open.any?

        Ok.new(:state => held)
      end

      # The deity an item is bought for, by the catalogue's spelling.
      def self.deity_named(item_name, typed)
        deities = (Global.read_config('pf2e_deities') || {}).keys.sort
        listed = deities.join(', ')

        return Err.new(:needs_deity, 'pf2egear.buy_needs_deity', 'item' => item_name, 'deities' => listed) if typed.to_s.strip.empty?

        found = deities.find { |one| one.casecmp?(typed.to_s.strip) }

        return Err.new(:bad_deity, 'pf2egear.buy_bad_deity', 'deity' => typed.to_s.strip, 'deities' => listed) unless found

        Ok.new(:state => found)
      end

      def self.divine_skill(deity)
        deity ? Global.read_config('pf2e_deities', deity.to_s, 'divine_skill') : nil
      end

      # What an item's rules are answered with: its own answers, and, for an item made for a deity, that
      # deity's Divine Skill.
      def self.chosen(item, info)
        held = Array(item.respond_to?(:answers) ? item.answers : []).map(&:to_s)
        skill = made_for_deity?(info) && item.respond_to?(:deity) ? divine_skill(item.deity) : nil

        skill ? held + [ skill ] : held
      end

      # An item's source with its answers filled in where its rules look for them.
      def self.answered(char, built, chosen)
        built = Effects.with_selections(char, built)
        extra = suboption_selections(built, chosen)

        return built if extra.empty?

        held = (built['item'] || {}).dig('flags', 'system', 'rulesSelections') || {}

        built.merge('item' => (built['item'] || {}).merge(
                      'flags' => { 'system' => { 'rulesSelections' => held.merge(extra) } }))
      end

      def self.suboption_selections(built, chosen)
        Rules.of_kind(built, 'RollOption').each_with_object({}) do |row, out|
          next unless row['alwaysActive'] && row['toggleable']

          values = Rules.choices_of(row).map { |one| one['value'] }
          found = Array(chosen).map(&:to_s).find { |one| values.include?(one) }

          out[Effects.camel(row['option'])] = found if found
        end
      end

      # The lines `item/view` shows: the deity an item was made for, and what its owner chose.
      def self.describe(item, info)
        lines = []

        if made_for_deity?(info) && item.respond_to?(:deity) && item.deity
          lines << t('pf2egear.item_made_for', :deity => item.deity, :skill => divine_skill(item.deity) || '?')
        end

        questions(item.name, info).each do |question|
          value = Array(item.respond_to?(:answers) ? item.answers : []).find { |one| answers?(question, [ one ]) }
          label = question['answers'].find { |answer, _label| answer.to_s == value.to_s }&.last

          lines << (label ? t('pf2egear.item_choice', :choice => label) : t('pf2egear.item_no_choice'))
        end

        lines
      end
    end
  end
end
