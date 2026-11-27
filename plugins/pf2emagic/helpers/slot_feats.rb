module AresMUSH
  module Pf2emagic

    # Feats that change what a prepared caster's slots hold, each through a prepare switch its data
    # names, so no code names a feat:
    #
    #   prepared_slot:               # two spells in one slot
    #     switch: splitslot
    #     cast: either               # cast one and the other is lost (Split Slot), or
    #                                # both at once (Spell Combination)
    #     count: 1                   # how many such slots in all, or
    #     per_rank: 1                # how many at each rank
    #     below_top: 1               # at least this many ranks below the highest
    #     min_rank: 3
    #     components_below: 2        # both are cast this many ranks below the slot
    #
    #   prepared_slot:               # one spell prepared in a higher slot, cast at its own rank
    #     switch: formretention      # and lasting longer (Form Retention)
    #     cast: retained
    #     components_below: 2
    #     spells: battle_form        # only a polymorph spell granting a battle form for 1 minute
    #     lasts: { unit: minutes, value: 10 }
    #
    #   mastered_spells:             # spells prepared at every rest in slots of their own
    #     switch: spellmastery       # (Spell Mastery)
    #     count: 4
    #     max_rank: 9
    #
    # A pair is kept in magic.slot_pairs and takes one of the rank's ordinary slots. Mastered
    # spells are kept in magic.mastered_spells and added to the day's spells at a rest.
    module SlotFeats

      KINDS = %w{prepared_slot mastered_spells}.freeze

      # What a pair holds in the ordinary slot count, since it is not one spell.
      PLACEHOLDER = '(two spells in one slot)'.freeze

      # Where a rest copies the pairs to, beside the class-keyed lists.
      TODAY = 'slot pairs'.freeze

      # Every switch any feat declares, for routing a command before a character is looked at.
      def self.switch?(switch)
        (Global.read_config('pf2e_feats') || {}).any? do |_name, details|
          next false unless details.is_a?(Hash)

          KINDS.any? { |kind| details[kind].is_a?(Hash) && details[kind]['switch'].to_s.casecmp?(switch.to_s) }
        end
      end

      # { 'feat', 'class', 'kind', 'block' } for the character's feat declaring a switch, or nil.
      def self.for_switch(char, switch)
        Pf2e::DraftSheet.of(char).feat_names.map(&:to_s).uniq(&:downcase).each do |name|
          found = Pf2e.get_feat_details(name)
          next unless found.is_a?(Array)

          KINDS.each do |kind|
            block = found[1][kind]
            next unless block.is_a?(Hash) && block['switch'].to_s.casecmp?(switch.to_s)

            return { 'feat' => found[0], 'class' => Array(found[1]['assoc_charclass']).first.to_s,
                     'kind' => kind, 'block' => block }
          end
        end

        nil
      end

      def self.top_rank(char, charclass)
        Entries.slots(char.magic, charclass).keys.map(&:to_s).reject { |r| r.casecmp?('cantrip') }.map(&:to_i).max.to_i
      end

      def self.pairs(magic, charclass)
        Array((magic.slot_pairs || {})[charclass])
      end

      # One placeholder per pair prepared at a rank, for counting it against the rank's slots.
      def self.placeholders(magic, charclass, rank)
        pairs(magic, charclass).select { |pair| pair['rank'].to_s == rank.to_s }.map { |_pair| PLACEHOLDER }
      end

      def self.err(key, args = {})
        Pf2e::Err.new(key.to_sym, "pf2emagic.#{key}", args)
      end

      # ------------------------------------------------------------------------------
      # Two spells in one slot
      # ------------------------------------------------------------------------------

      # Why a pair cannot go at this rank, or nil. Pure: the feat's block, the rank, the highest rank
      # the class casts, and the ranks of the feat's pairs already prepared.
      def self.rank_refusal(block, rank, top, held_ranks)
        return err('slot_pair_bad_rank') unless rank.to_i.positive?
        return err('slot_pair_rank_too_high', 'rank' => top - block['below_top'].to_i) if rank.to_i > top - block['below_top'].to_i
        return err('slot_pair_rank_too_low', 'rank' => block['min_rank']) if block['min_rank'] && rank.to_i < block['min_rank'].to_i

        if block['per_rank']
          return err('slot_pair_rank_full', 'rank' => rank) if held_ranks.count { |r| r.to_s == rank.to_s } >= block['per_rank'].to_i
        elsif block['count']
          return err('slot_pair_all_used', 'count' => block['count']) if held_ranks.size >= block['count'].to_i
        end

        nil
      end

      # The rank the pair's spells are cast at: the slot's, or lower for a combination.
      def self.cast_rank(block, rank)
        rank.to_i - block['components_below'].to_i
      end

      # A slot held open (`cast: open`, Infinite Possibilities) has no spells in it until it is cast.
      def self.open?(block_or_pair)
        block_or_pair['cast'].to_s == 'open'
      end

      # A slot whose two spells are cast together as one (`cast: both`, Spell Combination).
      def self.combined?(block_or_pair)
        block_or_pair['cast'].to_s == 'both'
      end

      # A slot holding one spell cast at a lower rank for longer (`cast: retained`, Form Retention).
      def self.retained?(block_or_pair)
        block_or_pair['cast'].to_s == 'retained'
      end

      # Why a spell may not go in a slot whose block limits its spells, or nil. `battle_form`: a polymorph
      # spell granting a battle form that lasts 1 minute.
      def self.spell_refusal(block, spell)
        return nil unless block['spells'].to_s == 'battle_form'

        found = Pf2emagic.get_spell_details(spell.to_s)
        minute = found.is_a?(Array) && found[1]['duration'].to_s.strip.casecmp?('1 minute')

        CastFeats.battle_form?(spell) && minute ? nil : err('slot_retained_not_battle_form', 'spell' => spell)
      end

      # ------------------------------------------------------------------------------
      # A combination (`cast: both`): two spells cast as one, at one target
      # ------------------------------------------------------------------------------

      # A spell target that is, or can be, a single creature or object: a count that can be one (`1`, `one`,
      # `a`, `up to N`, `1 or N`, `1 to N`, `1 or more`, `any number of`), or one particular creature (`your
      # familiar`, `the triggering creature`, `self`). Matched against the whole target text.
      SINGLE_TARGET = /\A(?:(?:1|one|an?|another|the|your|any number of|up to \w+)\b|self\z)/i.freeze

      # Text that names two things at once, or an area, which no single target can be: `1 ally and 1 enemy`,
      # `you and 1 ally`, `yourself and up to 5 willing creatures`, `all creatures in range`, `10-foot burst`,
      # `1 square mile`. A measure after `and` - `10 feet tall and 5 feet wide` - is still one thing.
      MORE_THAN_ONE = /\b(?:and|plus)\s+(?!(?:up to\s+)?\d+\s*(?:feet|foot|bulk)\b)(?:\d+|one|an?|the|up to|any|either|yourself|you)\b|\ball\b|\b(?:burst|emanation|cone)\b|\A1 (?:cubic foot|square mile)\z/i.freeze

      # Whether a spell's target text allows a single target. A target named with its alternative - `you or
      # 1 ally`, `1 creature, plus any number of additional creatures` - can be one, and is allowed.
      def self.single_target?(target)
        text = target.to_s.strip
        return false if text.empty? || text.casecmp?('varies')

        alternatives = text.split(/,?\s+or\s+/i)
        return true if alternatives.size > 1 && alternatives.any? { |one| single_target?(one) } && !text.match?(/\band\b/i)
        return true if text.match?(/\A1 creature, plus any number\b/i)

        text.match?(SINGLE_TARGET) && !text.match?(MORE_THAN_ONE)
      end

      # How a spell decides whether it has an effect: `attack`, `save fortitude` and the like, or `automatic`.
      # The data does not say whether an attack is ranged or melee, so any two attack spells match.
      def self.resolution(mechanics)
        return 'attack' if mechanics['attack']
        return "save #{mechanics['save']}" if mechanics['save']

        'automatic'
      end

      # Why two spells cannot be combined, or nil. Pure: each is `[ name, mechanics ]`, the mechanics
      # being the spell's `pf2e_spell_mechanics` row, or nil where it has none.
      def self.combination_refusal(first, second)
        [ first, second ].each do |name, mechanics|
          return err('combination_unknown', 'spell' => name) unless mechanics.is_a?(Hash)
          return err('combination_area', 'spell' => name, 'area' => mechanics['area']) if mechanics['area']
          return err('combination_no_target', 'spell' => name) unless mechanics['target']
          return err('combination_many_targets', 'spell' => name, 'target' => mechanics['target']) unless single_target?(mechanics['target'])
        end

        ways = [ first, second ].map { |_name, mechanics| resolution(mechanics) }
        return nil if ways.uniq.size == 1

        err('combination_resolves_differently', 'first' => first[0], 'second' => second[0],
                                                'first_way' => way_worded(ways[0]), 'second_way' => way_worded(ways[1]))
      end

      # `save fortitude` as a player reads it: `a Fortitude save`.
      def self.way_worded(way)
        case way
        when 'attack' then 'a spell attack'
        when 'automatic' then 'no attack or save'
        else "a #{way.sub(/\Asave /, '').capitalize} save"
        end
      end

      # A spell's mechanics row by the name `check_preparable` answered: `[ name, row ]`, the row nil where
      # the catalogue has none.
      def self.mechanics_of(name)
        catalogue = Global.read_config('pf2e_spell_mechanics') || {}
        found = catalogue.find { |key, _| key.casecmp?(name.to_s) }

        found || [ name, nil ]
      end

      # A refusal worded for an open slot, where the pair's wording speaks of two spells.
      OPEN_WORDING = { slot_pair_all_used: 'slot_open_all_used', slot_pair_no_slot: 'slot_open_no_slot',
                       slot_pair_bad_rank: 'slot_open_bad_rank' }.freeze

      def self.worded(refusal, block)
        return refusal unless refusal && open?(block) && OPEN_WORDING[refusal.code]

        err(OPEN_WORDING[refusal.code], refusal.args.merge('switch' => block['switch']))
      end

      def self.prepare_pair(char, found, rank, names)
        magic = char.magic
        block = found['block']
        charclass = found['class']

        if open?(block)
          return err('slot_open_no_spells', 'switch' => block['switch']) unless names.empty?
        elsif retained?(block)
          return err('slot_retained_one_spell', 'switch' => block['switch']) unless names.size == 1
        else
          return err('slot_pair_two_spells') unless names.size == 2
        end

        held = pairs(magic, charclass).select { |pair| pair['feat'] == found['feat'] }.map { |pair| pair['rank'] }
        refusal = worded(rank_refusal(block, rank, top_rank(char, charclass), held), block)
        return refusal if refusal

        at = cast_rank(block, rank)

        checked = names.map do |name|
          result = Pf2emagic.check_preparable(char, charclass, name, at.to_s)
          return Pf2e::Err.new(:not_preparable, 'pf2emagic.slot_pair_spell_refused', 'spell' => name, 'why' => result) if result.is_a?(String)

          refusal = spell_refusal(block, result['name'])
          return refusal if refusal

          result['name']
        end

        return err('slot_pair_same_spell') if checked.size == 2 && checked[0].casecmp?(checked[1])

        if combined?(block)
          refusal = combination_refusal(mechanics_of(checked[0]), mechanics_of(checked[1]))
          return refusal if refusal
        end

        prepared = Array(((magic.spells_prepared || {})[charclass] || {})[rank.to_s])
        taken = prepared + placeholders(magic, charclass, rank) + [ PLACEHOLDER ]

        unless taken.size <= Pf2emagic.max_spells_per_day(char, charclass, rank.to_s) &&
               Pf2emagic.prepared_set_fits?(char, charclass, rank.to_s, taken)
          return worded(err('slot_pair_no_slot', 'rank' => rank), block)
        end

        pair = { 'feat' => found['feat'], 'rank' => rank.to_s, 'spells' => checked,
                 'cast' => block['cast'].to_s, 'cast_rank' => at.to_s }
        pair['lasts'] = block['lasts'] if block['lasts'].is_a?(Hash)

        all = magic.slot_pairs || {}
        all[charclass] = pairs(magic, charclass) + [ pair ]
        magic.update(:slot_pairs => all)

        Pf2e::Ok.new(:state => pair)
      end

      def self.unprepare_pair(char, found, rank)
        magic = char.magic
        charclass = found['class']
        list = pairs(magic, charclass)
        index = list.index { |pair| pair['feat'] == found['feat'] && (rank.blank? || pair['rank'].to_s == rank.to_s) }

        return err('slot_pair_none', 'feat' => found['feat']) unless index

        removed = list.delete_at(index)
        magic.update(:slot_pairs => (magic.slot_pairs || {}).merge(charclass => list))

        Pf2e::Ok.new(:state => removed)
      end

      # The open slot a cast draws on (Infinite Possibilities, Miraculous Possibility): the lowest one
      # whose rank, less `components_below`, the spell can be prepared at, as the class would prepare it -
      # from the spellbook, or from the tradition's list. The spell is cast at that lower rank. A rank
      # asked for may be the slot's or the one it casts at. Removed from the day, with the spell it
      # cast written into it; nil where none takes the spell.
      def self.cast_from_open(char, magic, charclass, spell, rank)
        today = magic.spells_today || {}
        list = Array((today[TODAY] || {})[charclass])

        open = list.each_with_index.select do |pair, _index|
          open?(pair) && (rank.nil? || [ pair['rank'], pair['cast_rank'] ].map(&:to_s).include?(rank.to_s))
        end

        open.sort_by { |pair, _index| pair['rank'].to_i }.each do |pair, index|
          checked = Pf2emagic.check_preparable(char, charclass, spell, pair['cast_rank'].to_s)
          next if checked.is_a?(String)

          list.delete_at(index)
          today[TODAY] = (today[TODAY] || {}).merge(charclass => list)
          magic.update(:spells_today => today)

          return pair.merge('spells' => [ checked['name'] ])
        end

        nil
      end

      # The pair a cast draws on from the day's spells: one holding the spell, at the rank asked
      # for if one was. Removed from the day, since the slot is spent either way.
      def self.cast_from_pair(magic, charclass, spell, rank)
        today = magic.spells_today || {}
        list = Array((today[TODAY] || {})[charclass])
        index = pair_index(list, spell, rank)

        return nil unless index

        pair = list.delete_at(index)
        today[TODAY] = (today[TODAY] || {}).merge(charclass => list)
        magic.update(:spells_today => today)

        pair
      end

      def self.pair_index(list, spell, rank)
        list.index do |pair|
          Array(pair['spells']).any? { |s| s.casecmp?(spell.to_s) } && (rank.nil? || pair['rank'].to_s == rank.to_s)
        end
      end

      # The pair `cast_from_pair` would draw on, left in the day: for asking what a cast will be before the
      # slot is spent.
      def self.pair_holding(magic, charclass, spell, rank)
        list = Array(((magic.spells_today || {})[TODAY] || {})[charclass])
        index = pair_index(list, spell, rank)

        index ? list[index] : nil
      end

      # ------------------------------------------------------------------------------
      # Mastered spells
      # ------------------------------------------------------------------------------

      def self.mastered(magic, charclass)
        (magic.mastered_spells || {})[charclass] || {}
      end

      # Why a spell cannot be mastered at this rank, or nil. Pure. Replacing the spell already
      # mastered at a rank is allowed, since the ranks must differ.
      def self.mastery_refusal(block, rank, held)
        return err('mastery_rank_too_high', 'rank' => block['max_rank']) if block['max_rank'] && rank.to_i > block['max_rank'].to_i
        return nil if held.key?(rank.to_s)
        return err('mastery_all_used', 'count' => block['count']) if held.size >= block['count'].to_i

        nil
      end

      def self.master_spell(char, found, rank, name)
        magic = char.magic
        charclass = found['class']

        checked = Pf2emagic.check_preparable(char, charclass, name, rank.presence)
        return Pf2e::Err.new(:not_preparable, 'pf2emagic.slot_pair_spell_refused', 'spell' => name, 'why' => checked) if checked.is_a?(String)

        at = checked['level']
        return err('mastery_no_cantrip') if at == 'cantrip'

        held = mastered(magic, charclass)
        refusal = mastery_refusal(found['block'], at, held)
        return refusal if refusal

        replaced = held[at]
        all = magic.mastered_spells || {}
        all[charclass] = held.merge(at => checked['name'])
        magic.update(:mastered_spells => all)

        Pf2e::Ok.new(:state => { 'spell' => checked['name'], 'rank' => at, 'replaced' => replaced })
      end

      def self.forget_mastered(char, found, name)
        magic = char.magic
        charclass = found['class']
        held = mastered(magic, charclass)
        rank = held.keys.find { |r| held[r].to_s.casecmp?(name.to_s) || r.to_s == name.to_s }

        return err('mastery_not_held', 'spell' => name) unless rank

        spell = held[rank]
        all = magic.mastered_spells || {}
        all[charclass] = held.reject { |r, _s| r == rank }
        magic.update(:mastered_spells => all)

        Pf2e::Ok.new(:state => { 'spell' => spell, 'rank' => rank })
      end

      # ------------------------------------------------------------------------------
      # A rest
      # ------------------------------------------------------------------------------

      # The day's prepared list for a class with its mastered spells added, each in a slot of its own.
      def self.with_mastered(prepared, magic, charclass)
        list = Marshal.load(Marshal.dump(prepared || {}))

        mastered(magic, charclass).each_pair do |rank, spell|
          list[rank.to_s] = Array(list[rank.to_s]) + [ spell ]
        end

        list
      end

      # class => [ pairs ] for the day.
      def self.today(magic)
        Marshal.load(Marshal.dump(magic.slot_pairs || {})).reject { |_cc, list| Array(list).empty? }
      end
    end
  end
end
