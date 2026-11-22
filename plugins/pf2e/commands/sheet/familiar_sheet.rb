module AresMUSH
  module Pf2e

    # sheet/familiar [<character>]: a character's familiar or pet. Every sheet is open, so anyone may see
    # anyone's.
    class PF2FamiliarSheetCmd
      include CommandHandler

      attr_accessor :target

      def parse_args
        self.target = trim_arg(cmd.args)
      end

      def handle
        char = Pf2e.get_character(self.target, enactor)
        return client.emit_failure(t('pf2e.not_found')) unless char

        view = Familiar::SheetView.build(char)
        return client.emit_failure(t('pf2e.familiar_none', :char => char.name)) unless view

        client.emit PF2FamiliarSheetTemplate.new(view, client).render
      end
    end
  end
end
