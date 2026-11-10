module AresMUSH
  module Pf2egear
    # `buy/rune <category>/<item number>=<rune>`: buys a rune and etches it onto an item the character holds,
    # such as `buy/rune weapons/0=Flaming` or `buy/rune shields/0=Minor Reinforcing`. What it costs and
    # whether it can be had is `RuneVendor`'s.
    class PF2BuyRuneCmd
      include CommandHandler

      attr_accessor :category, :index, :rune

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        where = trim_arg(args.arg1).to_s.match(/\A(\w+)\s*\/\s*(\d+)\z/)

        self.category = where && where[1].downcase
        self.index = where && where[2].to_i
        self.rune = trim_arg(args.arg2)
      end

      def check_permissions
        return nil if enactor.is_approved? || enactor.is_admin?

        t('dispatcher.not_allowed')
      end

      def required_args
        [ self.category, self.index, self.rune ]
      end

      def handle
        found = Pf2egear::Inventory.item(enactor, self.category, self.index)

        return if Pf2e::CharState.emit_error!(client, found)

        item = found.state
        quote = RuneVendor.quote(enactor, item, self.category, self.rune)

        return if Pf2e::CharState.emit_error!(client, quote)

        cost = quote.state['cost']

        if cost > enactor.pf2_money.to_i
          return client.emit_failure(t('pf2egear.not_enough_you', :item => 'money to buy that'))
        end

        RuneVendor.etch!(enactor, item, quote.state)

        key = quote.state['replaces'] ? 'pf2egear.rune_bought_replacing' : 'pf2egear.rune_bought'
        client.emit_success t(key, :rune => quote.state['rune'], :item => RuneVendor.label(item),
                                   :replaced => quote.state['replaces'], :cost => Pf2egear.display_money(cost))
      end
    end
  end
end
