module AresMUSH
  module Pf2e
    module Companion

      # An animal companion's statistics (Player Core pp. 206-211), from its type and how far it has
      # advanced. It reads and never writes, and asks nothing of the database: everything comes from the
      # arguments and pf2e_animal_companions.yml.
      #
      #   Level            the master's
      #   Attributes       the type's, plus each stage's and specialization's increases
      #   Hit Points       the type's, plus 6 + Constitution per level (and Auspice's extra)
      #   Proficiency      untrained 0, otherwise level + 2 per rank above untrained
      #   AC               10 + Dexterity (capped by barding) + unarmored or barding proficiency + barding's
      #                    item bonus (at most +3)
      #   Saves            Fortitude Con, Reflex Dex, Will Wis; Perception Wis
      #   Unarmed attacks  attack proficiency + Strength (the higher of Strength and Dexterity if finesse);
      #                    damage is the stage's dice + Strength + the additional damage of a nimble (2) or
      #                    savage (3) companion, doubled once specialized
      #   Size             the type's (or the size chosen for a Horse), one larger at mature and at savage
      #                    while Medium or smaller
      #
      # A companion is `{ 'type' => 'Wolf', 'size' => nil, 'mature' => true, 'path' => 'savage',
      # 'specializations' => [ { 'name' => 'Racer', 'choice' => 'land' } ] }`: `size` only for a type with
      # `sizes`, `path` nil, 'nimble' or 'savage', and any specialization making it specialized. `barding` is
      # `{ 'name' => ..., 'companion_armor' => { ... } }` as pf2e_gear.yml writes it, or nil. `item_bonuses` are
      # what its invested items give, `{ 'speed' => 5 }`: an item bonus to its land Speed.
      #
      # `grants` is what the master's feats give it, merged from their `companion_grants`: `skills` (a skill
      # at least that rank: Fell Rider's Intimidation), `raise_with` (a specialization => skills one rank up,
      # to legendary: Stealthy Companion's ambusher), and `mount` (types that gain the mount special: Rough
      # Rider's wolf).
      module Stats

        RANKS = %w{untrained trained expert master legendary}.freeze
        SIZES = %w{Tiny Small Medium Large Huge Gargantuan}.freeze
        SAVES = { 'Fortitude' => 'Constitution', 'Reflex' => 'Dexterity', 'Will' => 'Wisdom' }.freeze

        # The skills a companion can be trained in, and their attributes.
        SKILLS = { 'Acrobatics' => 'Dexterity', 'Athletics' => 'Strength', 'Intimidation' => 'Charisma',
                   'Religion' => 'Wisdom', 'Stealth' => 'Dexterity', 'Survival' => 'Wisdom' }.freeze

        # The skills armor's check penalty applies to: those using Strength or Dexterity.
        CHECKED = %w{Strength Dexterity}.freeze

        MAX_ITEM_AC = 3
        HP_PER_LEVEL = 6
        MINIMUM_SPEED = 5

        def self.catalogue
          Global.read_config('pf2e_animal_companions') || {}
        end

        def self.type_info(name, from = nil)
          ((from || catalogue)['types'] || {})[name.to_s]
        end

        # The stages a companion has reached, in order.
        def self.stages(companion)
          list = [ 'young' ]
          list << 'mature' if companion['mature']
          list << companion['path'].to_s if %w{nimble savage}.include?(companion['path'].to_s)
          list << 'specialized' unless Array(companion['specializations']).empty?
          list
        end

        # What to call how far it has advanced: young, mature, nimble, savage or specialized.
        def self.stage_name(companion)
          stages(companion).last
        end

        # nil for a type the catalogue doesn't have.
        def self.of(companion, level:, barding: nil, item_bonuses: {}, grants: {}, catalogue: nil)
          held = catalogue || self.catalogue
          info = type_info(companion['type'], held)
          return nil unless info

          level = level.to_i
          grants ||= {}
          reached = stages(companion)
          specials = Array(companion['specializations']).filter_map do |one|
            found = (held['specializations'] || {})[one['name'].to_s]
            found ? [ one, found ] : nil
          end

          attributes = attributes_of(info, reached, specials, held)
          ranks = granted_ranks(ranks_of(info, reached, specials, held), specials, grants)
          size = size_of(info, companion['size'], reached, held)
          armor = barding && barding['companion_armor'].is_a?(Hash) ? barding['companion_armor'] : nil

          { 'type' => companion['type'].to_s,
            'level' => level,
            'stage' => reached.last,
            'size' => size,
            'traits' => traits_of(info, specials),
            'attributes' => attributes,
            'hp' => hp_of(info, attributes, level, specials),
            'ac' => ac_of(attributes, ranks, level, armor),
            'perception' => bonus(ranks['perception'], level) + attributes['Wisdom'],
            'saves' => SAVES.to_h { |save, attribute| [ save, bonus(ranks[save], level) + attributes[attribute] ] },
            'skills' => skills_of(ranks, attributes, level, armor),
            'attacks' => attacks_of(info, attributes, ranks, level, reached, held),
            'speeds' => speeds_of(info, specials, attributes, armor, item_bonuses || {}),
            'senses' => Array(info['senses']),
            'weaknesses' => weaknesses_of(specials),
            'mount' => info['mount'] == true || Array(grants['mount']).include?(companion['type'].to_s),
            'special' => info['special'],
            'support' => info['support'],
            'maneuver' => reached.include?('nimble') || reached.include?('savage') ? info['maneuver'] : nil,
            'specializations' => specials.map { |one, found| { 'name' => one['name'], 'choice' => one['choice'], 'description' => found['description'] } },
            'barding' => armor ? barding['name'] : nil,
            'ranks' => ranks.transform_values { |rank| RANKS[rank] } }
        end

        def self.bonus(rank, level)
          rank.to_i.zero? ? 0 : level + 2 * rank.to_i
        end

        def self.rank_of(word)
          RANKS.index(word.to_s) || 0
        end

        def self.attributes_of(info, reached, specials, held)
          out = Hash.new(0).merge(info['attributes'] || {})

          increases = reached.map { |stage| ((held['stages'] || {})[stage] || {})['attributes'] } +
                      specials.map { |_one, found| found['attributes'] }
          increases.compact.each { |more| more.each { |name, value| out[name] += value.to_i } }

          %w{Strength Dexterity Constitution Intelligence Wisdom Charisma}.to_h { |name| [ name, out[name] ] }
        end

        # Proficiency ranks as numbers. `saves` sets the three saves; `type_skill` is the type's skill.
        def self.ranks_of(info, reached, specials, held)
          ranks = Hash.new(0)
          type_skill = info['skill'].to_s

          raise_to = lambda do |key, word|
            keys = key == 'saves' ? SAVES.keys : [ key == 'type_skill' ? type_skill : key ]
            keys.each { |one| ranks[one] = [ ranks[one], rank_of(word) ].max }
          end

          reached.each do |stage|
            info_of = (held['stages'] || {})[stage] || {}
            (info_of['ranks'] || {}).each { |key, word| raise_to.call(key, word) }
            Array(info_of['trained']).each { |skill| raise_to.call(skill, skill == type_skill ? 'expert' : 'trained') }
          end

          specials.each do |_one, found|
            (found['ranks'] || {}).each { |key, word| raise_to.call(key, word) }
            Array(found['raise']).each { |skill| ranks[skill] = [ ranks[skill] + 1, rank_of('master') ].min }
          end

          ranks
        end

        # The master's feats on top: a skill made at least a rank, and a specialization's skills raised.
        def self.granted_ranks(ranks, specials, grants)
          (grants['skills'] || {}).each { |skill, word| ranks[skill] = [ ranks[skill], rank_of(word) ].max }

          held = specials.map { |one, _found| one['name'].to_s }
          (grants['raise_with'] || {}).each do |specialization, skills|
            next unless held.include?(specialization.to_s)

            Array(skills).each { |skill| ranks[skill] = [ ranks[skill] + 1, rank_of('legendary') ].min }
          end

          ranks
        end

        def self.size_of(info, chosen, reached, held)
          sizes = Array(info['sizes'])
          size = sizes.include?(chosen.to_s) ? chosen.to_s : info['size'].to_s

          reached.each do |stage|
            next unless ((held['stages'] || {})[stage] || {})['grow']

            index = SIZES.index(size)
            size = SIZES[index + 1] if index && index <= SIZES.index('Medium')
          end

          size
        end

        def self.traits_of(info, specials)
          traits = Array(info['traits']) + [ 'minion' ]

          specials.each do |one, found|
            traits.concat(Array((found['traits'] || {})[one['choice'].to_s]))
          end

          traits.uniq
        end

        def self.hp_of(info, attributes, level, specials)
          hp = info['hp'].to_i + (HP_PER_LEVEL + attributes['Constitution']) * level

          specials.each do |one, found|
            by_level = found['hp']
            next unless by_level.is_a?(Hash)

            reached = by_level.keys.map(&:to_i).select { |at| at <= level }.max
            next unless reached

            hp += by_level[reached] || by_level[reached.to_s]
            hp += found['sanctified'].to_i if (found['weakness'] || {}).key?(one['choice'].to_s)
          end

          hp
        end

        def self.strong_enough?(attributes, armor)
          armor && attributes['Strength'] >= armor['strength'].to_i
        end

        def self.ac_of(attributes, ranks, level, armor)
          return 10 + attributes['Dexterity'] + bonus(ranks['unarmored'], level) unless armor

          dexterity = armor.key?('dex_cap') ? [ attributes['Dexterity'], armor['dex_cap'].to_i ].min : attributes['Dexterity']
          item = [ armor['ac_bonus'].to_i, MAX_ITEM_AC ].min

          10 + dexterity + bonus(ranks['barding'], level) + item
        end

        # The skills it has a rank in, as { name => { 'rank', 'value' } }. Other skills use the attribute
        # alone, and the sheet says so rather than listing them.
        def self.skills_of(ranks, attributes, level, armor)
          penalty = armor && !strong_enough?(attributes, armor) ? armor['check_penalty'].to_i : 0

          SKILLS.select { |name, _attribute| ranks[name].positive? }.to_h do |name, attribute|
            value = bonus(ranks[name], level) + attributes[attribute]
            value += penalty if CHECKED.include?(attribute)

            [ name, { 'rank' => RANKS[ranks[name]], 'value' => value } ]
          end
        end

        def self.attacks_of(info, attributes, ranks, level, reached, held)
          stages = reached.map { |stage| (held['stages'] || {})[stage] || {} }
          dice = stages.map { |stage| stage['dice'] }.compact.max || 1
          extra = stages.map { |stage| stage['damage'] }.compact.max.to_i
          extra *= 2 if stages.any? { |stage| stage['double_damage'] }
          magical = stages.any? { |stage| stage['magical'] }
          specialized = reached.include?('specialized')

          Array(info['attacks']).map do |attack|
            traits = Array(attack['traits'])
            attribute = traits.include?('finesse') ? [ attributes['Strength'], attributes['Dexterity'] ].max : attributes['Strength']
            more = attack['extra']

            { 'name' => attack['name'],
              'bonus' => bonus(ranks['attack'], level) + attribute,
              'dice' => dice,
              'die' => attack['die'],
              'modifier' => attributes['Strength'] + extra,
              'damage_type' => attack['damage_type'],
              'traits' => magical ? traits + [ 'magical' ] : traits,
              'extra' => more ? "#{specialized ? more['specialized_dice'] || more['dice'] : more['dice']}#{more['die']} #{more['damage_type']}" : nil }
          end
        end

        def self.speeds_of(info, specials, attributes, armor, item_bonuses = {})
          speeds = (info['speeds'] || {}).transform_values(&:to_i)
          speeds['land'] += item_bonuses['speed'].to_i if speeds.key?('land')

          specials.each do |one, found|
            speeds['fly'] = [ speeds['fly'].to_i, speeds['land'].to_i ].max if found['fly'] == 'land' && speeds['land']
            chosen = one['choice'].to_s
            speeds[chosen] += found['speed_bonus'].to_i if found['speed_bonus'] && speeds.key?(chosen)
          end

          return speeds unless armor

          penalty = armor['speed_penalty'].to_i
          penalty = [ penalty + 5, 0 ].min if strong_enough?(attributes, armor)

          speeds.transform_values { |value| [ value + penalty, MINIMUM_SPEED ].max }
        end

        def self.weaknesses_of(specials)
          specials.each_with_object({}) do |(one, found), out|
            out.merge!((found['weakness'] || {})[one['choice'].to_s] || {})
          end
        end
      end
    end
  end
end
