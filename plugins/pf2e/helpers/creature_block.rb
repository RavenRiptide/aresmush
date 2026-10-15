module AresMUSH
  module Pf2e

    # A stat block as the web editor sends it, made into one the engine reads: only the parts a stat block
    # has, numbers as numbers, and no engine rules the author wrote. A Strike or ability keeps its rules
    # only where the creature it came from - the bestiary creature cloned, or the revision edited - had the
    # same ones on a part of that name; rules are the importer's, read from Foundry, never an author's.
    module CreatureBlock

      NUMBERS = %w{level ac hp hardness perception}.freeze
      COUNTED = %w{saves speeds abilities skills}.freeze
      LISTS = %w{traits immunities senses}.freeze
      WORDS = %w{name size rarity hp_details}.freeze

      def self.plain(value)
        JSON.parse(JSON.dump(value))
      end

      def self.cleaned(raw, base = nil)
        raw = plain(Hash(raw))
        base = plain(Hash(base))
        block = {}

        WORDS.each { |field| block[field] = raw[field].to_s.strip if raw[field].to_s.strip != '' }
        NUMBERS.each { |field| block[field] = raw[field].to_i if raw.key?(field) && raw[field].to_s.strip != '' }
        COUNTED.each { |field| block[field] = Hash(raw[field]).transform_values(&:to_i) if raw[field].is_a?(Hash) }
        LISTS.each { |field| block[field] = Array(raw[field]).map { |one| one.to_s.strip }.reject(&:empty?) }
        %w{weaknesses resistances}.each { |field| block[field] = Hash(raw[field]) if raw[field].is_a?(Hash) && raw[field].any? }

        block['strikes'] = Array(raw['strikes']).map { |one| strike(Hash(one), base) }
        block['actions'] = Array(raw['actions']).map { |one| ability(Hash(one), base) }
        block['shield'] = shield(Hash(raw['shield'])) if raw['shield'].is_a?(Hash)
        block['spellcasting'] = Array(raw['spellcasting']).map { |one| casting(Hash(one)) } if Array(raw['spellcasting']).any?

        block.compact
      end

      def self.strike(raw, base)
        out = { 'name' => raw['name'].to_s.strip, 'bonus' => raw['bonus'].to_i,
                'damage' => Array(raw['damage']).map { |formula, type, category| [ formula.to_s.delete(' '), type.to_s.strip.downcase, category.to_s.empty? ? nil : category.to_s ] },
                'traits' => Array(raw['traits']).map(&:to_s), 'effects' => Array(raw['effects']).map(&:to_s).reject(&:empty?) }
        out['range'] = raw['range'].to_i if raw['range'].to_i.positive?

        ruled(out, raw, base['strikes'])
      end

      def self.ability(raw, base)
        out = { 'name' => raw['name'].to_s.strip, 'type' => raw['type'].to_s.empty? ? 'action' : raw['type'].to_s,
                'cost' => raw['cost'].to_s.strip.empty? ? nil : raw['cost'].to_i, 'traits' => Array(raw['traits']).map(&:to_s),
                'text' => raw['text'].to_s }

        ruled(out, raw, base['actions'])
      end

      # Its rules, where the part of that name it came from had these same ones.
      def self.ruled(out, raw, from)
        rules = raw['rules']
        before = Array(from).find { |one| one['name'].to_s.casecmp?(out['name']) }

        rules.is_a?(Array) && rules.any? && before && before['rules'] == rules ? out.merge('rules' => rules) : out
      end

      def self.shield(raw)
        { 'name' => raw['name'].to_s.strip.empty? ? 'Shield' : raw['name'].to_s.strip, 'hardness' => raw['hardness'].to_i,
          'hp' => raw['hp'].to_i, 'ac' => (raw['ac'] || 2).to_i }
      end

      def self.casting(raw)
        { 'name' => raw['name'].to_s, 'tradition' => raw['tradition'].to_s, 'type' => raw['type'].to_s, 'dc' => raw['dc'].to_i,
          'attack' => raw['attack'].to_i, 'spells' => Hash(raw['spells']).transform_values { |names| Array(names).map(&:to_s) } }
          .merge(raw['slots'].is_a?(Hash) ? { 'slots' => raw['slots'].transform_values(&:to_i) } : {})
          .merge(raw['uses'].is_a?(Hash) ? { 'uses' => raw['uses'].transform_values(&:to_i) } : {})
      end
    end
  end
end
