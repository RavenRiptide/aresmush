module AresMUSH
  module Pf2e

    class PF2AdvanceFinishCmd
      include CommandHandler

      # Processes advancement and completes the process.

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        msg = Pf2e.do_advancement(enactor, client)

        if msg
          client.emit_failure msg
          return
        end

        client.emit_success t('pf2e.advance_done')

        # A familiar gained this level, or a witch familiar taking over one, waits for staff approval.
        opened = Pf2e::Familiar.after_level!(Character[enactor.id])
        client.emit_ooc opened if opened

      end

    end
  end
end
