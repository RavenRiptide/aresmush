module AresMUSH
  module Pf2e

    # A feat's `concealment`: the flat check its holder rolls to target someone they can't see well, and
    # whether a hidden attacker leaves them off-guard.
    #
    #   { concealed: 0, hidden: 5, hidden_not_off_guard: true }           Blind-Fight
    #   { concealed: 3, hidden: 9, predicate: [ "self:effect:rage" ] }    Supernatural Senses
    #
    # A DC of 0 is no check at all. Where two feats give a DC, the lower counts.
    module FlatChecks
      # What an attacker's own condition makes every target to them: hidden to the blinded, concealed to
      # the dazzled.
      AS = { 'blinded' => 'hidden', 'dazzled' => 'concealed' }.freeze

      def self.dc(holder, concealment)
        base = Resolve.flat_dc(concealment)

        return base unless base

        wanted = AS.fetch(concealment.to_s, concealment.to_s)
        options = nil
        offered = FeatKeys.rows(holder, 'concealment').filter_map do |_feat, row|
          next nil unless row.key?(wanted)

          options ||= Effects.options(holder)

          row[wanted].to_i if Predicate.test(row['predicate'], options)
        end

        ([ base ] + offered).min
      end

      # Whether an attacker with this concealment from the holder leaves them off-guard. Hidden doesn't,
      # with Blind-Fight; undetected always does.
      def self.off_guard_to?(holder, concealment)
        return true unless concealment.to_s == 'hidden'

        FeatKeys.rows(holder, 'concealment').none? { |_feat, row| row['hidden_not_off_guard'] }
      end
    end
  end
end
