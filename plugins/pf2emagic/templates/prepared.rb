module AresMUSH
  module Pf2emagic
    class PF2DisplayPreparedSpellsTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :spell_list, :client

      def initialize(char, spell_list, client = nil)
        @char = char
        @spell_list = spell_list
        @client = client

        super File.dirname(__FILE__) + "/prepared.erb"

      end

      def title
        t('pf2emagic.prepared_spells_title', :name => @char.name)
      end

      def textline(title)
        @client && @client.screen_reader ? title : line_with_text(title)
      end

      def spells_per_day
        Pf2emagic::Entries.slots_by_source(@char.magic)
      end

      def help_text
        t('pf2emagic.prepared_spells_help')
      end

      def spells
        @spell_list.map do |charclass, by_level|
          sorted = Pf2emagic.sort_level_spell_list(with_open_ranks(charclass, by_level))

          lines = sorted.map do |level, spell_names|
            heading = "#{item_color}#{Pf2emagic.rank_label(level)} (#{slot_summary(charclass, level)})%xn"

            "#{heading}%r#{rank_body(charclass, level, Array(spell_names))}"
          end

          format_class_spell_list(charclass, lines + slot_feat_lines(charclass))
        end
      end

      # The spells at one rank. A rank with restricted slots (a Cleric's divine font, a Wizard's
      # curriculum) shows each kind of slot on its own line with how many are filled, so the
      # caster can see which are still free. A set that no longer fits its slots, as after the
      # font changes, is listed as one line rather than guessed at.
      def rank_body(charclass, level, names)
        restrictions = Pf2emagic::Restrictions.at(@char, charclass, level)
        return spell_line(names) if restrictions.empty?

        pools = Pf2emagic::SlotFit.from_slots(base_slots(charclass, level), restrictions)
        # Two spells in one slot (Split Slot) take an open slot; they are listed with their feat.
        held = Pf2emagic::SlotFeats.placeholders(@char.magic, charclass, level)
        placed = Pf2emagic::SlotFit.assign(pools, names + held)
        return spell_line(names) unless placed

        pools.each_with_index.map do |pool, index|
          label = pool['name'] ? pool['name'].to_s.capitalize : t('pf2emagic.prepared_any_slot')
          spells = placed[index].reject { |spell| spell == Pf2emagic::SlotFeats::PLACEHOLDER }

          spell_line(spells, "#{label} (#{placed[index].size} of #{pool['capacity']}): ")
        end.join("%r")
      end

      def spell_line(names, label = '')
        listed = names.empty? ? t('pf2emagic.prepared_rank_empty') : names.sort.join(", ")

        "%b%b%b%b#{label}#{listed}"
      end

      # The prepared spells by rank, plus every rank the class has slots at and nothing prepared in,
      # so the screen shows how many slots there are before any are filled.
      def with_open_ranks(charclass, by_level)
        for_class = spells_per_day[charclass]
        return by_level unless for_class.is_a?(Hash)

        open = for_class.select do |rank, count|
          count.to_i.positive? && by_level.keys.none? { |held| held.to_s.casecmp?(rank.to_s) }
        end

        by_level.merge(open.keys.to_h { |rank| [ rank.to_s, [] ] })
      end

      # Two spells in one slot (Split Slot, Spell Combination), and Spell Mastery's spells.
      def slot_feat_lines(charclass)
        magic = @char.magic

        pairs = Pf2emagic::SlotFeats.pairs(magic, charclass).map do |pair|
          joined = pair['cast'].to_s == 'both' ? pair['spells'].join(' + ') : pair['spells'].join(' or ')
          at = pair['cast_rank'].to_s == pair['rank'].to_s ? '' : ", cast at rank #{pair['cast_rank']}"

          "#{item_color}#{Pf2emagic.rank_label(pair['rank'])} (#{pair['feat']}#{at})%xn%r%b%b%b%b#{joined}"
        end

        mastered = Pf2emagic::SlotFeats.mastered(magic, charclass)
        unless mastered.empty?
          listed = mastered.sort_by { |rank, _spell| rank.to_i }.map { |rank, spell| "#{spell} (#{rank})" }.join(", ")
          pairs << "#{item_color}Mastered, prepared at every rest%xn%r%b%b%b%b#{listed}"
        end

        pairs
      end

      def slot_summary(charclass, level)
        parts = [ count_with_noun(base_slots(charclass, level), 'slot') ]

        Pf2emagic.restricted_slots_at(@char, charclass, level).each_pair do |restriction, count|
          parts << count_with_noun(count, "#{restriction} slot") if count.to_i.positive?
        end

        parts.join(" + ")
      end

      def base_slots(charclass, level)
        for_class = spells_per_day[charclass]
        return 0 unless for_class.is_a?(Hash)

        key = for_class.keys.find { |k| k.to_s.casecmp?(level.to_s) }
        key ? for_class[key].to_i : 0
      end

      def count_with_noun(count, noun)
        "#{count.to_i} #{noun}#{'s' unless count.to_i == 1}"
      end

      # One rank to a line pair with no blank line between, so a caster with many ranks stays short.
      def format_class_spell_list(charclass, lines)
        "#{textline("#{charclass} Spells")}%r%r#{lines.join("%r")}%r"
      end

    end
  end
end
