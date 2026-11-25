module AresMUSH
  module Pf2e

    # `pf2ProfileSheet` - the Sheet tab of a character's profile: `{ id }`.
    class PF2ProfileSheetHandler
      def handle(request)
        ProfileSheet.answer(request, 'sheet') { |char| SheetView.of(char) }
      end
    end

    # `pf2ProfileCombat` - the Combat tab: `{ id }`.
    class PF2ProfileCombatHandler
      def handle(request)
        ProfileSheet.answer(request, 'combat') { |char| CombatSheetView.of(char) }
      end
    end

    # `pf2ProfileFormulas` - the Formulas tab: `{ id }`.
    class PF2ProfileFormulasHandler
      def handle(request)
        ProfileSheet.answer(request, 'formulas') { |char| FormulasView.of(char) }
      end
    end

    # `pf2ProfileFamiliar` - the Familiar tab: `{ id }`.
    class PF2ProfileFamiliarHandler
      def handle(request)
        ProfileSheet.answer(request, 'familiar') { |char| FamiliarView.of(char) }
      end
    end

    # `pf2ProfileCompanion` - the Animal Companion tab: `{ id }`.
    class PF2ProfileCompanionHandler
      def handle(request)
        ProfileSheet.answer(request, 'companion') { |char| Companion::ProfileView.of(char) }
      end
    end
  end
end
