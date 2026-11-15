module AresMUSH
  module Pf2egear

    # Staff creating an item and giving it to a character, as `item/give` does: the item a commission
    # crafting request made, or a GM's loot.
    #
    # Under commission crafting, the recipient pays the item's market price and can't receive an item above
    # their own level. The crafter's feat and formula are staff's to check from the request, because the
    # crafter is usually someone else. So a gift charges the catalogue price and checks the recipient's
    # level unless staff say otherwise: `force` skips the level check, and `free` skips the level check and
    # the charge.
    module ItemGiving

      # What is about to be given: `{ 'category', 'name', 'info', 'deity', 'material', 'cost' }`, or an Err
      # saying why it can't be. `extra` is what was typed after the item's name: the deity for an item made for
      # one, or a precious material and grade.
      def self.prepare(char, typed_category, typed_name, extra = [], charge: true, check_level: true)
        return Pf2e::Err.new(:not_approved, 'pf2egear.give_not_approved', 'char' => char.name) unless char.is_approved?

        category = Inventory.shop_category(typed_category)

        return Pf2e::Err.new(:bad_category, 'pf2egear.bad_shop_category', 'category' => typed_category, 'cmd' => 'item/give',
                             'categories' => Inventory.shop_category_names.join(', ')) unless category

        found = entry(category, typed_name)

        return found if found.err?

        name, info = found.state

        return Pf2e::Err.new(:made_only, 'pf2egear.give_made_only', 'item' => name) if info['made_only']

        extra = Array(extra).map(&:to_s).map(&:strip).reject(&:empty?)
        deity = nil
        material = nil

        if Pf2e::ItemChoices.made_for_deity?(info)
          named = Pf2e::ItemChoices.deity_named(name, extra.first)

          return named if named.err?

          deity = named.state
        elsif extra.any?
          return Pf2e::Err.new(:no_deity, 'pf2egear.give_no_deity', 'item' => name, 'extra' => extra.first) unless Materials.named(extra.first)

          made = Materials.prepare(category, name, info, extra[0], extra[1])

          return made if made.err?

          info = made.state['info']
          material = made.state['material']
        end

        level = info['level'].to_i
        shown = material ? Materials.label(name, material) : name

        return Pf2e::Err.new(:too_high, 'pf2egear.give_too_high', 'item' => shown, 'level' => level, 'char' => char.name,
                             'char_level' => char.pf2_level.to_i) if check_level && level > char.pf2_level.to_i

        cost = charge ? info['price'].to_i : 0

        return Pf2e::Err.new(:cant_afford, 'pf2egear.give_cant_afford', 'char' => char.name, 'item' => shown,
                             'cost' => Pf2egear.display_money(cost)) if cost > char.pf2_money.to_i

        Pf2e::Ok.new(:state => { 'category' => category, 'name' => name, 'info' => info, 'deity' => deity,
                                 'material' => material, 'cost' => cost })
      end

      # A catalogue entry by its exact name, or by the start of exactly one name, ignoring case.
      def self.entry(category, typed)
        list = (Global.read_config(Inventory.config(category)) || {}).select { |_name, info| info.is_a?(Hash) }
        wanted = typed.to_s.strip.downcase

        exact = list.find { |name, _info| name.downcase == wanted }

        return Pf2e::Ok.new(:state => exact) if exact

        partial = list.select { |name, _info| name.downcase.start_with?(wanted) }

        return Pf2e::Ok.new(:state => partial.first) if partial.size == 1
        return Pf2e::Err.new(:ambiguous, 'pf2egear.give_ambiguous', 'item' => typed,
                             'matches' => partial.keys.sort.first(10).join(', ')) if partial.size > 1

        Pf2e::Err.new(:no_item, 'pf2egear.give_no_item', 'item' => typed, 'category' => category)
      end

      # Gives it: the item made on their sheet, the deity it was made for, and the price taken.
      def self.give!(char, prepared, by:)
        item = Pf2egear.create_item(char, prepared['category'], prepared['name'], 1, prepared['info'])
        item.update(:deity => prepared['deity']) if prepared['deity'] && item.respond_to?(:deity)
        item.update(:material => prepared['material']) if prepared['material'] && item.respond_to?(:material)

        if prepared['cost'].positive?
          Pf2egear.pay_player(char, -prepared['cost'], by, "Item from staff: #{display_name(prepared)}")
        end

        item
      end

      def self.display_name(prepared)
        return Materials.label(prepared['name'], prepared['material']) if prepared['material']

        prepared['deity'] ? "#{prepared['name']} (#{prepared['deity']})" : prepared['name']
      end
    end
  end
end
