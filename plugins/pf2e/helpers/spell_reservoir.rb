module AresMUSH
  module Pf2e

    # A spell reservoir rune contains one spell, cast into the weapon over a minute, for its wielder to release
    # through a Strike (GM Core).
    #
    # A caster stores it with `+e/cast <spell>=<wielder>/reservoir` while the party explores: the spell is
    # spent as any casting is, and kept on the weapon instead of taking effect. Channeled Release Strikes with
    # the weapon and empties it; a hit casts the spell at the target, its attack decided by the Strike and its
    # save against DC 30. Safe Release empties it harmlessly. The spell is the weapon's, so what the encounter's
    # copy contains when the encounter ends is what the character's own weapon contains.
    module SpellReservoir

      RELEASE = 'Channeled Release'.freeze
      SAFE = 'Safe Release'.freeze
      WORD = 'reservoir'.freeze
      HIGHEST_RANK = 3
      MOST_ACTIONS = 2
      DC = 30

      def self.storing?(words)
        Array(words).any? { |word| word.to_s.strip.casecmp?(WORD) }
      end

      # The weapon with the rune that someone wields.
      def self.weapon_of(holder)
        RuneActions.carriers(holder, RELEASE).first
      end

      def self.stored(weapon)
        held = weapon&.reservoir

        held.is_a?(Hash) && held['spell'] ? held : nil
      end

      # ------------------------------------------------------------------------------
      # Storing

      # Why the spell can't be stored, asked before it's spent; nil when it can, or when nothing is being
      # stored.
      def self.refusal(scene, spell, targets, words)
        return nil unless storing?(words)
        return Err.new(:fighting, 'pf2e.reservoir_fighting') unless Exploration.exploring?(scene.encounter)
        return Err.new(:one_weapon, 'pf2e.reservoir_one_wielder') if targets.size > 1

        wielder = targets.first || scene.actor
        weapon = weapon_of(wielder.holder)

        return Err.new(:no_reservoir, 'pf2e.reservoir_none', 'target' => wielder.label) unless weapon

        held = stored(weapon)

        return Err.new(:full, 'pf2e.reservoir_full', 'weapon' => weapon.name, 'spell' => held['spell']) if held

        name, mechanics = Acting.spell_mechanics(spell)

        return Err.new(:unknown, 'pf2e.reservoir_unknown', 'spell' => name) unless mechanics

        unfit(name, mechanics, Acting.said(words, false)['rank'])
      end

      # A spell of 3rd rank or lower, cast with 2 actions or fewer, that can target a creature other than its
      # caster.
      def self.unfit(name, mechanics, rank)
        if (rank || mechanics['rank']).to_i > HIGHEST_RANK
          return Err.new(:too_high, 'pf2e.reservoir_too_high', 'spell' => name, 'rank' => HIGHEST_RANK)
        end

        time = mechanics['time'].to_s

        unless time.match?(/\A\d/) && time.to_i <= MOST_ACTIONS && !time.match?(/minute|hour|day/i)
          return Err.new(:too_slow, 'pf2e.reservoir_too_slow', 'spell' => name, 'actions' => MOST_ACTIONS)
        end

        target = mechanics['target'].to_s

        return Err.new(:no_target, 'pf2e.reservoir_no_target', 'spell' => name) if target.empty? || target.match?(/\A(you|self)\b/i)

        nil
      end

      # The spell, spent, kept on the wielder's weapon.
      def self.store(scene, spell, cast, targets, words)
        name, mechanics = Acting.spell_mechanics(spell)
        rank = Acting.spell_rank(scene.actor.holder, name, mechanics, Acting.said(words, false), cast)

        return Err.new(:too_high, 'pf2e.reservoir_too_high', 'spell' => name, 'rank' => HIGHEST_RANK) if rank.to_i > HIGHEST_RANK

        wielder = targets.first || scene.actor
        weapon = weapon_of(wielder.holder)
        weapon.update(:reservoir => { 'spell' => name, 'rank' => rank.to_i, 'caster' => scene.actor.label })

        out = Acting.report
        out['lines'] << Telling.event('pf2e.reservoir_stored', :actor => scene.actor.label, :spell => name, :rank => rank,
                                                              :weapon => weapon.name, :target => wielder.label)
        Ok.new(:state => out)
      end

      # ------------------------------------------------------------------------------
      # Releasing

      # A Strike with the weapon, which empties it; a hit casts the spell at the target.
      def self.channel(scene, out)
        weapon = weapon_of(scene.actor.holder)
        held = stored(weapon)

        return Err.new(:empty, 'pf2e.reservoir_empty', 'weapon' => weapon.name) unless held
        return Err.new(:no_target, 'pf2e.act_needs_target') unless scene.target

        struck = Acting.strike(scene, weapon.nickname || weapon.name, [], :spent => false)

        return struck if struck.err?

        out['lines'] << Telling.event('pf2e.act_announced', :actor => scene.actor.label, :action => RELEASE,
                                                           :cost => Actions.cost(RELEASE), :target => Acting.target_phrase(scene))
        merge(out, struck.state)
        weapon.update(:reservoir => {})

        last = TurnState.turn(scene.actor.holder)['last'] || {}

        unless last['hit']
          out['lines'] << Telling.event('pf2e.reservoir_missed', :spell => held['spell'])
          return nil
        end

        cast = Acting.cast(scene, held['spell'], [ scene.target ], [ "rank #{held['rank']}" ],
                           :through => { 'dc' => DC, 'degree' => last['degree'] })

        merge(out, cast.state) if cast.ok?
        nil
      end

      def self.release_safely(scene, out)
        weapon = weapon_of(scene.actor.holder)
        held = stored(weapon)

        return Err.new(:empty, 'pf2e.reservoir_empty', 'weapon' => weapon.name) unless held

        weapon.update(:reservoir => {})
        out['lines'] << Telling.event('pf2e.act_announced', :actor => scene.actor.label, :action => SAFE,
                                                           :cost => Actions.cost(SAFE), :target => '')
        out['lines'] << Telling.event('pf2e.reservoir_emptied', :spell => held['spell'], :weapon => weapon.name)
        nil
      end

      def self.merge(out, other)
        %w{lines gm detail}.each { |part| out[part].concat(Array(other[part])) }
      end

      # ------------------------------------------------------------------------------
      # When the encounter ends

      # What each weapon of theirs contains in the encounter is what their own weapon contains.
      def self.settle!(state)
        char = state.character

        state.weapons.to_a.select(&:copied_from).each do |copy|
          own = PF2Weapon[copy.copied_from]

          next unless own && own.character_id.to_s == char.id.to_s
          next if (own.reservoir || {}) == (copy.reservoir || {})

          own.update(:reservoir => copy.reservoir || {})
        end
      end
    end
  end
end
