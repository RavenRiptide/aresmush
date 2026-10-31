module AresMUSH
  module Pf2e

    # What a saved creature may not be: whatever would keep the engine from fighting with it. A creature
    # with any of these is not saved, so everything in the database can be added to an encounter.
    #
    # Each finding is `{ 'code', 'key', 'args' }`, for a command to tell and a spec to read by its code.
    module CreatureCheck

      FORMULA = /\A(?:(?<count>\d*)d(?<sides>\d+)(?<plus>[+-]\d+)?|(?<flat>\d+))\z/i
      DICE = 1..50
      SIDES = 2..100
      PLUS = 500

      # A damage formula the game can roll: up to 50 dice of 2 to 100 sides, and a figure added of at most
      # 500, or a flat number of at most that.
      def self.formula?(formula)
        found = formula.to_s.delete(' ').match(FORMULA)

        return false unless found
        return found[:flat].to_i <= PLUS if found[:flat]

        DICE.cover?(found[:count].to_s.empty? ? 1 : found[:count].to_i) && SIDES.cover?(found[:sides].to_i) && found[:plus].to_i.abs <= PLUS
      end
      LEVELS = (-1..25).freeze
      LONGEST = 60

      def self.found(code, args = {})
        { 'code' => code, 'key' => "pf2e.#{code}", 'args' => args }
      end

      # What is warned of and not refused: a word the game does not know, a figure above the highest GM
      # Core gives for the creature's level, and spells with no DC.
      def self.warnings(block)
        CreatureVocabulary.warnings(block) + CreatureBenchmarks.warnings(block) + spell_dcs(block)
      end

      # A spell DC left blank is the GM's to set at every cast; the level's moderate one is offered.
      def self.spell_dcs(block)
        level = block['level'].to_i

        Array(block['spellcasting']).select { |casting| casting['dc'].to_i.zero? }.map do |casting|
          named = casting['name'].to_s.strip.empty? ? 'its spells' : casting['name']

          found(:creature_casting, 'casting' => named, 'what' => t('pf2e.creature_casting_dc', :level => level,
                                                                     :dc => CreatureBenchmarks.figure_at('spell', level, 'moderate_dc')))
        end
      end

      def self.errors(block)
        needs(block) + level(block) + strikes(block) + abilities(block) + sizes(block) + shape(block) + spellcasting(block)
      end

      TRADITIONS = %w{arcane divine occult primal}.freeze
      # Foundry's: `items` is spells cast from scrolls and the like, as a thaumaturge does.
      CASTING_TYPES = %w{prepared spontaneous innate focus items}.freeze
      RANKS = (0..10).freeze

      # Spells as the game casts them: a tradition and a way of casting it knows, ranks from cantrips to 10,
      # and a spontaneous caster's slots for every rank above cantrips it casts at.
      def self.spellcasting(block)
        Array(block['spellcasting']).flat_map do |casting|
          named = casting['name'].to_s.strip.empty? ? 'its spells' : casting['name']
          problems = []
          problems << found(:creature_casting, 'casting' => named, 'what' => t('pf2e.creature_casting_tradition', :list => TRADITIONS.join(', '))) unless TRADITIONS.include?(casting['tradition'])
          problems << found(:creature_casting, 'casting' => named, 'what' => t('pf2e.creature_casting_type', :list => CASTING_TYPES.join(', '))) unless CASTING_TYPES.include?(casting['type'])

          ranks = Hash(casting['spells']).keys.map(&:to_i)
          problems << found(:creature_casting, 'casting' => named, 'what' => t('pf2e.creature_casting_ranks')) unless ranks.all? { |rank| RANKS.cover?(rank) }

          unslotted = casting['type'] == 'spontaneous' ? ranks.select(&:positive?).reject { |rank| Hash(casting['slots'])[rank.to_s].to_i.positive? } : []
          problems << found(:creature_casting, 'casting' => named, 'what' => t('pf2e.creature_casting_slots', :ranks => unslotted.sort.join(', '))) if unslotted.any?

          problems
        end
      end

      # The shape it starts in is one its abilities give it.
      def self.shape(block)
        return [] if block['shape'].nil? || Shapes.choices_in(block).include?(block['shape'])

        [ found(:creature_shape, 'shape' => block['shape'], 'shapes' => Shapes.choices_in(block).join(', ')) ]
      end

      # What one creature may hold at most, which keeps a stat block a stat block.
      MOST = { 'strikes' => 20, 'actions' => 40, 'spellcasting' => 6 }.freeze
      LONGEST_TEXT = 4000

      def self.sizes(block)
        many = MOST.filter_map { |field, most| Array(block[field]).size > most ? found(:creature_too_many, 'what' => field, 'most' => most) : nil }
        long = Array(block['actions']).select { |one| one['text'].to_s.length > LONGEST_TEXT }
                                      .map { |one| found(:creature_text_long, 'ability' => one['name'], 'most' => LONGEST_TEXT) }

        many + long
      end

      def self.needs(block)
        %w{ac hp}.reject { |field| block[field].to_i.positive? }.map { |field| found(:creature_needs, 'figure' => field.upcase) }
      end

      def self.level(block)
        LEVELS.cover?(block['level'].to_i) ? [] : [ found(:creature_level, 'level' => block['level'], 'from' => LEVELS.first, 'to' => LEVELS.last) ]
      end

      def self.strikes(block)
        listed = Array(block['strikes'])

        listed.flat_map do |strike|
          named = strike['name'].to_s.strip
          next [ found(:creature_unnamed, 'what' => 'Strike') ] if named.empty?

          damage = Array(strike['damage'])
          next [ found(:creature_strike_damage, 'strike' => named) ] if damage.empty?

          damage.reject { |formula, _type, _category| formula?(formula) }
                .map { |formula, _type, _category| found(:creature_formula, 'formula' => formula, 'strike' => named) }
        end + twice(listed, 'Strike')
      end

      def self.abilities(block)
        listed = Array(block['actions'])

        listed.flat_map do |ability|
          named = ability['name'].to_s.strip
          next [ found(:creature_unnamed, 'what' => 'ability') ] if named.empty?

          problems = []
          problems << found(:creature_ability_text, 'ability' => named) if ability['text'].to_s.strip.empty?
          problems << found(:creature_ability_cost, 'ability' => named) if ability['type'] == 'action' && !(1..3).cover?((ability['cost'] || 1).to_i)
          problems
        end + twice(listed, 'ability')
      end

      # Two of a kind under one name, which `creature/set` and `+e/as` could not tell apart.
      def self.twice(listed, what)
        listed.map { |one| one['name'].to_s.strip.downcase }.reject(&:empty?).tally.select { |_name, count| count > 1 }
              .map { |name, _count| found(:creature_twice, 'what' => what, 'name' => name) }
      end

      # A name a saved creature may take: one `+e/add` can read back, and not a bestiary creature's, which
      # the bestiary keeps. `bestiary` answers the bestiary's creature of that name, if any.
      def self.name(words, bestiary = ->(term) { Bestiary.named(term) })
        named = words.to_s.strip

        return Err.new(:creature_name_empty, 'pf2e.creature_name_empty') if named.empty?
        return Err.new(:creature_name_long, 'pf2e.creature_name_long', 'most' => LONGEST) if named.length > LONGEST
        return Err.new(:creature_name_mark, 'pf2e.creature_name_mark') if named.match?(%r{[=;#/]|\Ac(?:ustom)?:}i)
        return Err.new(:creature_name_count, 'pf2e.creature_name_count') if named.match?(/\A\d+(?:\s|\z)/)
        return Err.new(:creature_name_adjusted, 'pf2e.creature_name_adjusted', 'word' => named.split.first) if
          Adjustments.names.include?(named.split.first.downcase)

        taken = bestiary.call(named)

        return Err.new(:creature_name_bestiary, 'pf2e.creature_name_bestiary', 'name' => taken) if taken

        Ok.new(:state => named)
      end
    end
  end
end
