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
        kind = Pf2e::SpellItems.kind(self.category)

        return browse_spell_items(kind) if kind

        list_key = "pf2e_" + category

        # Valid category of items?
        list = Global.read_config(list_key)

        if !list
          client.emit_failure t('pf2egear.bad_category')
          return
        end

        # The list shows what the character can buy: items of their level or lower, common or ones they
        # have access to, and not something only a class feature makes, such as a versatile vial.
        charlevel = enactor.pf2_level
        access = Pf2e::ItemAccess.of(enactor)
        available_items = list.select do |k,v|
          v['level'] <= charlevel && !v['made_only'] && Pf2e::ItemAccess.allows?(access, self.category, k, v)
        end

        template = Pf2eBrowseGearTemplate.new(enactor, self.category, available_items.sort.to_h)

        # Every row asks whether the character is proficient, which reads their effects and feats.
        # Holding the sheet reads them once for the list rather than once per item.
        client.emit Pf2e::SheetReads.holding(enactor) { template.render }

      end

      # Scrolls and wands hold any spell, so they aren't listed one by one: the table of what each rank costs,
      # and how to buy one.
      def browse_spell_items(kind)
        row = Pf2e::SpellItems.table[kind]
        lines = (row['ranks'] || {}).sort_by { |rank, _at| rank.to_i }.map do |rank, at|
          t('pf2e.spell_item_browse_line', :rank => rank, :level => at['level'], :price => Pf2egear.display_money(at['price']))
        end

        title = t('pf2e.spell_item_browse_title', :kind => kind.capitalize)
        footer = [ t('pf2e.spell_item_browse_how', :kind => kind) ]
        footer << t('pf2e.spell_item_browse_specialty') unless (row['specialties'] || {}).empty?

        client.emit BorderedListTemplate.new(lines + [ '' ] + footer, title).render
      end

    end
  end
end
