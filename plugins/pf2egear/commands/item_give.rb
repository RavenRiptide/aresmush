module AresMUSH
  module Pf2egear

    # `item/give <character>=<category>/<name>[/<deity>]`, or `[/<material>/<grade>]` for a precious material:
    # staff create an item and give it to a character,
    # charging its catalogue price. `item/give/force` gives an item above the character's level, still
    # charging, and `item/give/free` neither checks the level nor charges (`Pf2egear::ItemGiving`).
    class PF2ItemGiveCmd
      include CommandHandler

      attr_accessor :who, :category, :name, :extra

      # After the item's name: the deity for an item made for one, or a precious material and grade.
      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.who = trim_arg(args.arg1)

        parts = args.arg2.to_s.split('/').map(&:strip)
        self.category = parts[0].to_s.empty? ? nil : parts[0].downcase
        self.name = parts[1].to_s.empty? ? nil : parts[1]
        self.extra = parts[2..] || []
      end

      def required_args
        [ self.who, self.category, self.name ]
      end

      def check_permissions
        return nil if enactor.has_permission?('manage_sheet')

        t('dispatcher.not_allowed')
      end

      def check_switch
        return nil if [ 'give', 'give/free', 'give/force' ].include?(cmd.switch)

        t('pf2egear.give_bad_switch', :switch => cmd.switch)
      end

      def free?
        cmd.switch == 'give/free'
      end

      def handle
        found = ClassTargetFinder.find(self.who, Character, enactor)

        return client.emit_failure(t('pf2e.char_not_found')) unless found.found?

        char = found.target
        running = PF2Encounter.running_for(char).first

        return client.emit_failure(t('pf2egear.give_in_encounter', :char => char.name, :id => running.id)) if running

        prepared = ItemGiving.prepare(char, self.category, self.name, self.extra,
                                      :charge => !free?, :check_level => cmd.switch == 'give')

        return if Pf2e::CharState.emit_error!(client, prepared)

        ItemGiving.give!(char, prepared.state, :by => enactor.name)

        named = ItemGiving.display_name(prepared.state)
        cost = prepared.state['cost']
        paid = cost.positive? ? t('pf2egear.give_paid', :cost => Pf2egear.display_money(cost)) : t('pf2egear.give_unpaid')

        client.emit_success t('pf2egear.give_ok', :char => char.name, :item => named, :paid => paid)

        message = t('pf2egear.given_to_you', :from => enactor.name, :item => named, :paid => paid)

        Login.notify(char, :pf2_gear, message, prepared.state['name'])

        recipient = Login.find_game_client(char)
        recipient.emit_ooc message if recipient && char != enactor
      end
    end
  end
end
