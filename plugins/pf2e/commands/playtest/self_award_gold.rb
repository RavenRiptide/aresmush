module AresMUSH
  module Pf2e
    # Playtest only: pays an approved character the lump sum a new character of their level starts
    # with, so one built and advanced straight to a higher level can outfit themselves. Nothing
    # tracks a claim - each one pays again.
    class PF2SelfAwardGoldCmd
      include CommandHandler

      def check_playtest
        return nil if Pf2e.playtest?
        return t('pf2e.playtest_only')
      end

      def check_approval
        return nil if enactor.is_approved?
        return t('pf2e.not_approved')
      end

      def handle
        level = enactor.pf2_level.to_i
        owed = Pf2e.playtest_wealth_owed(level)

        return client.emit_failure(t('pf2e.playtest_gold_none', :level => level)) unless owed.positive?

        Pf2egear.pay_player(enactor, owed, enactor.name, "Playtest starting wealth for level #{level}")

        client.emit_success t('pf2e.playtest_gold_claimed', :amount => Pf2egear.display_money(owed), :level => level)
      end

    end
  end
end
