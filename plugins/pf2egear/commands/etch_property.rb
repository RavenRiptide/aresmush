module AresMUSH
  module Pf2egear
    class PF2EtchPropertyCmd
      include CommandHandler

      attr_accessor :target, :category, :item_index, :rune_name

      def parse_args
          if (args = cmd.args.match(/([^\s=]+)=(\w+)\/(\d+)\/(.*)/))
            self.target = args[1]
            self.category = args[2]
            @item_index = args[3].to_i
            self.rune_name = args[4]
          else
            @unreadable = true
          end
      end

      # Checks run in the order of their names, so staff are asked for first and the arguments second.
      def check_admin
        t('pf2egear.rune_no_admin') unless enactor.is_admin?
      end

      def check_args
        t('pf2egear.rune_property_cmd_fail') if @unreadable
      end

      def check_character_exists
        if !(@char = Character.find_one_by_name(self.target))
          return t('pf2egear.target_not_found', :name => self.target)
        end
      end
      
      def check_item_exists
        found = Pf2egear::Inventory.item(@char, category, @item_index)

        return t(found.key) if found.err?

        @item = found.state

        nil
      end

      # A property rune is a toggle: one the item holds comes off, and any other goes on if it fits
      # (`RuneFit`, the check the vendor makes too). Taking one off is always allowed, even a rune the
      # catalogue no longer has, which is what lets an item be put right.
      def handle
        held = RuneFit.held(@item, self.rune_name)

        return take_off(held) if held

        fit = RuneFit.property(@item, self.category, self.rune_name)

        return if Pf2e::CharState.emit_error!(client, fit)

        rune, replaces = fit.state['rune'], fit.state['replaces']
        write((held_runes - [ replaces ].compact + [ rune ]).sort)

        key = replaces ? 'pf2egear.rune_property_replaced' : 'pf2egear.rune_property_set'
        client.emit_success t(key, :rune_name => rune, :operation => 'set', :replaced => replaces,
                                   :char => @char.name, :item_name => item_name)
      end

      def take_off(held)
        write(held_runes - [ held ])
        client.emit_success t('pf2egear.rune_property_set', :rune_name => held, :operation => 'unset',
                                                            :char => @char.name, :item_name => item_name)
      end

      def held_runes
        Pf2egear.property_list(@item)
      end

      # Writes the list in the item's shape, putting right one that holds it bare.
      def write(list)
        runes = @item.runes || {}
        property = runes['property'].is_a?(Hash) ? runes['property'] : {}
        runes['property'] = property.merge('list' => list)
        @item.update(:runes => runes)
      end

      def item_name
        @item.nickname || @item.name
      end
    end
  end
end
