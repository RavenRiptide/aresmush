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

        # What counts toward the limit; an aeon wyrd's master leaves one aeon stone out (Aeon Stone Reservoir).
        counted = already_invested.dup
        counter = Pf2e::Familiar.invest_count(enactor, counted)

        self.to_invest.each do |item|

          category, num = Pf2egear::Inventory.investable_ref(item)

          found = Pf2egear::Inventory.item(enactor, category, num)

          next if Pf2e::CharState.emit_error!(client, found)

          item_id = found.state

          if Pf2e.has_trait?(item_id.traits, 'invested')

            # An item that asks a question when it's invested is answered here, or not invested at all.
            info = Pf2egear.catalogue_entry(category, item_id) || {}
            how = "#{cmd.root_plus_switch} #{Pf2egear::Inventory.canonical(category)}/#{num}"
            held = item_id.respond_to?(:answers) ? item_id.answers : []
            answered = Pf2e::ItemChoices.for_investing(item_id.name, info, held,
                                                      Pf2egear::Inventory.invest_answer(item), how: how)

            next if Pf2e::CharState.emit_error!(client, answered)

            # One apex item at a time.
            next if Pf2e::CharState.emit_error!(client, Pf2e::Apex.refusal(enactor, item_id))

            # Invested now as well as at each day's preparations, so the sheet has it at once. One set
            # for the day already is counted in the limit; it only wants investing.
            if item_id.invest_on_refresh
              if item_id.invested
                client.emit_failure t('pf2egear.already_set_for_investment')
                return
              end
            else
              counted << item_id
              counter = Pf2e::Familiar.invest_count(enactor, counted)

              if counter > max_investable
                client.emit_failure t('pf2egear.too_many_invested', :max => max_investable)
                return
              end
            end

            item_id.update(invest_on_refresh: true, invested: true)
            Pf2e::Apex.invested!(enactor, item_id)
            item_id.update(answers: answered.state) if item_id.respond_to?(:answers) && answered.state != held

          else
            client.emit_ooc t('pf2egear.not_investible_item', :item => Pf2egear.get_item_name(item_id))
          end

          client.emit_success t('pf2egear.items_invested_ok', :count => counter)


        end


      end

    end
  end
end
