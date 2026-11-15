module AresMUSH
  module Pf2egear

    # `buy/material <category>=<item>/<material>/<grade>`: buys a weapon, armor, or shield made of a precious
    # material (`Pf2egear::Materials`). An uncommon material costs 2 RPP on top of the price, and a rare one 4.
    class PF2BuyMaterialCmd
      include CommandHandler

      attr_accessor :category, :item_name, :material, :grade

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.category = downcase_arg(args.arg1)

        parts = args.arg2.to_s.split('/').map(&:strip)
        self.item_name, self.material, self.grade = parts.map { |one| one.empty? ? nil : one }
      end

      def required_args
        [ self.category, self.item_name, self.material, self.grade ]
      end

      def check_permissions
        return nil if enactor.is_approved?
        return nil if enactor.is_admin?

        t('dispatcher.not_allowed')
      end

      def handle
        quote = Materials.quote(enactor, self.category, self.item_name, self.material, self.grade)

        return if Pf2e::CharState.emit_error!(client, quote)

        state = quote.state
        label = Materials.label(state['name'], state['material'])

        if state['rpp'].positive?
          refused = Player.spend_rpp(enactor, state['rpp'], "Precious material: #{label}")

          return client.emit_failure(refused) if refused
        end

        before = Bulk.standing(enactor)

        Materials.make!(enactor, state)
        Pf2egear.pay_player(enactor, -state['cost'], 'Item Vendor', "Purchase #{label}")

        key = state['rpp'].positive? ? 'pf2egear.material_bought_rpp' : 'pf2egear.material_bought'
        client.emit_success t(key, :item => label, :cost => Pf2egear.display_money(state['cost']), :rpp => state['rpp'])

        warning = Bulk.warning(enactor, before)
        client.emit_ooc warning if warning
      end
    end
  end
end
