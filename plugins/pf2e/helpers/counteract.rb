module AresMUSH
  module Pf2e

    # A counteract check: a d20 and a counteract modifier against the DC of the effect being ended. Its
    # degree of success says how high a rank it can end, measured from the counteract rank (Player Core,
    # Counteracting): up to three ranks above on a critical success, one above on a success, and only a
    # lower rank on a failure.
    module Counteract

      # How far above the counteract rank each degree reaches. A critical failure ends nothing. Read when
      # asked, since this file loads before Degree does.
      def self.reach(degree)
        { Degree::CRITICAL_SUCCESS => 3, Degree::SUCCESS => 1, Degree::FAILURE => -1 }[degree]
      end

      # The highest rank a check of this degree ends, or nil when it ends nothing.
      def self.highest(rank, degree)
        reach = reach(degree)

        reach.nil? ? nil : rank.to_i + reach
      end

      def self.ends?(rank, degree, target_rank)
        top = highest(rank, degree)

        !top.nil? && target_rank.to_i <= top
      end

      # `{ 'die', 'total', 'dc', 'degree' }`. Without a DC there is no degree, only the total for the GM to
      # compare.
      def self.roll(modifier, dc = nil)
        die = Pf2e.roll_dice(1, 20).first.to_i
        total = die + modifier.to_i

        { 'die' => die, 'total' => total, 'dc' => dc, 'degree' => dc ? Degree.of(total, dc.to_i, die) : nil }
      end
    end
  end
end
