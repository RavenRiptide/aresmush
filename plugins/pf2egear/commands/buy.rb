module AresMUSH
  module Pf2egear
    class PF2BuyCmd
      include CommandHandler

      attr_accessor :category, :item_name, :quantity

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_optional_arg3)
        self.category = downcase_arg(args.arg1)
        self.item_name = downcase_arg(args.arg2)
        self.quantity = integer_arg(args.arg3)
      end

      def required_args
        [ self.category, self.item_name ]
      end

      def check_permissions
        return nil if enactor.is_approved?
        return nil if enactor.is_admin?
        return t('dispatcher.not_allowed')
      end

      def check_valid_quantity
        return nil if !self.quantity
        return nil if self.quantity.positive?
        return t('pf2egear.bad_quantity')
      end

      # `buy/rank5 scroll=Fireball`: a heightened scroll or wand. Nil for the spell's own rank. A switch can't
      # hold digits, so the command reads as switch `rank` with the number left over, which is taken from what
      # was typed.
      def rank
        return nil unless cmd.switch == 'rank'

        found = cmd.raw.to_s.match(%r{/rank\s*(\d+)}i)

        found ? found[1].to_i : nil
      end

      def check_switch
        return nil if cmd.switch.nil? || rank

        t('pf2e.spell_item_bad_switch', :switch => cmd.switch)
      end

      def handle
        kind = Pf2e::SpellItems.kind(self.category)

        return buy_spell_item(kind) if kind
        return client.emit_failure(t('pf2e.spell_item_bad_switch', :switch => cmd.switch)) if cmd.switch

        charlevel = enactor.pf2_level

        # If no quantity is specified, assume they want just one.
        q = self.quantity ? self.quantity : 1

        list_key = "pf2e_" + self.category

        # Valid category of items?
        list = Global.read_config(list_key)

        if !list
          client.emit_failure t('pf2egear.bad_category')
          return
        end

        # The list of items in that category gets filtered by character level.
        # What only a class feature makes - a versatile vial - is never for sale.
        available_items = list.select { |k,v| v['level'] <= charlevel && !v['made_only'] }

        # Does that item exist in that category?
        item = available_items.select { |k,v| k.downcase.include? (self.item_name) }

        if item.size.zero?
          client.emit_failure t('pf2egear.not_found')
          return
        elsif item.size > 1
          item = available_items.select { |k,v| k.downcase == self.item_name }

          if item.size.zero?
            client.emit_failure t('pf2egear.not_found')
            return
          end

          item_name = item.keys.first
          item_info = item.values.first
        else
          item_name = item.keys.first
          item_info = item.values.first
        end

        # A stocked specialty wand holds no spell of its own; it's bought with the spell it holds.
        if Pf2e::SpellItems.specialty_catalogue?(item_name)
          client.emit_failure t('pf2e.spell_item_specialty_buy', :item => item_name)
          return
        end

        if !Pf2e::ItemAccess.accessible?(enactor, self.category, item_name, item_info)
          client.emit_failure t('pf2egear.no_access', :item => item_name, :rarity => Pf2e::ItemAccess.rarity(item_info))
          return
        end

        # Only gear and consumables stack; a weapon has its own runes, so each is its own item.
        if q > 1 && !Pf2egear::Inventory.stackable?(self.category)
          client.emit_ooc t('pf2egear.quantity_one_only')
          q = 1
        end

        # Do they have enough money?
        cost = item_info['price'] * q
        purse = enactor.pf2_money

        if cost > purse
          client.emit_failure t('pf2egear.not_enough_you', :item => 'money to buy that')
          return
        end

        before = Pf2egear::Bulk.standing(enactor)

        # Create the item.

        Pf2egear.create_item(enactor, self.category, item_name, q, item_info)

        Pf2egear.pay_player(enactor, -cost, 'Item Vendor', "Purchase #{item_name}")

        client.emit_success t('pf2egear.item_bought_ok', :item => item_name, :cost => Pf2egear.display_money(cost), :quantity => q)

        warning = Pf2egear::Bulk.warning(enactor, before)

        client.emit_ooc warning if warning

      end

      # A scroll or a wand: one generic item carrying its spell, priced by the spell's rank
      # (`Pf2e::SpellItems`).
      def buy_spell_item(kind)
        found = Pf2e::SpellItems.for_sale(enactor, kind, self.item_name, rank)

        return if Pf2e::CharState.emit_error!(client, found)

        name, info = found.state
        category = Pf2e::SpellItems.table[kind]['category']
        many = self.quantity || 1

        if many > 1 && !Pf2egear::Inventory.stackable?(category)
          client.emit_ooc t('pf2egear.quantity_one_only')
          many = 1
        end

        cost = info['price'] * many

        return client.emit_failure(t('pf2egear.not_enough_you', :item => 'money to buy that')) if cost > enactor.pf2_money.to_i

        before = Pf2egear::Bulk.standing(enactor)

        Pf2egear.create_item(enactor, category, name, many, info)
        Pf2egear.pay_player(enactor, -cost, 'Item Vendor', "Purchase #{name}")

        client.emit_success t('pf2egear.item_bought_ok', :item => name, :cost => Pf2egear.display_money(cost), :quantity => many)

        warning = Pf2egear::Bulk.warning(enactor, before)
        client.emit_ooc warning if warning
      end

    end
  end
end
