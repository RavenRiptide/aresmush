module AresMUSH
  module Pf2e

    # A creature's shapes, and any other form its abilities let it choose between: Foundry declares each
    # as an option with choices, a werewolf's Change Shape as `change-shape` with hybrid, humanoid and
    # animal. Which Strikes it has hangs on the choice (`Npcs.strikes`), as do the rules that predicate on
    # it. A word naming one of the choices picks it: as the creature is added, `+e/add werewolf/animal`,
    # or as it uses the ability, `+e/as #4=act change shape/animal`, which takes the ability's actions.
    module Shapes

      # Every choice a stat block's abilities declare, before any creature is made of it.
      def self.choices_in(block)
        Array(block['actions']).flat_map { |one| Array(one['rules']) }.select { |rule| rule['key'] == 'RollOption' }
                               .flat_map { |rule| Array(rule['suboptions']).map { |choice| choice['value'].to_s } }.uniq
      end

      # The options with choices its abilities declare, each with the choice it is in.
      #
      #   [ { 'option', 'label', 'choices' => [ value ], 'selected' } ]
      def self.of(npc)
        RollOptions.declared(npc).select { |one| Array(one['choices']).any? }.map do |one|
          { 'option' => one['option'], 'label' => label(one), 'choices' => one['choices'].map { |choice| choice['value'].to_s },
            'selected' => one['selected'] }
        end
      end

      # The option a word names a choice of, among those an ability declares where one is named.
      def self.named(npc, word, ability = nil)
        wanted = Domains.slug(word)
        options = ability ? Array(ability['rules']).select { |rule| rule['key'] == 'RollOption' }.map { |rule| rule['option'] } : nil

        of(npc).find { |one| (options.nil? || options.include?(one['option'])) && one['choices'].any? { |choice| Domains.slug(choice) == wanted } }
      end

      # Takes the shape a word names. Refused, saying the shapes there are, where it has no such shape.
      def self.take!(npc, word)
        found = named(npc, word)

        unless found
          shapes = of(npc).flat_map { |one| one['choices'] }
          return Err.new(:no_shape, 'pf2e.shape_unknown', 'creature' => npc.name, 'shape' => word, 'shapes' => shapes.join(', '))
        end

        choice = found['choices'].find { |one| Domains.slug(one) == Domains.slug(word) }
        RollOptions.set(npc, found['option'], choice)

        Ok.new(:state => found.merge('selected' => choice))
      end

      # A word among those an ability is used with that names one of its own choices: the shape it takes.
      def self.taken_by(npc, ability, words)
        Array(words).each do |word|
          found = named(npc, word, ability)
          return take!(npc, word).state if found
        end

        nil
      end

      # `Change Shape: animal`, for its GM.
      def self.shown(npc)
        of(npc).map { |one| "#{one['label']}: #{one['selected']}" }
      end

      # What a Strike's `when` says, in the words of its stat block: `not as humanoid`, or for an option
      # with no choice named, `only with Pack Attack`.
      def self.when_words(block, statements)
        Array(statements).map do |statement|
          negated = statement.is_a?(Hash) && statement.key?('not')
          option, _, choice = (negated ? statement['not'] : statement).to_s.partition(':')
          kind = choice.empty? ? 'with' : 'as'
          said = choice.empty? ? label_in(block, option) : choice

          t("pf2e.shape_#{negated ? 'not' : 'only'}_#{kind}", :shape => said)
        end.join(', ')
      end

      def self.label(declared)
        words = declared['label'].to_s
        words.empty? || words.start_with?('PF2E.') ? titled(declared['option']) : words
      end

      def self.label_in(block, option)
        rule = Array(block['actions']).flat_map { |one| Array(one['rules']) }.find { |one| one['key'] == 'RollOption' && one['option'] == option }
        rule ? label(rule) : titled(option)
      end

      def self.titled(option)
        option.to_s.split('-').map(&:capitalize).join(' ')
      end
    end
  end
end
