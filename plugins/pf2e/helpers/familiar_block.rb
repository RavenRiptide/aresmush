module AresMUSH
  module Pf2e
    module Familiar

      # A familiar in an encounter as a stat block, the shape `Npcs` reads off a creature, so its conditions,
      # effects, damage and healing go through the creature code. The figures are `Familiar::Stats` against
      # its master as they stand in the encounter, so its AC and saves follow theirs (less what a familiar
      # doesn't share), and are worked out again each time the record is loaded.
      module Block

        SAVES = { 'fortitude' => 'Fortitude', 'reflex' => 'Reflex', 'will' => 'Will' }.freeze

        # Empty when its master no longer has an approved familiar.
        def self.of(npc)
          state = npc.master
          stats = state&.character ? stats_of(state) : nil
          return {} unless stats

          specific = Familiar.approved_record(state)['specific'].presence

          { 'name' => npc.name,
            'familiar' => true,
            'pet' => Choices.plain_pet?(state),
            'specific' => specific,
            'familiar_abilities' => Daily.abilities_today(state).map { |one| one['name'].to_s }.uniq,
            'level' => stats['level'],
            'size' => stats['size'],
            'traits' => stats['traits'],
            'hp' => stats['hp'],
            'ac' => stats['ac'],
            'perception' => stats['perception'],
            'saves' => SAVES.to_h { |key, save| [ key, stats['saves'][save] ] },
            'skills' => skills(stats),
            'abilities' => {},
            'speeds' => stats['speeds'],
            'senses' => stats['senses'],
            'immunities' => stats['immunities'],
            'resistances' => listed(stats['resistances']),
            'weaknesses' => listed(stats['weaknesses']),
            'actions' => actions(npc, state, specific),
            'strikes' => [],
            'spellcasting' => [ MasterSpells.block_entry(state) ].compact }
        end

        # A specific familiar's own actions, with its name and its master's DC written in, and the actions
        # its master's abilities today give it (Familiar Focus, Restorative Familiar).
        def self.actions(npc, state, specific)
          listed = Array(Stats.specific_config(specific)['actions'])
          own = []

          unless listed.empty?
            # Filled by name, since the text's `%r` line breaks are no format directives.
            fills = { '%{name}' => npc.name.to_s, '%{dc}' => master_dc(state).to_s }
            own = listed.map { |one| one.merge('text' => one['text'].to_s.gsub(/%\{(?:name|dc)\}/, fills)) }
          end

          own + MasterActions.actions(state)
        end

        # The higher of its master's class DC and their best spell DC, as they stand in the encounter.
        def self.master_dc(state)
          class_dc = state.combat ? Stat.total(state, 'class_dc').to_i : 0
          entries = state.magic ? Pf2emagic::Entries.casting(state.magic) : []
          spell_dcs = entries.filter_map do |entry|
            stats = Pf2emagic.get_caster_stats(state, entry['name'])
            stats.is_a?(Hash) ? Acting.spell_figure(state, 'spell_dc', stats) : nil
          end

          ([ class_dc ] + spell_dcs).max
        end

        def self.stats_of(state)
          approved = Familiar.approved_record(state)
          return nil unless approved

          Stats.of(state, Daily.abilities_today(state), :form => approved['form'].presence || 'land',
                   :specific => approved['specific'], :options => Daily.options(state))
        end

        # Every skill, since one a stat block leaves out would be read as an attribute: a familiar's other
        # skills are its level.
        def self.skills(stats)
          (Global.read_config('pf2e_skills') || {}).keys.to_h do |skill|
            [ skill, stats['skills'].fetch(skill, stats['other_skills']) ]
          end
        end

        def self.listed(entries)
          Array(entries).to_h { |one| [ one['type'], one['value'] ] }
        end
      end
    end
  end
end
