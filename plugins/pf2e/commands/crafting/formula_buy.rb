module AresMUSH
  module Pf2e

    # What the formula commands share: the catalogue entry a player named, and learning it.
    module LearnsFormulas
      def entry
        @entry ||= Crafting.entry(self.category, self.name)
      end

      def check_entry
        return nil if entry.ok?

        t(entry.key, **CharState.symbolize(entry.args))
      end

      def check_known
        return nil unless Crafting.known?(enactor, self.category, entry.state.first)

        t('pf2e.formula_known', :formula => entry.state.first)
      end
    end

    # `formula/buy <category>=<item>` - buys a common formula at the price PF2e sets for an item of its
    # level, from the character's own money.
    class PF2FormulaBuyCmd
      include CommandHandler
      include LearnsFormulas

      attr_accessor :category, :name

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.category = downcase_arg(args.arg1)
        self.name = trim_arg(args.arg2)
      end

      def required_args
        [ self.category, self.name ]
      end

      def handle
        named, info = entry.state
        price = Crafting.price(info['level'])

        return client.emit_failure(t('pf2e.formula_not_common', :formula => named)) unless Crafting.common?(info)
        return client.emit_failure(t('pf2egear.not_enough_you', :item => 'money for that formula')) if price > enactor.pf2_money.to_i

        Pf2egear.pay_player(enactor, -price, enactor.name, t('pf2e.formula_bought_reason', :formula => named))
        Crafting.learn!(enactor, self.category, named, :source_type => 'bought', :source_ref => "formula: #{named}",
                                                       :granted_by => enactor.name)

        client.emit_success t('pf2e.formula_bought', :formula => named,
                                                     :price => Pf2egear.display_money(price).strip)
      end
    end

    # `formula/reverse <category>=<item>` - works out a formula from an item you carry: a Crafting check
    # against what the item's level makes it, paying the formula's price in materials on a success.
    class PF2FormulaReverseCmd
      include CommandHandler
      include LearnsFormulas

      attr_accessor :category, :name

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.category = downcase_arg(args.arg1)
        self.name = trim_arg(args.arg2)
      end

      def required_args
        [ self.category, self.name ]
      end

      def handle
        named, info = entry.state

        return client.emit_failure(t('pf2e.formula_not_held', :item => named)) unless carries?(named)

        price = Crafting.price(info['level'])
        dc = Crafting.craft_dc(info)
        check = Check.of(enactor, 'skill', 'Crafting')
        result = Resolve.roll(check, :dc => dc)
        roll = Telling.value(Telling.roll(result))

        spent = spent_on(result['degree'], price)
        Pf2egear.pay_player(enactor, -spent, enactor.name, t('pf2e.formula_worked_out_reason', :formula => named)) if spent.positive?

        if result['degree'] >= Degree::SUCCESS
          Crafting.learn!(enactor, self.category, named, :source_type => 'crafted', :source_ref => "formula: #{named}",
                                                         :granted_by => enactor.name)
        end

        client.emit t('pf2e.formula_worked_out', :name => enactor.name, :formula => named, :roll => roll, :dc => dc,
                                                 :degree => Telling.value(Telling.degree(result['degree'])),
                                                 :spent => Pf2egear.display_money(spent).strip)
      end

      # What the materials cost: the whole price where it worked, half of it wasted on a critical failure,
      # and nothing where they simply got nowhere.
      def spent_on(degree, price)
        return price if degree >= Degree::SUCCESS
        return price / 2 if degree == Degree::CRITICAL_FAILURE

        0
      end

      def carries?(named)
        Pf2egear::Inventory.held(enactor, self.category).any? { |item| item.name.casecmp?(named) }
      end
    end
  end
end
