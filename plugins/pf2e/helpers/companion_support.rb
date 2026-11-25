module AresMUSH
  module Pf2e
    module Companion

      # An animal companion's Support (Player Core p. 206): 1 of its actions, after which its master has its
      # type's support benefit until the start of their next turn, and it may use only basic move actions that
      # turn. If it has already used any other action that turn, it can't Support.
      #
      # A benefit reaches a creature "in the companion's reach", which an encounter without a map can't see, so
      # the master says so on the Strike with the word `support`, as they say `flanking`. What the engine can do
      # with a hit it does (`BENEFITS`); a benefit about where creatures stand, or their reactions, is told.
      module Support

        NAME = 'Support'.freeze
        EFFECT = 'Effect: Companion Support'.freeze
        WORD = 'support'.freeze

        # The basic actions with the move trait, and the specialty ones a Speed allows.
        MOVES = %w{Crawl Leap Step Stride Burrow Fly Swim}.freeze

        # What a supported hit does, by type. `dice` doubles for a nimble or savage companion.
        #
        #   damage      rolled separately, from the companion, on any hit; `struck` limits it to a Strike
        #               that dealt one of those types
        #   persistent  added to a hit that damages, doubled on a critical hit as the Strike's own is
        #   condition   left on a creature the hit damages, as an action's consequence is
        #   effect      put on a creature the hit damages, `critical` on a critical hit
        #   dazzled     Dazzled until the persistent bleed ends
        #   ridden      only while the striker rides it (`Riding`)
        #   charge      a horse's: its damage bonus is on the Strike itself (`Riding.horse_charge`), told here
        BENEFITS = {
          'Bear' => { 'damage' => 'slashing', 'die' => 'd8' },
          'Riding Drake' => { 'damage' => 'fire', 'die' => 'd4', 'ridden' => true },
          'Horse' => { 'charge' => true },
          'Shark' => { 'damage' => 'slashing', 'die' => 'd8', 'struck' => %w{slashing piercing} },
          'Boar' => { 'persistent' => 'bleed', 'die' => 'd6' },
          'Scorpion' => { 'persistent' => 'poison', 'die' => 'd6' },
          'Bird' => { 'persistent' => 'bleed', 'die' => 'd4', 'dazzled' => true },
          'Ape' => { 'condition' => { 'condition' => 'Frightened', 'value' => 1 } },
          'Cat' => { 'condition' => { 'condition' => 'Off-Guard', 'until' => 'next-turn-end' } },
          'Wolf' => { 'effect' => 'Effect: Wolf Support', 'critical' => 'Effect: Wolf Support (Critical)' }
        }.freeze

        # What marks a Dazzled that lasts until the bleed ends.
        UNTIL_BLEED = 'until_bleed'.freeze

        # Support as one of its own actions, on its stat block.
        def self.action(stats)
          { 'name' => NAME, 'type' => 'action', 'cost' => 1, 'traits' => [], 'text' => stats['support'].to_s }
        end

        # Its row for `MonsterAbilities`: the GM may have it Support whenever, as with anything it does.
        ROW = {
          'refusal' => lambda do |use|
            state = use.actor.holder.master
            state ? nil : Err.new(:support_no_master, 'pf2e.companion_support_no_master', 'name' => use.actor.label)
          end,
          'run' => ->(use) { Support.run(use) }
        }.freeze

        def self.row?(name, holder)
          Domains.slug(name) == Domains.slug(NAME) && holder && Actors.of(holder).minion_kind == 'companion'
        end

        def self.run(use)
          npc = use.actor.holder
          state = npc.master
          master = Combatants.turn_name(use.scene.encounter, use.actor.label)

          ActiveEffects.apply(state, EFFECT, :applied_by => use.actor.label, :encounter => use.scene.encounter)
          TurnState.write(npc, 'turn' => TurnState.turn(npc).merge('supported' => true))

          key = BENEFITS.key?(npc.stat_block['type'].to_s) ? 'pf2e.companion_support_applied' : 'pf2e.companion_support_told'
          use.out['lines'] << Telling.event(key, :name => use.actor.label, :master => master)
          Riding.fell_rider!(use, npc, state)
        end

        def self.supported?(npc)
          TurnState.turn(npc)['supported'] == true
        end

        # The companion Supporting this holder now: their own, here, with the effect on them. Nil otherwise.
        def self.supporting(holder)
          encounter = holder.respond_to?(:encounter) ? holder.encounter : nil
          return nil unless encounter && Array(holder.pf2_effects).any? { |effect| effect.name == EFFECT }

          row = Combatants.rows(encounter).find { |one| one['state'].to_s == holder.id.to_s }
          found = row ? Combatants.minions_of(encounter, row['id'], 'companion').first : nil
          found ? Combatants.holder_of(found) : nil
        end

        # The word said with no companion Supporting the striker.
        def self.word_refusal(scene)
          return nil if supporting(scene.actor.holder)

          Err.new(:not_supported, 'pf2e.companion_support_word_unsupported', 'actor' => scene.actor.label)
        end

        # After a supported Strike hit and its damage was dealt. `rows` are the Strike's damage, `before` the
        # target's standing before it, which says whether the hit damaged them, and `attack` the Strike.
        def self.after_hit(scene, rows, before, critical, out, attack = {})
          npc = supporting(scene.actor.holder)
          benefit = npc ? BENEFITS[npc.stat_block['type'].to_s] : nil
          target = scene.target

          return unless npc
          return out['lines'] << Telling.event('pf2e.companion_support_benefit', :name => npc.name, :text => npc.stat_block['support_text']) unless benefit

          if benefit['charge']
            key = attack['horse_charge'] ? 'pf2e.companion_support_horse' : 'pf2e.companion_support_horse_unmet'
            return out['lines'] << Telling.event(key, :name => npc.name, :amount => attack['horse_charge'])
          end

          if benefit['ridden'] && !Riding.rides?(scene.actor.holder, npc)
            return out['lines'] << Telling.event('pf2e.companion_support_ridden_unmet', :name => npc.name)
          end

          return if Pf2e.dead?(target.holder)

          damaged = Actors.of(target.holder).standing != before
          dice = npc.stat_block['advanced'] ? 2 : 1

          if benefit['damage']
            struck = rows.map { |row| row['type'].to_s }
            if benefit['struck'].nil? || (damaged && (struck & benefit['struck']).any?)
              formula = "#{dice}#{benefit['die']}"
              thrown = Pf2e.thrown_formula(formula)
              out['lines'] << Telling.event('pf2e.companion_support_damage', :name => npc.name)
              Acting.deal(scene, target, [ { 'amount' => thrown['total'], 'type' => benefit['damage'], 'formula' => formula,
                                             'dice' => thrown['shown'] } ], out)
            end
          end

          return unless damaged && !Pf2e.dead?(target.holder)

          if benefit['persistent']
            formula = "#{critical ? dice * 2 : dice}#{benefit['die']}"
            Acting.deal(scene, target, [ { 'formula' => formula, 'type' => benefit['persistent'], 'category' => 'persistent' } ], out)
            dazzle(scene, target, out) if benefit['dazzled']
          end

          Acting.condition_consequence(scene, target, benefit['condition'], out) if benefit['condition']

          if benefit['effect']
            ActiveEffects.apply(target.holder, critical ? benefit['critical'] : benefit['effect'], :applied_by => npc.name,
                                                                                                  :encounter => scene.encounter)
            out['lines'] << Telling.event('pf2e.companion_support_effect', :target => target.label, :name => npc.name,
                                                                         :feet => critical ? 10 : 5)
          end
        end

        # Dazzled until it removes the bleed: marked, and lifted when the bleed ends (`bleed_ended`).
        def self.dazzle(scene, target, out)
          Acting.condition_consequence(scene, target, { 'condition' => 'Dazzled' }, out)
          Acting.note_on(target.holder, 'Dazzled', UNTIL_BLEED => true) if (target.holder.pf2_conditions || {}).key?('Dazzled')
        end

        # The bleed is gone: a Dazzled that lasted until then goes with it.
        def self.bleed_ended(holder)
          held = (holder.pf2_conditions || {})['Dazzled']
          Pf2e.remove_condition(holder, 'Dazzled') if held.is_a?(Hash) && held[UNTIL_BLEED]
        end

        # After Supporting, a player's companion may use only basic move actions that turn; before it, Support
        # needs a turn in which it has used no other action.
        def self.refusal(npc, label, name, verb)
          if name == NAME
            return Err.new(:support_after_action, 'pf2e.companion_support_after_action', 'name' => label) if TurnState.turn(npc)['actions'].to_i.positive?

            return nil
          end

          return nil unless supported?(npc)
          return nil if verb == 'act' && MOVES.include?(name)

          Err.new(:support_moves_only, 'pf2e.companion_support_moves_only', 'name' => label)
        end
      end
    end
  end
end
