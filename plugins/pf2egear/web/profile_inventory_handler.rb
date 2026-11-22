module AresMUSH
  module Pf2egear

    # `pf2ProfileInventory` - the Inventory tab of a character's profile: `{ id }`.
    class PF2ProfileInventoryHandler
      def handle(request)
        Pf2e::ProfileSheet.answer(request, 'inventory') { |char| InventoryView.of(char) }
      end
    end
  end
end
