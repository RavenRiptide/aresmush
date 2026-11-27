module AresMUSH
  module Pf2emagic

    # The Spells tab of a character's profile, as plain data: one block per source they cast from, then their
    # focus, innate and adapted spells. Built from the spellcasting entries (`Entries`), so a character who
    # keeps both a spellbook and a repertoire shows both, each as its own source keeps it.
    module SpellsView

      def self.of(char)
        magic = char.magic
        return nil unless magic

        # The sources the tradition register lists, as `magic` shows them: a stored row the register
        # doesn't list has no casting attribute to read a spell attack or DC from.
        registered = (magic.tradition || {}).keys.map(&:to_s)
        casting = Entries.casting(magic).select { |entry| registered.any? { |one| one.casecmp?(entry['name'].to_s) } }

        { name: char.name,
          sources: casting.sort_by { |entry| entry['name'].to_s }.map { |entry| source(char, magic, entry) },
          focus: focus(char, magic),
          innate: innate(magic),
          adapted: adapted(magic) }
      end

      # A rank as a number, with a cantrip at 0.
      def self.rank_of(key)
        key.to_s.casecmp?('cantrip') ? 0 : key.to_i
      end

      def self.spells(list, kind = 'spell')
        Pf2e::ProfileSheet.items(Array(list).reject { |spell| spell.to_s.casecmp?(Entries::OPEN) }.map(&:to_s).sort, kind)
      end

      # What a source keeps its spells in: a repertoire, a spellbook, the witch's familiar, or nothing for a
      # source that casts from its whole tradition.
      def self.keeps(char, entry)
        return nil unless Entries.enumerated?(entry['name'])
        return 'repertoire' if entry['category'].to_s == 'spontaneous'

        Pf2e::FamiliarView.spell_source(char).to_s.casecmp?(entry['name'].to_s) ? 'familiar' : 'spellbook'
      end

      def self.source(char, magic, entry)
        name = entry['name'].to_s
        prepared = ((magic.spells_prepared || {})[name] || {})
        known = entry['known'] || {}
        slots = entry['slots'] || {}
        signature = entry['category'].to_s == 'spontaneous' ? (entry['signature'] || {}) : {}

        ranks = (slots.keys + known.keys + prepared.keys).map { |key| rank_of(key) }.uniq.sort.map do |rank|
          pick = ->(hash) { hash.find { |key, _value| rank_of(key) == rank }&.last }

          { rank: rank, slots: pick.call(slots).to_i,
            prepared: spells(pick.call(prepared)), known: spells(pick.call(known)),
            signature: spells(pick.call(signature)) }
        end

        { name: name.sub(/ Archetype$/, ''), archetype: entry['source_type'] == 'archetype',
          tradition: entry['tradition'].to_s, category: entry['category'].to_s, rank: entry['proficiency'].to_s,
          attack: PF2Magic.get_spell_attack_bonus(char, name), dc: PF2Magic.get_spell_dc(char, name),
          keeps: keeps(char, entry), ranks: ranks,
          divine_font: name.casecmp?('Cleric') ? magic.divine_font.presence : nil,
          deity_spells: spells(Pf2emagic.deity_list_spells(char, name)) }
      end

      # One block per focus entry, so two sources of one type show apart: each casts at its own DC.
      def self.focus(char, magic)
        tradition = magic.tradition || {}
        by_source = Global.read_config('pf2e_magic', 'focus_type_by_source') || {}

        entries = Entries.focus_entries(magic).sort_by { |entry| entry['name'].to_s }.filter_map do |entry|
          known = entry['known'] || {}
          next if Array(known['spell']).empty? && Array(known['cantrip']).empty?

          source = entry['granted_by'].presence || focus_source(by_source, entry['name'], tradition)
          casts = source && Array(tradition[source]).size >= 2

          { label: Entries.focus_label(entry), source: source,
            dc: casts ? PF2Magic.get_spell_dc(char, source, entry['name']) : nil,
            cantrips: spells(known['cantrip']), spells: spells(known['spell']) }
        end

        { pool: Pf2emagic.focus_pool_max(magic), entries: entries }
      end

      # The casting source a focus type belongs to, for an entry that doesn't say which granted it.
      def self.focus_source(by_source, type, tradition)
        sources = by_source.select { |_source, held| held.to_s.casecmp?(type.to_s) }.keys

        tradition.keys.find { |held| sources.any? { |one| one.to_s.casecmp?(held.to_s) } } || sources.first
      end

      def self.innate(magic)
        Entries.innate_grants(magic).map do |grant|
          open = grant['name'].to_s.casecmp?(Entries::OPEN)

          { spell: open ? nil : Pf2e::ProfileSheet.item(Pf2e.pretty_string(grant['name']), 'spell'),
            rank: rank_of(Entries.innate_rank(magic, grant)), tradition: grant['tradition'].to_s }
        end
      end

      # A spell from another tradition cast as one of theirs (Adapted Cantrip, Adapt Ritual).
      def self.adapted(magic)
        (magic.adapted_spells || {}).map do |name, info|
          info = {} unless info.is_a?(Hash)

          { spell: Pf2e::ProfileSheet.item(Pf2e.pretty_string(name), 'spell'), rank: info['base_level'].to_i,
            tradition: info['tradition'].to_s, source: info['class'].presence }
        end.sort_by { |one| [ one[:rank], one[:spell][:name] ] }
      end
    end
  end
end
