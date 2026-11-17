module AresMUSH
  module Pf2e

    # Chargen used to store a monk's fist as 1d6. Powerful Fist's own rule now makes it a d6, read when
    # the fist is attacked with, so a stored 1d6 would be stepped up again to a d8. Every fist is stored
    # as 1d4 now; this puts back the ones stored before that.
    module FistDie

      STORED = '1d6'.freeze
      BASE = '1d4'.freeze

      # Whether the character's stored fist needed putting back, and was. Only a fist that Powerful Fist
      # will step up is touched: a character without the feature in play keeps the die they have.
      def self.restore!(char)
        combat = char.combat
        attacks = combat&.unarmed_attacks || {}
        fist = attacks['Fist']

        return false unless fist.is_a?(Hash) && fist['damage'].to_s == STORED
        return false unless Effects.features(char).any? { |source| source['name'] == 'Powerful Fist' }

        combat.update(:unarmed_attacks => attacks.merge('Fist' => fist.merge('damage' => BASE)))
        true
      end

      # Every character's fist put back, and the names of those whose was.
      def self.restore_all!
        Character.all.select { |char| restore!(char) }.map(&:name).sort
      end
    end
  end
end
