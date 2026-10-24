module AresMUSH
  module Pf2e
    module Encounters

      # Whose turn it is, and what moving through the order does to the round.
      #
      # `at` is the encounter's `next_init`: one past whoever's turn it is, so the turn is `at - 1`. Moving
      # on makes `at` the turn; backing up makes the one before the turn the turn.
      #
      # Pure: a list size, a position and a round number in, the new position and round out.
      module Turn

        # One row per direction. `step` moves the position; `wraps` says the move crosses a round
        # boundary, which is where the round counter changes.
        DIRECTIONS = {
          'next' => {
            'label' => 'pf2e.init_advances',
            'wraps' => lambda { |ctx| ctx[:at].zero? },
            'round' => lambda { |ctx| ctx[:round].to_i + 1 },
            'current' => lambda { |ctx| ctx[:at] }
          },
          'prev' => {
            'label' => 'pf2e.init_backs_up',
            # Backing up from the round's first turn lands on the last one of the round before.
            'wraps' => lambda { |ctx| ((ctx[:at] - 1) % ctx[:size]).zero? },
            'round' => lambda { |ctx| ctx[:round].to_i - 1 },
            'current' => lambda { |ctx| (ctx[:at] - 2) % ctx[:size] }
          }
        }.freeze

        def self.directions
          DIRECTIONS.keys
        end

        # Where the order stands after moving one step.
        #
        #   current  the participant whose turn it now is, as an index
        #   upcoming the one after them
        #   round    the round number, changed only when the move crossed a boundary
        #   new_round whether it did
        def self.move(direction, size:, at:, round:)
          row = DIRECTIONS[direction.to_s]

          return Err.new(:unknown_direction, 'pf2e.bad_option', 'element' => 'direction',
                         'options' => directions.join(', ')) unless row
          return Err.new(:no_participants, 'pf2e.encounter_empty') if size.to_i < 1

          ctx = { :size => size.to_i, :at => at.to_i, :round => round.to_i }
          wraps = row['wraps'].call(ctx)
          current = row['current'].call(ctx)

          Ok.new(:state => {
            'current' => current,
            'upcoming' => (current + 1) % size.to_i,
            'round' => wraps ? row['round'].call(ctx) : round.to_i,
            'new_round' => wraps,
            'label' => row['label']
          })
        end
      end
    end
  end
end
