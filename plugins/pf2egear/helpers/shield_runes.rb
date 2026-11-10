module AresMUSH
  module Pf2egear

    # A shield's Hardness and Hit Points with its reinforcing rune (GM Core). Each grade adds to both, up to
    # a maximum; a shield already past the maximum keeps its own, so the rune never lowers it. The broken
    # threshold is half the Hit Points, as for every shield.
    #
    # The shield's stored `hardness` and `hp` stay its own, so taking the rune off puts them back. Anything
    # reading a shield's Hardness or Hit Points reads them here. A creature's stat-block shield has no runes
    # and reads as it is.
    module ShieldRunes

      GRADES = (0..6).freeze

      def self.reinforcing(shield)
        return 0 unless shield.respond_to?(:runes)

        (shield.runes || {}).dig('fundamental', 'reinforcing').to_i
      end

      # The grade's row in `pf2e_fundamental_runes.yml`, or nil for none.
      def self.grade(number)
        return nil unless number.to_i.positive?

        (Global.read_config('pf2e_fundamental_runes', 'shield', 'reinforcing') || {})[number.to_i]
      end

      def self.hardness(shield)
        raised(shield.hardness.to_i, grade(reinforcing(shield)), 'hardness')
      end

      def self.max_hp(shield)
        raised(shield.hp.to_i, grade(reinforcing(shield)), 'hp')
      end

      # The rune's name, or nil for a shield with none.
      def self.name(shield)
        grade(reinforcing(shield))&.dig('name')
      end

      # Foundry's `adjustFromUpgrades`: the increase on top, and past the maximum, the maximum or the
      # shield's own, whichever is higher.
      def self.raised(own, row, field)
        change = row && row[field]

        return own unless change

        sum = own + change['increase'].to_i
        max = change['max'].to_i

        sum > max ? [ own, max ].max : sum
      end
    end
  end
end
