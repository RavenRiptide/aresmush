module AresMUSH
  module Pf2e
    module Familiar

      # Master abilities that add to their master's spellcasting for the day (Player Core p. 212), and
      # Spellcasting's spell:
      #
      #   Cantrip Connection   a prepared caster gains a cantrip slot; a repertoire caster adds a cantrip
      #                        they name, which is remembered on the familiar's record and only staff change
      #   Spell Battery        one slot at least 3 ranks below their highest: the highest such rank
      #   Spellcasting         the familiar casts a spell from their repertoire, or prepared today, at least
      #                        5 ranks below their highest slot, named with the day's picks
      #
      # Nothing is written to their magic record or the ledger: `adjust` adds the day's extras to the
      # entries `Pf2emagic::Entries.for_magic` hands out, so dropping the ability takes them away.
      module MasterSpells

        CANTRIP_CONNECTION = 'Cantrip Connection'.freeze
        SPELL_BATTERY = 'Spell Battery'.freeze
        SPELLCASTING = 'Spellcasting'.freeze

        # Spell Battery's slot is at least this many ranks below the highest.
        BATTERY_BELOW = 3

        # Where a repertoire caster's cantrips are remembered on the familiar's record.
        REMEMBERED = 'cantrips'.freeze

        # ------------------------------------------------------------------------------------------------
        # The entries
        # ------------------------------------------------------------------------------------------------

        # The entries with today's extras added. Asked on every read of anyone's spellcasting, so it reads
        # the raw picks first and goes no further for the many who have neither ability.
        def self.adjust(magic, entries)
          char = magic.respond_to?(:character) ? magic.character : nil
          return entries unless char && picked_raw?(char)

          picks = Daily.master_ability?(char, CANTRIP_CONNECTION) || Daily.master_ability?(char, SPELL_BATTERY) ? Daily.today(char) : []
          return entries if picks.empty?

          connections = picks.select { |one| one['name'] == CANTRIP_CONNECTION }
          battery = picks.any? { |one| one['name'] == SPELL_BATTERY }

          cantrip_entry = cantrip_entry(entries)
          battery_entry = battery ? battery_entry(entries) : nil

          entries.map do |entry|
            changed = entry
            changed = connect(changed, connections) if entry.equal?(cantrip_entry) && connections.any?
            changed = charge(changed) if entry.equal?(battery_entry)
            changed
          end
        end

        def self.picked_raw?(char)
          pick = (char.pf2_daily_choices || {})[Daily::SWITCH]
          return false unless pick.is_a?(Hash)

          Array(pick['abilities']).any? { |one| [ CANTRIP_CONNECTION, SPELL_BATTERY ].include?(one['name']) }
        end

        # A prepared caster's cantrip slots, or a repertoire caster's cantrips.
        def self.connect(entry, connections)
          if entry['category'].to_s == 'prepared'
            slots = (entry['slots'] || {}).merge('cantrip' => (entry['slots'] || {})['cantrip'].to_i + connections.size)
            return entry.merge('slots' => slots)
          end

          named = connections.filter_map { |one| one['choice'].presence }
          known = entry['known'] || {}
          entry.merge('known' => known.merge('cantrip' => (Array(known['cantrip']) + named).uniq))
        end

        def self.charge(entry)
          rank = battery_rank(entry['slots'])
          return entry unless rank

          slots = entry['slots'] || {}
          entry.merge('slots' => slots.merge(rank.to_s => slots[rank.to_s].to_i + 1))
        end

        # Their class's own spellcasting, or the first archetype's when they cast only through one.
        def self.cantrip_entry(entries)
          casting = entries.select { |one| %w{class archetype}.include?(one['source_type']) && %w{prepared spontaneous}.include?(one['category'].to_s) }
          casting.find { |one| one['source_type'] == 'class' } || casting.first
        end

        # The spellcasting with the highest slot rank.
        def self.battery_entry(entries)
          entries.select { |one| %w{class archetype}.include?(one['source_type']) }
                 .max_by { |one| top_rank(one['slots']) }
        end

        def self.top_rank(slots)
          (slots || {}).keys.map(&:to_s).reject { |rank| rank.casecmp?('cantrip') }.map(&:to_i).max.to_i
        end

        # The highest rank at least 3 below their highest: nil below 4th-rank slots, which it needs.
        def self.battery_rank(slots)
          top = top_rank(slots)
          top > BATTERY_BELOW ? top - BATTERY_BELOW : nil
        end

        # ------------------------------------------------------------------------------------------------
        # Cantrip Connection's cantrip, for a repertoire caster
        # ------------------------------------------------------------------------------------------------

        # Their spellcasting that Cantrip Connection adds to, from the entries as stored.
        def self.cantrip_source(char)
          cantrip_entry(Pf2emagic::Entries.for_magic(char.magic))
        end

        def self.repertoire?(char)
          char.magic && cantrip_source(char)&.dig('category').to_s == 'spontaneous'
        end

        def self.remembered(char)
          Array(Familiar.record(char)[REMEMBERED])
        end

        # The cantrips each Cantrip Connection pick adds, in order: what was typed, else the cantrip
        # remembered for that pick. A cantrip typed where another is remembered is refused.
        def self.connections(char, picks)
          held = remembered(char)
          index = 0

          picks.map do |one|
            next one unless one['name'] == CANTRIP_CONNECTION

            kept = held[index]
            index += 1
            typed = one['choice'].to_s.strip

            if typed.empty?
              return Err.new(:familiar_cantrip_needed, 'pf2e.familiar_cantrip_needed', 'list' => cantrip_options(char).join(', ')) unless kept

              next one.merge('choice' => kept)
            end

            if kept && !kept.casecmp?(typed)
              return Err.new(:familiar_cantrip_kept, 'pf2e.familiar_cantrip_kept', 'cantrip' => kept)
            end

            found = cantrip_refusal(char, typed, kept)
            return found if found.err?

            one.merge('choice' => found.state)
          end.then { |done| Ok.new(:state => done) }
        end

        # A cantrip of their tradition they could add to their repertoire and don't already know. One
        # already remembered for this pick is known through it, so it is taken as it is.
        def self.cantrip_refusal(char, typed, kept)
          return Ok.new(:state => kept) if kept

          source = cantrip_source(char)
          checked = Pf2emagic.check_spell(char, source['name'], 'cantrip', typed, true)
          return Err.new(:familiar_cantrip_bad, 'pf2e.familiar_cantrip_bad', 'why' => checked) if checked.is_a?(String)

          name = checked[0]
          if Array((source['known'] || {})['cantrip']).any? { |one| one.to_s.casecmp?(name) }
            return Err.new(:familiar_cantrip_known, 'pf2e.familiar_cantrip_known', 'cantrip' => name)
          end

          Ok.new(:state => name)
        end

        # The cantrips they could name, for a refusal's list.
        def self.cantrip_options(char)
          source = cantrip_source(char)
          return [] unless source

          known = Array((source['known'] || {})['cantrip']).map(&:downcase)
          Pf2emagic.pickable_spells(char, source['name'], 'cantrip').keys.reject { |one| known.include?(one.downcase) }.sort
        end

        # After a pick: the cantrips it named are remembered, in order, for the picks to come. Written
        # through the character the pick was just saved on, so the caller's copy stays current.
        def self.remember!(char, pick)
          named = Array((pick || {})['abilities']).select { |one| one['name'] == CANTRIP_CONNECTION }
                                                  .filter_map { |one| one['choice'].presence }
          held = remembered(char)
          return if named.size <= held.size

          char.update(:pf2_familiar => Familiar.record(char).merge(REMEMBERED => held + named.drop(held.size)))
        end

        # Staff change a remembered cantrip, which stands in for retraining it.
        def self.change!(char, old, new)
          held = remembered(char)
          index = held.index { |one| one.casecmp?(old.to_s) }
          return Err.new(:familiar_cantrip_none, 'pf2e.familiar_cantrip_none', 'cantrip' => old) unless index

          found = cantrip_refusal(char, new, nil)
          return found if found.err?

          changed = held.dup
          changed[index] = found.state
          Character[char.id].update(:pf2_familiar => Familiar.record(char).merge(REMEMBERED => changed))

          picks = DailyChoices.picks(Character[char.id])
          pick = picks[Daily::SWITCH]
          if pick.is_a?(Hash) && Array(pick['abilities']).any? { |one| one['choice'].to_s.casecmp?(held[index]) }
            abilities = pick['abilities'].map { |one| one['name'] == CANTRIP_CONNECTION && one['choice'].to_s.casecmp?(held[index]) ? one.merge('choice' => found.state) : one }
            text = Familiar.abilities_text(abilities)
            Character[char.id].update(:pf2_daily_choices => picks.merge(Daily::SWITCH => pick.merge('abilities' => abilities, 'pick' => text)))
          end

          Ok.new(:state => { 'old' => held[index], 'new' => found.state })
        end

        # ------------------------------------------------------------------------------------------------
        # Spellcasting's spell
        # ------------------------------------------------------------------------------------------------

        # The spells it may name, as [ { 'spell', 'rank', 'source' } ]: in their repertoire, or prepared today,
        # at least 5 ranks below their highest slot. Cantrips aren't among them. Lowest rank first.
        def self.spellcasting_list(holder)
          magic = holder.magic
          return [] unless magic

          top = Choices.top_slot_rank(holder)
          below = (Daily.catalogue[SPELLCASTING] || {}).dig('choice', 'ranks_below').to_i
          highest = top - below
          return [] if highest < 1

          today = magic.spells_today || {}

          Pf2emagic::Entries.casting(magic).flat_map do |entry|
            by_rank = entry['category'].to_s == 'prepared' ? (today[entry['name']] || {}) : (entry['known'] || {})

            by_rank.select { |rank, _spells| rank.to_s.match?(/\A\d+\z/) && rank.to_i.between?(1, highest) }.flat_map do |rank, spells|
              Array(spells).map(&:to_s).reject { |one| one.empty? || one.casecmp?(Pf2emagic::Entries::OPEN) }
                           .map { |one| { 'spell' => one, 'rank' => rank.to_i, 'source' => entry['name'] } }
            end
          end.sort_by { |one| one['rank'] }
        end

        def self.spellcasting_options(char)
          spellcasting_list(char).map { |one| one['spell'] }.uniq.sort
        end

        # The spell picked for it today, or nil.
        def self.spellcasting_spell(holder)
          Daily.today(holder).find { |one| one['name'] == SPELLCASTING }&.dig('choice').presence
        end

        # Today's spell as they can still cast it - { 'spell', 'rank', 'source' } - or nil where it is no
        # longer in their repertoire or prepared.
        def self.spellcasting_today(holder)
          spell = spellcasting_spell(holder)
          return nil unless spell && Familiar.approved?(holder)

          spellcasting_list(holder).find { |one| one['spell'].casecmp?(spell) }
        end

        # The familiar's stat block entry for it: its master's tradition, spell DC and spell attack for the
        # spellcasting it comes from, as they stand in the encounter, and the spell once at its rank.
        def self.block_entry(state)
          found = spellcasting_today(state)
          return nil unless found

          stats = Pf2emagic.get_caster_stats(state, found['source'])
          return nil unless stats.is_a?(Hash)

          { 'name' => SPELLCASTING, 'tradition' => stats['tradition'], 'type' => 'innate',
            'dc' => Acting.spell_figure(state, 'spell_dc', stats), 'attack' => Acting.spell_figure(state, 'spell_attack', stats),
            'spells' => { found['rank'].to_s => [ found['spell'] ] }, 'uses' => { found['spell'] => 1 } }
        end

        # ------------------------------------------------------------------------------------------------
        # The familiar casting it
        # ------------------------------------------------------------------------------------------------

        # What a player's familiar may not cast: anything but today's spell, a spell no longer theirs, or a
        # second casting today. The day's casting is counted on its master's encounter state.
        def self.cast_refusal(npc, label, spell)
          state = npc.master
          chosen = state ? spellcasting_spell(state) : nil
          return Err.new(:familiar_no_spell, 'pf2e.familiar_cast_none', 'name' => label) unless chosen
          unless chosen.casecmp?(Npcs.spell_base(spell.to_s))
            return Err.new(:familiar_other_spell, 'pf2e.familiar_cast_only', 'name' => label, 'spell' => chosen)
          end
          return Err.new(:familiar_spell_gone, 'pf2e.familiar_cast_gone', 'spell' => chosen) unless spellcasting_today(state)

          return nil unless TurnState.used(state, SPELLCASTING).positive?

          Err.new(:familiar_cast_used, 'pf2e.familiar_action_used', 'name' => label, 'action' => SPELLCASTING)
        end

        # After a cast: a familiar casting today's spell spends its master's casting for the day, and the room
        # is reminded that a drawback falls on both.
        def self.cast!(scene, spell, out)
          holder = scene.actor.holder
          state = Actors.of(holder).minion_kind == 'familiar' ? holder.master : nil
          chosen = state ? spellcasting_spell(state) : nil
          return unless chosen && chosen.casecmp?(spell.to_s)

          TurnState.count_use(state, SPELLCASTING, 'day')
          out['lines'] << Telling.event('pf2e.familiar_cast_drawback', :name => scene.actor.label,
                                                                       :master => Combatants.turn_name(scene.encounter, scene.actor.label))
        end
      end
    end
  end
end
