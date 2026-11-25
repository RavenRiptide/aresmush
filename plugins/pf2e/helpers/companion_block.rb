module AresMUSH
  module Pf2e
    module Companion

      # An animal companion in an encounter as a stat block, the shape `Npcs` reads off a creature, so its
      # Strikes, multiple attack penalty, conditions, effects, damage and healing go through the creature code.
      # The figures are `Companion.stats` for its master's approved companion, at their level and with what it
      # wears, worked out again each time the record loads. Unlike a familiar's, its AC, saves and attacks are
      # its own, not its master's.
      module Block

        SAVES = { 'fortitude' => 'Fortitude', 'reflex' => 'Reflex', 'will' => 'Will' }.freeze

        # Empty when its master no longer has an approved companion.
        def self.of(npc)
          char = npc.master&.character
          companion = char ? Companion.main(char) : nil
          stats = companion && Companion.approved?(char, companion) ? Companion.stats(char, companion, :draft => false) : nil
          return {} unless stats

          raging = Maneuvers.raging?(npc)
          strikes = stats['attacks'].map { |attack| strike(attack, raging ? Maneuvers::RAGE_DAMAGE[attack['name']].to_i : 0) }

          { 'name' => npc.name,
            'companion' => true,
            'type' => stats['type'],
            'level' => stats['level'],
            'size' => stats['size'],
            'traits' => stats['traits'],
            'hp' => stats['hp'],
            'ac' => stats['ac'],
            'perception' => stats['perception'],
            'saves' => SAVES.to_h { |key, save| [ key, stats['saves'][save] ] },
            'abilities' => stats['attributes'].to_h { |attribute, value| [ Domains.abbreviation(attribute), value ] },
            # Only what it is trained in: a skill a stat block leaves out is read as its attribute, which is
            # what an untrained companion's skill is.
            'skills' => stats['skills'].to_h { |skill, held| [ skill, held['value'] ] },
            'speeds' => stats['speeds'],
            'senses' => stats['senses'],
            'immunities' => [],
            'resistances' => {},
            'weaknesses' => stats['weaknesses'],
            'support_text' => stats['support'].to_s,
            # Nimble or savage, which doubles its support benefit's dice.
            'advanced' => !stats['maneuver'].nil?,
            'specialized' => Maneuvers.specialized?(stats),
            # The mount special: ridden, it keeps all its Speeds and may move and Support in one turn.
            'mount' => stats['mount'] ? true : false,
            'actions' => [ Support.action(stats), Maneuvers.action(stats, npc.master) ].compact,
            'strikes' => strikes + [ Maneuvers.rock(stats) ].compact,
            'spellcasting' => [] }
        end

        # One of its attacks as a creature's Strike: `Jaws`, +6, `1d8+2 piercing`, with a scorpion's poison or
        # any other additional damage as a second roll. `more` is damage a raging badger adds.
        def self.strike(attack, more = 0)
          modifier = attack['modifier'].to_i + more
          dice = "#{attack['dice']}#{attack['die']}#{modifier.zero? ? '' : format('%+d', modifier)}"
          damage = [ [ dice, attack['damage_type'], nil ] ]
          extra = attack['extra'].to_s.split(' ', 2)
          damage << [ extra[0], extra[1], nil ] if extra.size == 2

          { 'name' => attack['name'], 'bonus' => attack['bonus'], 'traits' => Array(attack['traits']), 'damage' => damage }
        end
      end
    end
  end
end
