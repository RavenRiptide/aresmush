module AresMUSH
  module Pf2emagic

    # Which of a caster's slots at a rank are restricted, and to what.
    #
    # PF2e restricts slots in several unrelated ways, and the list keeps growing. A Wizard's
    # curriculum slot takes a spell from the school's list; a Cleric's divine font slot takes only
    # heal or harm. Each kind is a row here, so adding one is a new row, and `Pf2emagic::SlotFit`
    # places spells without knowing what any of them mean.
    module Restrictions

      CANTRIP = 'cantrip'.freeze

      # `count` is how many slots this restriction grants at the rank; `eligible` is what may go in
      # them. Both take (char, charclass, level). `eligible` is called only when `count` is
      # positive, so it may assume the restriction applies.
      KINDS = [
        {
          'name' => 'curriculum',
          # A curriculum's slots are granted by the specialty's stat block, so the count is read
          # from what advancement recorded rather than derived.
          'count' => lambda { |char, charclass, level| Restrictions.stat_block_count(char, charclass, 'curriculum', level) },
          'eligible' => lambda { |char, charclass, level| Pf2emagic.curriculum_spells(char, charclass, level) }
        },
        {
          'name' => 'divine font',
          # Four extra slots at the cleric's highest slot rank, five from 5th level, six from 15th.
          # No other rank gets any, and cantrips never do. The 10th rank is not counted as the
          # highest: Miraculous Spell's single 10th-rank slot is its own thing, so the font stays
          # at 9th.
          'count' => lambda { |char, charclass, level|
            next 0 unless charclass.to_s.casecmp?('Cleric')
            next 0 if level.to_s.casecmp?(CANTRIP)
            next 0 if char.magic&.divine_font.blank?
            next 0 unless level.to_s == Restrictions.highest_font_rank(char, charclass).to_s

            Restrictions.font_slots(char.pf2_level)
          },
          'eligible' => lambda { |char, _charclass, _level|
            font = char.magic&.divine_font
            font.blank? ? [] : [ Pf2e.pretty_string(font) ]
          }
        }
      ].freeze

      # { name => { 'count' => n, 'eligible' => [ spells ] } } for one rank.
      def self.at(char, charclass, level)
        named = KINDS.each_with_object({}) do |kind, found|
          count = kind['count'].call(char, charclass, level).to_i
          next unless count.positive?

          found[kind['name']] = { 'count' => count, 'eligible' => kind['eligible'].call(char, charclass, level) }
        end

        # A restriction no row here knows about still takes its slot away, and accepts nothing. If
        # it accepted anything, the character would gain a free slot with nothing to show it.
        unknown(char, charclass, level).each do |name, count|
          next if named.key?(name)

          Global.logger.error "Unknown restricted slot '#{name}' for #{char.name}; its slot accepts nothing."
          named[name] = { 'count' => count, 'eligible' => [] }
        end

        named
      end

      # What may go in one named restriction's slots, whether or not it grants any at this rank.
      # Callers that display a restriction's list want this; callers that enforce it want `at`.
      def self.eligible(char, charclass, name, level)
        kind = KINDS.find { |k| k['name'].casecmp?(name.to_s) }

        unless kind
          Global.logger.error "Unknown restricted slot '#{name}' for #{char.name}; its slot accepts nothing."
          return []
        end

        Array(kind['eligible'].call(char, charclass, level)).compact
      end

      # { name => count }, for callers that only need to size the pools.
      def self.counts_at(char, charclass, level)
        at(char, charclass, level).transform_values { |r| r['count'] }
      end

      def self.stat_block_count(char, charclass, name, level)
        for_class = (char.magic&.restricted_slots || {})[charclass]
        return 0 unless for_class.is_a?(Hash)

        key = for_class.keys.find { |k| k.to_s.casecmp?(name.to_s) }

        key ? Pf2emagic.restricted_count_at_rank(for_class[key], level) : 0
      end

      def self.open_slots(char, charclass, level)
        Entries.slots(char.magic, charclass)[level].to_i
      end

      # The highest rank from 1 to 9 the class has slots at, or nil when it has none.
      def self.highest_font_rank(char, charclass)
        (1..9).reverse_each.find { |rank| open_slots(char, charclass, rank.to_s).positive? }
      end

      def self.font_slots(char_level)
        char_level = char_level.to_i
        return 6 if char_level >= 15
        return 5 if char_level >= 5

        4
      end

      def self.unknown(char, charclass, level)
        known = KINDS.map { |k| k['name'].downcase }
        for_class = (char.magic&.restricted_slots || {})[charclass]
        return {} unless for_class.is_a?(Hash)

        for_class.each_with_object({}) do |(name, by_rank), found|
          next if known.include?(name.to_s.downcase)

          count = Pf2emagic.restricted_count_at_rank(by_rank, level)
          found[name] = count if count.positive?
        end
      end
    end
  end
end
