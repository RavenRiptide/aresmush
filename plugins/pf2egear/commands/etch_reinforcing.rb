module AresMUSH
  module Pf2egear
    # `etch/reinforcing <character>=shields/<item number>/<grade>`: sets a shield's reinforcing rune, from 0
    # (none) to 6 (supreme). What each grade adds is in `pf2e_fundamental_runes.yml`, read by `ShieldRunes`.
    class PF2EtchReinforcingCmd
      include CommandHandler

      attr_accessor :target, :category, :item_index, :grade

      def parse_args
        if (args = cmd.args.to_s.match(/\A([^\s=]+)=(\w+)\/(\d+)\/(\d+)\z/))
          self.target = args[1]
          self.category = args[2]
          @item_index = args[3].to_i
          self.grade = args[4].to_i
        else
          @unreadable = true
        end
      end

      # Checks run in the order of their names, so staff are asked for first and the arguments second.
      def check_admin
        t('pf2egear.rune_no_admin') unless enactor.is_admin?
      end

      def check_args
        t('pf2egear.rune_reinforcing_cmd_fail') if @unreadable
      end

      def check_category
        t('pf2egear.rune_reinforcing_shields_only') unless Pf2egear::Inventory.canonical(self.category).to_s == 'shields'
      end

      def check_grade
        t('pf2egear.rune_reinforcing_out_of_range') unless ShieldRunes::GRADES.include?(self.grade)
      end

      def check_character_exists
        return nil if (@char = Character.find_one_by_name(self.target))

        t('pf2egear.target_not_found', :name => self.target)
      end

      def check_item_exists
        found = Pf2egear::Inventory.item(@char, self.category, @item_index)

        return t(found.key) if found.err?

        @item = found.state

        nil
      end

      def handle
        old = ShieldRunes.reinforcing(@item)
        runes = @item.runes || {}
        runes['fundamental'] ||= {}
        runes['fundamental']['reinforcing'] = self.grade
        @item.update(:runes => runes)

        client.emit_success t('pf2egear.rune_potency_set', :rune => 'Reinforcing', :char => @char.name,
                              :item_name => @item.nickname || @item.name, :old_rune_lvl => old, :rune_lvl => self.grade)
      end
    end
  end
end
