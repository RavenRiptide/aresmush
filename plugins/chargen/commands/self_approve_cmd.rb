module AresMUSH
  module Chargen
    # Playtest only: a player approves their own character. Staff approve anyone with app/approve.
    class SelfApproveCmd
      include CommandHandler

      def check_playtest
        return nil if Pf2e.playtest?
        return t('pf2e.playtest_only')
      end

      def handle
        error = Chargen.approve_char(enactor, enactor, '')
        if (error)
          client.emit_failure error
        else
          client.emit_success t('chargen.app_approved', :name => enactor.name)
        end
      end
    end
  end
end
