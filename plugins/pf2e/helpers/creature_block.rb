module AresMUSH
  module Pf2e

    # A stat block as the web editor sends it, made into one the engine reads. Anyone may craft what is
    # sent, so every part is taken only in the shape a stat block has - a figure as a number, a list of
    # words, a Strike as its fields - and anything else is dropped rather than raised on or stored. Lists
    # and words are kept to a stat block's size.
    #
    # A Strike or ability keeps engine rules only where the creature it came from - the bestiary creature
    # cloned, or the revision edited - had the same ones on a part of that name: rules are the importer's,
    # read from Foundry, never an author's.
    module CreatureBlock

      NUMBERS = %w{level ac hp hardness perception}.freeze
      COUNTED = %w{saves speeds abilities skills}.freeze
      LISTS = %w{traits immunities senses}.freeze
      WORDS = %w{name size rarity hp_details shape}.freeze

      MOST_LISTED = 30
      LONGEST = 2000
      LONGEST_TEXT = 4000

      def self.plain(value)
        JSON.parse(JSON.dump(value))
      end

      # A number from what may not be one: a string or a number, else nothing.
      def self.int(value)
        value.is_a?(Integer) || value.is_a?(Float) || (value.is_a?(String) && value.strip.match?(/\A[+-]?\d+\z/)) ? value.to_i : nil
      end

      def self.word(value, longest = LONGEST)
        value.is_a?(String) || value.is_a?(Numeric) ? value.to_s.strip[0, longest] : ''
      end

      def self.words(value)
        (value.is_a?(Array) ? value : []).map { |one| word(one, 60) }.reject(&:empty?).first(MOST_LISTED)
      end

      def self.hash(value)
        value.is_a?(Hash) ? value : {}
      end

      # A creature with nothing yet but its level, for an author to build from.
      def self.blank(level)
        { 'name' => '', 'level' => level, 'traits' => [], 'saves' => { 'fortitude' => 0, 'reflex' => 0, 'will' => 0 },
          'strikes' => [], 'actions' => [] }
      end

      def self.cleaned(raw, base = nil)
        raw = hash(plain(raw))
        base = hash(plain(base))
        block = {}

        WORDS.each { |field| block[field] = word(raw[field]) if word(raw[field]) != '' }
        NUMBERS.each { |field| block[field] = int(raw[field]) unless int(raw[field]).nil? }
        COUNTED.each do |field|
          counted = hash(raw[field]).filter_map { |key, value| int(value).nil? ? nil : [ word(key, 60), int(value) ] }.reject { |key, _| key.empty? }
          block[field] = counted.first(MOST_LISTED).to_h if raw[field].is_a?(Hash)
        end
        LISTS.each { |field| block[field] = words(raw[field]) }
        %w{weaknesses resistances}.each { |field| block[field] = resisted(raw[field]) if raw[field].is_a?(Hash) && resisted(raw[field]).any? }

        block['strikes'] = parts(raw['strikes']).map { |one| strike(one, base) }
        block['actions'] = parts(raw['actions']).map { |one| ability(one, base) }
        block['shield'] = shield(raw['shield']) if raw['shield'].is_a?(Hash)
        block['spellcasting'] = parts(raw['spellcasting']).first(10).map { |one| casting(one) } if parts(raw['spellcasting']).any?

        block.compact
      end

      def self.parts(value)
        (value.is_a?(Array) ? value : []).select { |one| one.is_a?(Hash) }
      end

      # A weakness or resistance: its value, or its value with what it excepts and what it doubles against.
      def self.resisted(value)
        hash(value).filter_map do |type, held|
          key = word(type, 60)
          next nil if key.empty?

          if held.is_a?(Hash)
            worth = int(held['value'])
            next nil if worth.nil?

            [ key, { 'value' => worth, 'except' => words(held['except']), 'double' => words(held['double']) }.reject { |_, one| one == [] } ]
          else
            int(held).nil? ? nil : [ key, int(held) ]
          end
        end.first(MOST_LISTED).to_h
      end

      def self.strike(raw, base)
        damage = (raw['damage'].is_a?(Array) ? raw['damage'] : []).select { |one| one.is_a?(Array) && one.size >= 2 }.first(5).map do |formula, type, category|
          [ word(formula, 40).delete(' '), word(type, 40).downcase, word(category, 20).empty? ? nil : word(category, 20) ]
        end
        out = { 'name' => word(raw['name'], 60), 'bonus' => int(raw['bonus']).to_i, 'damage' => damage, 'traits' => words(raw['traits']),
                'effects' => words(raw['effects']) }
        out['range'] = int(raw['range']) if int(raw['range']).to_i.positive?

        ruled(out, raw, base['strikes'])
      end

      def self.ability(raw, base)
        type = %w{action reaction free passive}.include?(raw['type']) ? raw['type'] : 'action'
        out = { 'name' => word(raw['name'], 60), 'type' => type, 'cost' => int(raw['cost']), 'traits' => words(raw['traits']),
                'text' => word(raw['text'], LONGEST_TEXT + 1) }

        ruled(out, raw, base['actions'])
      end

      # Its rules, and the shape it is offered in, where the part of that name it came from had these same.
      def self.ruled(out, raw, from)
        before = (from.is_a?(Array) ? from : []).find { |one| one.is_a?(Hash) && one['name'].to_s.casecmp?(out['name']) }

        %w{rules when}.reduce(out) do |held, field|
          kept = raw[field]
          kept.is_a?(Array) && kept.any? && before && before[field] == kept ? held.merge(field => kept) : held
        end
      end

      def self.shield(raw)
        { 'name' => word(raw['name'], 60).empty? ? 'Shield' : word(raw['name'], 60), 'hardness' => int(raw['hardness']).to_i,
          'hp' => int(raw['hp']).to_i, 'ac' => (int(raw['ac']) || 2) }
      end

      def self.casting(raw)
        spells = hash(raw['spells']).filter_map { |rank, names| int(rank).nil? ? nil : [ int(rank).to_s, words(names) ] }.to_h
        counted = ->(value) { hash(value).filter_map { |key, number| int(number).nil? ? nil : [ word(key, 60), int(number) ] }.to_h }

        { 'name' => word(raw['name'], 60), 'tradition' => word(raw['tradition'], 20), 'type' => word(raw['type'], 20),
          'dc' => int(raw['dc']), 'attack' => int(raw['attack']), 'spells' => spells }
          .merge(raw['slots'].is_a?(Hash) ? { 'slots' => counted.call(raw['slots']) } : {})
          .merge(raw['uses'].is_a?(Hash) ? { 'uses' => counted.call(raw['uses']) } : {})
      end
    end
  end
end
