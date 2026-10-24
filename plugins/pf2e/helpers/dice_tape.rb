module AresMUSH
  module Pf2e

    # The dice of one change, kept in the order they fell, so the change can be made again with every die
    # as it fell but one.
    #
    # That is what a Hero Point's reroll is. A GM's breath weapon rolls its damage and a save for each of
    # four heroes; one of them spends a Hero Point, and their save alone is rolled again while the damage
    # and the other three saves stand. So each d20 that is someone's check is kept under their name, and
    # every other roll under its shape, `2d6`. Made again, a roll takes the next die kept under its own
    # heading and throws a fresh one when there is none: a new outcome may roll what the first did not, or
    # not roll what it did, and neither moves anyone else's die.
    #
    #   { 'n' => 1, 'd' => 20, 'faces' => [ 7 ], 'who' => 'Aria' }
    #   { 'n' => 2, 'd' => 6, 'faces' => [ 3, 4 ] }
    #
    # `kept` is on a check rolled twice, for fortune or misfortune, and `hero` on the one a Hero Point
    # rolled again.
    module DiceTape

      RECORDING = :pf2e_dice_recording
      REPLAYING = :pf2e_dice_replaying
      CHECK = :pf2e_dice_check

      # Runs the block and answers the dice it rolled.
      def self.recording
        previous = Thread.current[RECORDING]
        made = Thread.current[RECORDING] = []

        yield

        made
      ensure
        Thread.current[RECORDING] = previous
      end

      # Runs the block with the dice of `tape` falling as they did, but for the last check `who` made in
      # it: that one is `face` where one is given, and thrown afresh where not.
      def self.replaying(tape, who:, face: nil)
        previous = Thread.current[REPLAYING]
        mine = Array(tape).select { |row| row['who'] == who }
        Thread.current[REPLAYING] = { 'waiting' => Array(tape).group_by { |row| heading(row) }, 'who' => who, 'face' => face,
                                      'swap' => mine.size - 1, 'seen' => 0 }

        yield
      ensure
        Thread.current[REPLAYING] = previous
      end

      # The d20 rolled in the block is `who`'s check; `kept` says it is rolled twice, and which is kept.
      # A check inside one already named keeps that name where it has none of its own.
      def self.for_check(who, kept = nil)
        previous = Thread.current[CHECK]
        Thread.current[CHECK] = { 'who' => who || (previous || {})['who'], 'kept' => kept }.compact

        yield
      ensure
        Thread.current[CHECK] = previous
      end

      def self.heading(row)
        row['who'] ? "check:#{row['who']}" : "#{row['n']}d#{row['d']}"
      end

      # One roll: the die the replay holds for it, or else what the block throws.
      def self.draw(amount, sides)
        row = { 'n' => amount.to_i, 'd' => sides.to_i }
        row = row.merge(Thread.current[CHECK] || {}) if row['n'] == 1 && row['d'] == 20
        replay = Thread.current[REPLAYING]
        was = replay ? Array(replay['waiting'][heading(row)]).shift : nil

        row = if replay && again?(replay, row)
                row.merge('faces' => replay['face'] ? [ replay['face'] ] : yield, 'hero' => true)
              else
                # A die that falls as it did keeps that a Hero Point was once spent on it.
                was && was['faces'].size == row['n'] ? row.merge(was.slice('faces', 'hero')) : row.merge('faces' => yield)
              end

        Thread.current[RECORDING] << row if Thread.current[RECORDING]

        row['faces']
      end

      # Whether this roll is the check the replay rolls again: theirs are counted as they come.
      def self.again?(replay, row)
        return false unless row['who'] && row['who'] == replay['who']

        at = replay['seen']
        replay['seen'] += 1

        at == replay['swap']
      end

      # Whether a Hero Point was spent on any check of `who`'s in a tape.
      def self.hero?(tape, who)
        Array(tape).any? { |row| row['who'] == who && row['hero'] }
      end

      # The last check `who` made in a tape, if they made one.
      def self.last_check(tape, who)
        Array(tape).select { |row| row['who'] == who }.last
      end
    end
  end
end
