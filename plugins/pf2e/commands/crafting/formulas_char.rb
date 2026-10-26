module AresMUSH
  module Pf2e

    class PF2DisplayFormulasCmd
      include CommandHandler

      attr_accessor :character

      def parse_args
        self.character = cmd.args
      end

      def check_can_view_other
        return nil unless self.character
        return nil if enactor.has_permission?("manage_sheet")
        return t('dispatcher.not_allowed')
      end

      def handle

        char = Pf2e.get_character(self.character, enactor)

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

        template = PF2FormulaTemplate.new(char.pf2_formula_book, char, client)

        client.emit template.render

      end

    end
  end
end