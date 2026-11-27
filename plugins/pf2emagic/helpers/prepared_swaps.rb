module AresMUSH
  module Pf2emagic

    # Changing what a prepared slot holds after daily preparations, over ten minutes. Each is a key the
    # feat's data carries, so no code names a feat:
    #
    #   swaps_prepared:          # prepare/swap <spell> = <new spell>: one of the day's prepared spells
    #     into: [ Summon Elemental ]   # replaced by one of these at the same rank (Call of the Wild,
    #                                  # Elemental Summons), or
    #     into: chosen                 # by the spell the feat's own choice picked (Rites of Convocation)
    #
    #   reprepare:               # prepare/reprepare <spell>: a spell cast today, of this rank or lower
    #     max_rank: 4            # and without a duration, back in its slot (Reprepare Spell)
    #
    # A wizard with the Spell Substitution thesis swaps into any spell they could prepare at that rank, and
    # may fill a slot they reprepare with a different spell (`prepare/reprepare <spell> = <new spell>`), which
    # holds that slot to spells without a duration until the next rest.
    #
    # None of it can be done in a fight. Where they stand in a running encounter that is exploring, the
    # encounter's copy of the day's spells is changed; outside one, their own.
    #
    # Each change of spell is kept in spells_today['prepared swaps'] as
    # { class => [ { 'rank', 'from', 'to', 'no_duration' } ] }, which a rest rebuilds empty. It lets
    # BondedItem.cast_today tell a spell swapped away from one cast, and keeps a slot's limit to spells
    # without a duration through later swaps.
    module PreparedSwaps

      TODAY = 'prepared swaps'.freeze

      THESIS = 'Spell Substitution'.freeze

      def self.err(key, args = {})
        Pf2e::Err.new(key.to_sym, "pf2emagic.#{key}", args)
      end

      def self.substitution?(char)
        char.respond_to?(:pf2_base_info) && ((char.pf2_base_info || {})['specialize_info']).to_s.casecmp?(THESIS)
      end

      # What may swap the character's prepared spells: [ { 'source', 'class', 'into' } ], where `into` is
      # the spells a swap may take, or nil for any the class could prepare at that rank.
      def self.swap_sources(char)
        sources = Pf2e::DraftSheet.of(char).feat_names.map(&:to_s).uniq(&:downcase).filter_map do |name|
          found = Pf2e.get_feat_details(name)
          next unless found.is_a?(Array) && found[1]['swaps_prepared'].is_a?(Hash)

          block = found[1]['swaps_prepared']
          into = block['into'].to_s.casecmp?('chosen') ? Array(Pf2e.choice_for(char, found[0])) : Array(block['into'])

          { 'source' => found[0], 'class' => Array(found[1]['assoc_charclass']).first.to_s, 'into' => into.map(&:to_s) }
        end

        if substitution?(char)
          sources << { 'source' => THESIS, 'class' => (char.pf2_base_info || {})['charclass'].to_s, 'into' => nil }
        end

        sources
      end

      # [ feat, block ] for the character's feat carrying `reprepare:`, or nil.
      def self.reprepare_feat(char)
        Pf2e::DraftSheet.of(char).feat_names.map(&:to_s).uniq(&:downcase).each do |name|
          found = Pf2e.get_feat_details(name)

          return found if found.is_a?(Array) && found[1]['reprepare'].is_a?(Hash)
        end

        nil
      end

      def self.duration?(spell)
        found = Pf2emagic.get_spell_details(spell.to_s)

        found.is_a?(Array) && found[1]['duration'].to_s.strip.present?
      end

      # ------------------------------------------------------------------------------
      # Where they stand

      def self.running(char)
        char.is_a?(Character) ? PF2Encounter.running_for(char).to_a : []
      end

      # Ten minutes is not to be had in a fight: refused in a running encounter that is not exploring.
      def self.fight_refusal(char)
        running(char).any? { |encounter| !Pf2e::Exploration.exploring?(encounter) } ? err('swap_in_fight') : nil
      end

      # Whose day's spells a change is written to: their state in each running encounter, or their own.
      def self.holders(char)
        states = running(char).filter_map { |encounter| Pf2e::CombatantStates.of(encounter, char) }

        states.empty? ? [ char ] : states
      end

      # ------------------------------------------------------------------------------
      # The record of the day's changes

      def self.swaps(today, charclass)
        Array((today[TODAY] || {})[charclass])
      end

      # How many copies of a spell the day began with at a rank, as changed since: prepared, less those
      # swapped away, plus those swapped in.
      def self.expected(prepared_list, today, charclass, rank, spell)
        changed = swaps(today, charclass).select { |swap| swap['rank'].to_s == rank.to_s }

        Array(prepared_list).count(spell) - changed.count { |swap| swap['from'] == spell } +
          changed.count { |swap| swap['to'] == spell }
      end

      # Whether every copy of a spell left at a rank is in a slot held to spells without a duration.
      def self.restricted?(today, charclass, rank, spell)
        changed = swaps(today, charclass).select { |swap| swap['rank'].to_s == rank.to_s && swap['no_duration'] }
        held = changed.count { |swap| swap['to'] == spell } - changed.count { |swap| swap['from'] == spell }
        left = Array((today[charclass] || {})[rank.to_s]).count(spell)

        held.positive? && left <= held
      end

      # The lowest rank holding a copy of the spell today, or the one asked for if it holds one.
      def self.rank_holding(today, charclass, spell, rank = nil)
        ranks = (today[charclass] || {}).select do |at, list|
          at.to_s != 'cantrip' && Array(list).include?(spell) && (rank.blank? || at.to_s == rank.to_s)
        end

        ranks.keys.min_by(&:to_i)
      end

      # The day's spells with one copy of `from` at a rank replaced by `to` (or `to` added, where `from` was
      # already cast), and the change recorded. Pure.
      def self.changed(today, charclass, rank, from, to, no_duration, spent: false)
        out = Marshal.load(Marshal.dump(today))
        list = Array((out[charclass] || {})[rank.to_s])

        unless spent
          index = list.index(from)
          list.delete_at(index) if index
        end

        out[charclass] = (out[charclass] || {}).merge(rank.to_s => list + [ to ])

        unless from == to
          record = { 'rank' => rank.to_s, 'from' => from, 'to' => to, 'no_duration' => no_duration }
          out[TODAY] = (out[TODAY] || {}).merge(charclass => swaps(out, charclass) + [ record ])
        end

        out
      end

      def self.write!(char, charclass, rank, from, to, no_duration, spent: false)
        holders(char).each do |holder|
          magic = holder.magic
          next unless magic

          today = magic.spells_today || {}
          magic.update(:spells_today => changed(today, charclass, rank, from, to, no_duration, spent: spent))
        end
      end

      # A spell a feat names goes in the slot whether or not their spellbook or familiar holds it, so long as
      # it is of the slot's rank or lower and on their tradition. Answers check_preparable's hash, or why not.
      def self.named_check(char, charclass, found, rank)
        name, details = found
        own = details['base_level'].to_s.casecmp?('cantrip') ? 0 : details['base_level'].to_i

        return t('pf2emagic.cant_prepare_level') if own.zero? || own > rank.to_i

        tradition = Entries.tradition_of(char.magic, charclass).to_s.downcase
        return t('pf2emagic.cant_prepare_trad', :cc => charclass) unless Array(details['tradition']).include?(tradition)

        { 'level' => rank.to_s, 'name' => name, 'caster class' => charclass }
      end

      # ------------------------------------------------------------------------------
      # prepare/swap

      # One of the day's prepared spells replaced by another at the same rank. Ok carries
      # { 'source', 'class', 'rank', 'from', 'to' }.
      def self.swap(char, from, to, rank = nil)
        refusal = fight_refusal(char)
        return refusal if refusal

        sources = swap_sources(char)
        return err('swap_no_source') if sources.empty?

        found = Pf2emagic.get_spell_details(from.to_s)
        return Pf2e::Err.new(:no_spell, 'pf2emagic.swap_refused', 'why' => found) if found.is_a?(String)

        wanted = Pf2emagic.get_spell_details(to.to_s)
        return Pf2e::Err.new(:no_spell, 'pf2emagic.swap_refused', 'why' => wanted) if wanted.is_a?(String)

        from_name = found[0]
        to_name = wanted[0]
        today = holders(char).first.magic&.spells_today || {}
        refused = nil

        sources.each do |source|
          charclass = source['class']
          at = rank_holding(today, charclass, from_name, rank)
          next unless at

          if source['into'] && source['into'].none? { |one| one.casecmp?(to_name) }
            refused ||= err('swap_not_offered', 'source' => source['source'], 'spells' => source['into'].join(', ').presence || '-')
            next
          end

          checked = source['into'] ? named_check(char, charclass, wanted, at) : Pf2emagic.check_preparable(char, charclass, to_name, at)

          if checked.is_a?(String)
            refused = Pf2e::Err.new(:not_preparable, 'pf2emagic.swap_spell_refused', 'spell' => to_name, 'why' => checked)
            next
          end

          held_to_no_duration = restricted?(today, charclass, at, from_name)
          return err('swap_no_duration_slot', 'spell' => to_name) if held_to_no_duration && duration?(to_name)

          write!(char, charclass, at, from_name, checked['name'], held_to_no_duration)

          return Pf2e::Ok.new(:state => { 'source' => source['source'], 'class' => charclass, 'rank' => at,
                                          'from' => from_name, 'to' => checked['name'] })
        end

        refused || err('swap_not_prepared', 'spell' => from_name)
      end

      # ------------------------------------------------------------------------------
      # prepare/reprepare

      # A spell cast today back in its slot, or, with Spell Substitution, a different spell without a
      # duration in that slot. Ok carries { 'class', 'rank', 'from', 'to' }.
      def self.reprepare(char, spell, to = nil)
        refusal = fight_refusal(char)
        return refusal if refusal

        feat = reprepare_feat(char)
        return err('reprepare_not_held') unless feat

        charclass = Array(feat[1]['assoc_charclass']).first.to_s
        max = feat[1]['reprepare']['max_rank'].to_i

        found = Pf2emagic.get_spell_details(spell.to_s)
        return Pf2e::Err.new(:no_spell, 'pf2emagic.swap_refused', 'why' => found) if found.is_a?(String)

        name = found[0]
        magic = holders(char).first.magic
        return err('reprepare_not_cast', 'spell' => name) unless magic

        prepared = (magic.spells_prepared || {}).slice(charclass)
        cast = Pf2e::BondedItem.cast_today(prepared, magic.spells_today || {}, name)
        return err('reprepare_not_cast', 'spell' => name) unless cast

        rank = cast[1]
        return err('reprepare_rank_too_high', 'rank' => max) if rank.to_i > max

        if to.blank?
          return err('reprepare_has_duration', 'spell' => name) if duration?(name)

          write!(char, charclass, rank, name, name, false, spent: true)

          return Pf2e::Ok.new(:state => { 'class' => charclass, 'rank' => rank, 'from' => name, 'to' => name })
        end

        return err('reprepare_needs_thesis', 'thesis' => THESIS) unless substitution?(char)

        checked = Pf2emagic.check_preparable(char, charclass, to.to_s, rank)
        return Pf2e::Err.new(:not_preparable, 'pf2emagic.swap_spell_refused', 'spell' => to, 'why' => checked) if checked.is_a?(String)
        return err('reprepare_has_duration', 'spell' => checked['name']) if duration?(checked['name'])

        write!(char, charclass, rank, name, checked['name'], true, spent: true)

        Pf2e::Ok.new(:state => { 'class' => charclass, 'rank' => rank, 'from' => name, 'to' => checked['name'] })
      end
    end
  end
end
