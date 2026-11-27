module AresMUSH
  module Pf2e

    # A feat's `condition_rules`: how a condition lands on its holder, and how fast it eases.
    #
    #   { condition: Frightened, eases_by: 2 }      Frightened drops by 2 at the end of each turn
    #   { condition: Frightened, gained_less: 1 }   Frightened lands 1 lower whenever it is gained
    #   { condition: Drained, flat_check: 17 }      a DC 17 flat check keeps Drained from landing
    #
    # A condition is gained when it is new or its value rises. Easing one never counts.
    module ConditionFeats
      def self.rules(holder, condition)
        FeatKeys.rows(holder, 'condition_rules').select do |_feat, row|
          Pf2e.canonical_condition(row['condition']) == condition
        end
      end

      # How much a condition eases at the end of the holder's turn: the most any feat gives, or 1.
      def self.eases_by(holder, condition)
        ([ 1 ] + rules(holder, condition).map { |_feat, row| row['eases_by'].to_i }).max
      end

      # What a condition being gained comes to: the value it lands at, or an Err when it doesn't land.
      #
      # `before` is the value already held, nil when it is not held at all.
      def self.gaining(holder, condition, before, value)
        return value unless gained?(before, value, holder, condition)

        found = rules(holder, condition)

        found.each do |feat, row|
          next unless row['flat_check']

          rolled = Resolve.flat(row['flat_check'].to_i)

          next unless rolled['success']

          return Err.new(:condition_resisted, 'pf2e.condition_resisted',
                         'name' => holder.name, 'condition' => condition, 'feat' => feat,
                         'die' => rolled['die'], 'dc' => rolled['dc'])
        end

        less = found.map { |_feat, row| row['gained_less'].to_i }.max.to_i

        return value if less.zero? || value.nil?

        lowered = value.to_i - less

        return lowered if lowered > before.to_i

        feat = found.find { |_feat, row| row['gained_less'] }.first
        Err.new(:condition_eased, 'pf2e.condition_eased', 'name' => holder.name, 'condition' => condition, 'feat' => feat)
      end

      def self.gained?(before, value, holder, condition)
        return true if before.nil? && !(holder.pf2_conditions || {}).key?(condition)

        !value.nil? && value.to_i > before.to_i
      end
    end
  end
end
