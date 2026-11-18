module AresMUSH
  module Pf2egear
    class PF2GearUnequipCmd
      include CommandHandler

      attr_accessor :category, :item_num

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.category = downcase_arg(args.arg1)
        self.item_num = integer_arg(args.arg2)

        @numcheck = trim_arg(args.arg2)
      end

      def required_args
        [ self.category, self.item_num ]
      end

      # Whose things these are: the enactor's own. In an encounter, their copy there.
      def holder
        enactor
      end

      # What can be taken off again: the same list equipping accepts.
      def check_valid_category
        return nil if PF2GearEquipCmd::EQUIPPABLE.include?(self.category)

        t('pf2egear.bad_category')
      end

      def check_is_number
        return nil if @numcheck.to_i.to_s == @numcheck
        return t('pf2egear.must_specify_by_number')
      end

      def handle
        found = Pf2egear::Inventory.item(holder, self.category, self.item_num)

        return if Pf2e::CharState.emit_error!(client, found)

        item = found.state

        item.update(equipped: false)

        iname = item.nickname ? item.nickname : item.name

        client.emit_success t('pf2egear.item_unequip_ok', :name => iname)

        # In an encounter, plain `unequip` changed their sheet; they hear how to unequip it there too.
        # `encounter/unequip` works on the encounter's copy already, so it has nothing to say.
        return unless holder == enactor

        note = Pf2egear::EncounterGear.sheet_only_note(enactor, self.category, item)

        client.emit_ooc note if note
      end

    end
  end
end
