module AresMUSH
  module Pf2egear
    class PF2InvestCmd
      include CommandHandler

      attr_accessor :to_invest

      def parse_args
        self.to_invest = Pf2egear::Inventory.item_list(cmd.args)
      end

      def required_args
        [ self.to_invest ]
      end

      def handle

        ### VALIDATION SECTION ###

        valid_cats = Pf2egear::Inventory.categories.select { |c| Pf2egear::Inventory.investable?(c) }

        # Check for correct format, naming the first item that isn't a category and a number.

        unreadable = self.to_invest.find { |item| !Pf2egear::Inventory.investable_ref(item) }

        if unreadable
          client.emit_failure t('pf2egear.bad_format', :cmd => cmd.root_plus_switch, :item => unreadable,
                                :categories => valid_cats.map { |c| Pf2egear::Inventory.canonical(c) }.uniq.join(', '))
          return
        end

        max_investable = Pf2e.has_feat?(enactor, 'Incredible Investiture') ? 12 : 10

        # Every item PF2e lets a character invest, which Inventory says rather than this command.
        investable_list = valid_cats.map { |c| Pf2egear::Inventory.canonical(c) }.uniq
                                    .flat_map { |c| Pf2egear::Inventory.held(enactor, c) }

        already_invested = investable_list.select { |item| item.invest_on_refresh }

        counter = already_invested.size

        self.to_invest.each do |item|

          category, num = Pf2egear::Inventory.investable_ref(item)

          found = Pf2egear::Inventory.item(enactor, category, num)

          next if Pf2e::CharState.emit_error!(client, found)

          item_id = found.state

          if Pf2e.has_trait?(item_id.traits, 'invested')

            # Invested now as well as at each day's preparations, so the sheet has it at once. One set
            # for the day already is counted in the limit; it only wants investing.
            if item_id.invest_on_refresh
              if item_id.invested
                client.emit_failure t('pf2egear.already_set_for_investment')
                return
              end
            else
              counter = counter + 1

              if counter > max_investable
                client.emit_failure t('pf2egear.too_many_invested', :max => max_investable)
                return
              end
            end

            item_id.update(invest_on_refresh: true, invested: true)

          else
            client.emit_ooc t('pf2egear.not_investible_item', :item => Pf2egear.get_item_name(item_id))
          end

          client.emit_success t('pf2egear.items_invested_ok', :count => counter)


        end


      end

    end
  end
end
