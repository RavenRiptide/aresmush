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
        return browse_runes if %w{rune runes}.include?(self.category)

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

      # Runes go on an item rather than being one, so they get a list of their own: every grade of each
      # fundamental rune, then the property runes the character could buy, with what each is etched onto.
      def browse_runes
        client.emit BorderedListTemplate.new(rune_lines, t('pf2egear.rune_browse_title')).render
      end

      def rune_lines
        lines = [ t('pf2egear.rune_browse_fundamental') ]

        RuneVendor.fundamentals.each_value do |runes|
          runes.each_value do |grades|
            grades.sort_by { |grade, _row| grade.to_i }.each { |_grade, row| lines << rune_line(row['name'], row) }
          end
        end

        access = Pf2e::ItemAccess.of(enactor)
        buyable = Pf2egear.runes.select do |name, info|
          info['level'].to_i <= enactor.pf2_level.to_i && Pf2e::ItemAccess.allows?(access, 'runes', name, info)
        end

        { 'weapon' => 'weapons', 'armor' => 'armor' }.each_pair do |kind, shown|
          lines << ''
          lines << t('pf2egear.rune_browse_property', :kind => shown)

          buyable.select { |_name, info| info['kind'] == kind }.sort_by { |name, info| [ info['level'].to_i, name ] }
                 .each do |name, info|
                   lines << rune_line(name, info)
                   # A rune for any weapon or any armor says nothing more; one for some says which.
                   lines << "    only on #{RuneFit::USAGES.dig(info['usage'].to_s, 1)}" unless %w{weapon armor}.include?(info['usage'])
                 end
        end

        lines + [ '', t('pf2egear.rune_browse_how') ]
      end

      def rune_line(name, info)
        "#{name.to_s.ljust(30)} #{"level #{info['level']}".ljust(10)} #{Pf2egear.display_money(info['price'].to_i).strip}"
      end

    end
  end
end
