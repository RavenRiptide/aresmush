module AresMUSH
  module Pf2emagic

    # `pf2ProfileSpells` - the Spells tab of a character's profile: `{ id }`.
    class PF2ProfileSpellsHandler
      def handle(request)
        Pf2e::ProfileSheet.answer(request, 'spells') { |char| SpellsView.of(char) }
      end
    end
  end
end
