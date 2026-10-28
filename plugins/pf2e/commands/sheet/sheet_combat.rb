module AresMUSH
  module Pf2e

    class PF2DisplayCombatSheetCmd
      include CommandHandler

      attr_accessor :target

      def parse_args
        self.target = trim_arg(cmd.args)
      end

      def handle
        char = Pf2e.get_character(self.target, enactor)

        if !char
          client.emit_failure t('pf2e.char_not_found')
          return
        end

        # Not before approval: until then the feats picked in chargen are only a draft, and their
        # attacks and bonuses are not on the sheet this reads.
        outcome = Pf2e::Sheet.viewable?(enactor, char, 'combat')
                    .and_then { Pf2e::Sheet.available(char, 'combat') }
                    .and_then { char.is_approved? ? Ok.new(:state => 'combat') : Err.new(:csheet_not_approved) }

        return if Pf2e::CharState.emit_error!(client, outcome)

        rendered = Pf2e::SheetReads.holding(char) { PF2CombatSheetTemplate.new(char, client).render }

        client.emit rendered
      end

    end

  end
end
