module AresMUSH
  module Pf2egear
    class PF2UninvestCmd
      include CommandHandler

      attr_accessor :to_uninvest

      def parse_args
        self.to_uninvest = Pf2egear::Inventory.item_list(cmd.args)
      end

      def required_args
        [ self.to_uninvest ]
      end

      def handle

        ### VALIDATION SECTION ###

        valid_cats = Pf2egear::Inventory.categories.select { |c| Pf2egear::Inventory.investable?(c) }

        # Check for correct format, naming the first item that isn't a category and a number.

        unreadable = self.to_uninvest.find { |item| !Pf2egear::Inventory.investable_ref(item) }

        if unreadable
          client.emit_failure t('pf2egear.bad_format', :cmd => cmd.root_plus_switch, :item => unreadable,
                                :categories => valid_cats.map { |c| Pf2egear::Inventory.canonical(c) }.uniq.join(', '))
          return
        end

        # Assemble list of object ID's to be uninvested.

        uninvest_list = []

        self.to_uninvest.each do |item|

          category, num = Pf2egear::Inventory.investable_ref(item)

          found = Pf2egear::Inventory.item(enactor, category, num)

          next if Pf2e::CharState.emit_error!(client, found)

          found.state.update(:invest_on_refresh => false, :invested => false)

          uninvest_list << found.state.name

        end


        client.emit_success t('pf2egear.items_uninvested_ok', :count => uninvest_list.size)

      end

    end
  end
end
