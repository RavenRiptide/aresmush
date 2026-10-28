module AresMUSH
  module Pf2egear
    class PF2BrowseGearCmd
      include CommandHandler

      attr_accessor :category

      def parse_args
        self.category = downcase_arg(cmd.args)
      end

      def required_args
        [ self.category ]
      end

      def handle

        list_key = "pf2e_" + category

        # Valid category of items?
        list = Global.read_config(list_key)

        if !list
          client.emit_failure t('pf2egear.bad_category')
          return
        end

        # The list of items in that category gets filtered by character level.

        charlevel = enactor.pf2_level
        available_items = list.select { |k,v| v['level'] <= charlevel }

        template = Pf2eBrowseGearTemplate.new(enactor, self.category, available_items.sort.to_h)

        # Every row asks whether the character is proficient, which reads their effects and feats.
        # Holding the sheet reads them once for the list rather than once per item.
        client.emit Pf2e::SheetReads.holding(enactor) { template.render }

      end

    end
  end
end
