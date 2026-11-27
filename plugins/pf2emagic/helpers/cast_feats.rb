module AresMUSH
  module Pf2emagic

    # Feats that change what a cast may spend, read as the spell is cast. Each is a key the feat's data
    # carries, so no code names a feat:
    #
    #   overflow_casts:          # cast after the rank's slots run out (Studious Capacity, Greater Vital
    #     per_day: 2             # Evolution, Divine Effusion), so many times a day,
    #     not_top: true          # never at the highest rank the class casts,
    #     distinct_ranks: true   # each at a different rank
    #
    #   battle_form_casts:       # a common polymorph battle form spell cast from a slot as if it were a
    #     per_day: 1             # signature spell (Greater Physical Evolution)
    #
    #   font_trade:              # a spell from the divine font traded for another at its rank
    #     from: Heal             # (Restorative Channel)
    #     spells: [ Sound Body ]
    #
    # A class feat speaks only for its own class. The day's uses are kept in spells_today, which a rest
    # rebuilds without them, so every feat starts the day unused.
    module CastFeats

      OVERFLOW = 'overflow casts'.freeze
      BATTLE_FORMS = 'battle form casts'.freeze

      RARITY_TRAITS = %w{uncommon rare unique}.freeze

      # feat => its block, for the character's feats carrying the key, for this class.
      def self.held(char, key, charclass)
        Pf2e::DraftSheet.of(char).feat_names.map(&:to_s).uniq(&:downcase).each_with_object({}) do |name, out|
          found = Pf2e.get_feat_details(name)
          next unless found.is_a?(Array) && found[1][key].is_a?(Hash)
          next unless BonusSlots.for_class?(found[1], charclass)

          out[found[0]] = found[1][key]
        end
      end

      def self.today(magic, store)
        (magic.spells_today || {})[store] || {}
      end

      def self.record(magic, store, feat, value)
        spells_today = magic.spells_today || {}
        uses = spells_today[store] || {}

        uses[feat] = value
        spells_today[store] = uses

        magic.update(:spells_today => spells_today)
      end

      # [ feat, uses left, [ what limits it ] ] for each of a class's feats that casts past its slots or
      # casts a battle form, for the magic display. The limits are the words `overflow`, `not_top`,
      # `used:<rank>,<rank>` (for distinct_ranks) and `battle_form`, for the display to phrase.
      def self.summary(char, charclass)
        overflow_today = today(char.magic, OVERFLOW)
        forms_today = today(char.magic, BATTLE_FORMS)

        overflow = held(char, 'overflow_casts', charclass).map do |feat, block|
          used = Array(overflow_today[feat]).map(&:to_s)
          limits = [ 'overflow' ]
          limits << 'not_top' if block['not_top']
          limits << "used:#{used.join(',')}" if block['distinct_ranks'] && used.any?

          [ feat, [ (block['per_day'] || 1).to_i - used.size, 0 ].max, limits ]
        end

        forms = held(char, 'battle_form_casts', charclass).map do |feat, block|
          [ feat, [ (block['per_day'] || 1).to_i - forms_today[feat].to_i, 0 ].max, [ 'battle_form' ] ]
        end

        overflow + forms
      end

      # ------------------------------------------------------------------------------
      # Casting after the rank's slots run out
      # ------------------------------------------------------------------------------

      # The first feat that may cast a spell at this rank today, or nil. `top` is the highest rank the
      # class casts.
      def self.overflow_feat(char, charclass, rank, top)
        used_today = today(char.magic, OVERFLOW)

        held(char, 'overflow_casts', charclass).find do |feat, block|
          used = Array(used_today[feat]).map(&:to_s)

          used.size < (block['per_day'] || 1).to_i &&
            !(block['not_top'] && rank.to_i >= top.to_i) &&
            !(block['distinct_ranks'] && used.include?(rank.to_s))
        end&.first
      end

      def self.spend_overflow(magic, feat, rank)
        record(magic, OVERFLOW, feat, Array(today(magic, OVERFLOW)[feat]) + [ rank.to_s ])
      end

      # ------------------------------------------------------------------------------
      # A battle form cast as a signature spell
      # ------------------------------------------------------------------------------

      # A polymorph spell whose text grants a battle form: Animal Form, Dragon Form and the rest.
      def self.battle_form?(spell)
        found = Pf2emagic.get_spell_details(spell.to_s)
        return false unless found.is_a?(Array)

        details = found[1]

        Array(details['traits']).include?('polymorph') && details.to_s.downcase.include?('battle form')
      end

      def self.common?(spell)
        found = Pf2emagic.get_spell_details(spell.to_s)

        found.is_a?(Array) && (Array(found[1]['traits']) & RARITY_TRAITS).empty?
      end

      # The feat that lets this spell be cast as a signature spell today, or nil.
      def self.battle_form_feat(char, charclass, spell)
        return nil unless battle_form?(spell) && common?(spell)

        used_today = today(char.magic, BATTLE_FORMS)

        held(char, 'battle_form_casts', charclass).find do |feat, block|
          used_today[feat].to_i < (block['per_day'] || 1).to_i
        end&.first
      end

      def self.spend_battle_form(magic, feat)
        record(magic, BATTLE_FORMS, feat, today(magic, BATTLE_FORMS)[feat].to_i + 1)
      end

      # ------------------------------------------------------------------------------
      # A font spell traded for another
      # ------------------------------------------------------------------------------

      # { 'feat', 'from', 'rank' } for a spell the character may cast by giving up a font spell they
      # still have today, or nil. The trade is at the font's rank, and the spell is heightened to it.
      # A font spell is told from one prepared in an ordinary slot only by its rank, so any copy of the
      # font's spell at that rank is the one given up.
      def self.font_trade(char, charclass, spell, level = nil)
        rank = Restrictions.highest_font_rank(char, charclass)
        return nil unless rank
        return nil if level && level.to_i != rank

        list = Array(((char.magic.spells_today || {})[charclass] || {})[rank.to_s])

        held(char, 'font_trade', charclass).each do |feat, block|
          next unless Array(block['spells']).any? { |one| one.to_s.casecmp?(spell.to_s) }

          from = list.find { |one| one.to_s.casecmp?(block['from'].to_s) }

          return { 'feat' => feat, 'from' => from, 'rank' => rank.to_s } if from
        end

        nil
      end

      # Gives up the font spell the trade named.
      def self.spend_font_trade(magic, charclass, trade)
        spells_today = magic.spells_today
        by_rank = spells_today[charclass]
        list = Array(by_rank[trade['rank']]).dup

        list.delete_at(list.index(trade['from']))
        by_rank[trade['rank']] = list
        spells_today[charclass] = by_rank

        magic.update(:spells_today => spells_today)
      end
    end
  end
end
