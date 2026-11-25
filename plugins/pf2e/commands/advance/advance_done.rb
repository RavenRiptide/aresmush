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
        # Worked out while the level is still open: once it commits, there is no draft to compare with.
        companion = Pf2e::Companion::Preview.closing_line(enactor)
        coming_off = Pf2e::Companion::Gear.coming_off_at_level(enactor)

        msg = Pf2e.do_advancement(enactor, client)

        if msg
          client.emit_failure msg
          return
        end

        client.emit_success t('pf2e.advance_done')
        client.emit_ooc companion if companion

        # Barding the companion has outgrown comes off with the level.
        Pf2e::Companion::Gear.settle!(Character[enactor.id])
        coming_off.each do |item|
          client.emit_ooc t('pf2e.companion_gear_came_off', :name => Pf2e::Companion::Gear.wearer(Character[enactor.id])['name'], :item => item)
        end

        # A familiar gained this level, or a witch familiar taking over one, waits for staff approval.
        opened = Pf2e::Familiar.after_level!(Character[enactor.id])
        client.emit_ooc opened if opened

        # A companion gained this level waits for staff to approve its name, but not to stop the next level.
        named = Pf2e::Companion.after_level!(Character[enactor.id])
        client.emit_ooc named if named

      end

    end
  end
end
