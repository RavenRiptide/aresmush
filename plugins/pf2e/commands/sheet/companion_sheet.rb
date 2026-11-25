module AresMUSH
  module Pf2e

    # sheet/companion [<character>]: a character's animal companion. Every sheet is open, so anyone may see
    # anyone's. The layout is the familiar sheet's: a title and sections of rows.
    class PF2CompanionSheetCmd
      include CommandHandler

      attr_accessor :target

      def parse_args
        self.target = trim_arg(cmd.args)
      end

      def handle
        char = Pf2e.get_character(self.target, enactor)
        return client.emit_failure(t('pf2e.not_found')) unless char

        view = Companion::SheetView.build(char)
        return client.emit_failure(t('pf2e.companion_none', :char => char.name)) unless view

        client.emit PF2FamiliarSheetTemplate.new(view, client).render
      end
    end
  end
end
