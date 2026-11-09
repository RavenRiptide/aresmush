module AresMUSH
  module Pf2egear

    # `wand/repair <character>=<number>`: staff mend a wand an overcharge broke, on the character's own sheet.
    # A wand they have with them in a running encounter is mended there instead, by the GM with
    # `encounter/repair`, since the encounter's copy is what settles back.
    class PF2WandRepairCmd
      include CommandHandler

      attr_accessor :who, :number

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.who = trim_arg(args.arg1)
        self.number = integer_arg(args.arg2)
      end

      def required_args
        [ self.who, self.number ]
      end

      def check_permissions
        return nil if enactor.has_permission?('manage_sheet')

        t('dispatcher.not_allowed')
      end

      def handle
        found = ClassTargetFinder.find(self.who, Character, enactor)

        return client.emit_failure(t('pf2e.char_not_found')) unless found.found?

        char = found.target
        item = Pf2egear::Inventory.item(char, 'magicitem', self.number)

        return if Pf2e::CharState.emit_error!(client, item)
        return client.emit_failure(t('pf2egear.not_found')) unless item.state

        held = Pf2e::Equipment.held_by(item.state)

        return client.emit_failure(t('pf2e.wand_repair_in_encounter', :item => item.state.name, :id => held.id)) if held

        mended = Pf2e::SpellItems.repair!(item.state)

        return if Pf2e::CharState.emit_error!(client, mended)

        client.emit_success t('pf2e.wand_repaired_staff', :who => char.name, :item => mended.state)
      end
    end
  end
end
