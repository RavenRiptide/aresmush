module AresMUSH
  module Pf2e

    # What a saved creature may not be: whatever would keep the engine from fighting with it. A creature
    # with any of these is not saved, so everything in the database can be added to an encounter.
    #
    # Each finding is `{ 'code', 'key', 'args' }`, for a command to tell and a spec to read by its code.
    module CreatureCheck

      FORMULA = /\A\d*d\d+(?:[+-]\d+)?\z|\A\d+\z/i
      LEVELS = (-1..25).freeze
      LONGEST = 60

      def self.found(code, args = {})
        { 'code' => code, 'key' => "pf2e.#{code}", 'args' => args }
      end

      def self.errors(block)
        needs(block) + level(block) + strikes(block) + abilities(block)
      end

      def self.needs(block)
        %w{ac hp}.reject { |field| block[field].to_i.positive? }.map { |field| found(:creature_needs, 'figure' => field.upcase) }
      end

      def self.level(block)
        LEVELS.cover?(block['level'].to_i) ? [] : [ found(:creature_level, 'level' => block['level'], 'from' => LEVELS.first, 'to' => LEVELS.last) ]
      end

      def self.strikes(block)
        listed = Array(block['strikes'])

        listed.flat_map do |strike|
          named = strike['name'].to_s.strip
          next [ found(:creature_unnamed, 'what' => 'Strike') ] if named.empty?

          damage = Array(strike['damage'])
          next [ found(:creature_strike_damage, 'strike' => named) ] if damage.empty?

          damage.reject { |formula, _type, _category| formula.to_s.delete(' ').match?(FORMULA) }
                .map { |formula, _type, _category| found(:creature_formula, 'formula' => formula, 'strike' => named) }
        end + twice(listed, 'Strike')
      end

      def self.abilities(block)
        listed = Array(block['actions'])

        listed.flat_map do |ability|
          named = ability['name'].to_s.strip
          next [ found(:creature_unnamed, 'what' => 'ability') ] if named.empty?

          problems = []
          problems << found(:creature_ability_text, 'ability' => named) if ability['text'].to_s.strip.empty?
          problems << found(:creature_ability_cost, 'ability' => named) if ability['type'] == 'action' && !(1..3).cover?((ability['cost'] || 1).to_i)
          problems
        end + twice(listed, 'ability')
      end

      # Two of a kind under one name, which `creature/set` and `+e/as` could not tell apart.
      def self.twice(listed, what)
        listed.map { |one| one['name'].to_s.strip.downcase }.reject(&:empty?).tally.select { |_name, count| count > 1 }
              .map { |name, _count| found(:creature_twice, 'what' => what, 'name' => name) }
      end

      # A name a saved creature may take: one `+e/add` can read back, and not a bestiary creature's, which
      # the bestiary keeps. `bestiary` answers the bestiary's creature of that name, if any.
      def self.name(words, bestiary = ->(term) { Bestiary.named(term) })
        named = words.to_s.strip

        return Err.new(:creature_name_empty, 'pf2e.creature_name_empty') if named.empty?
        return Err.new(:creature_name_long, 'pf2e.creature_name_long', 'most' => LONGEST) if named.length > LONGEST
        return Err.new(:creature_name_mark, 'pf2e.creature_name_mark') if named.match?(%r{[=;#/]|\Ac(?:ustom)?:}i)
        return Err.new(:creature_name_count, 'pf2e.creature_name_count') if named.match?(/\A\d+\s/)
        return Err.new(:creature_name_adjusted, 'pf2e.creature_name_adjusted', 'word' => named.split.first) if
          Adjustments.names.include?(named.split.first.downcase)

        taken = bestiary.call(named)

        return Err.new(:creature_name_bestiary, 'pf2e.creature_name_bestiary', 'name' => taken) if taken

        Ok.new(:state => named)
      end
    end
  end
end
