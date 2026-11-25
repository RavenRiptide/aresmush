module AresMUSH
  module Pf2e
    module Familiar

      # Phase Familiar (witch hex, focus 1, reaction; Player Core): when the familiar would take damage, its
      # master recalls it partly to the ether, and against that damage it has resistance 5 to all damage (2
      # more for each rank above 1) and immunity to precision damage. `Spell Effect: Phase Familiar` carries
      # both.
      #
      # Answered after the hit, as Lifelink and Shield Block are. A hit on a familiar whose master knows the
      # hex is kept on the familiar: both standings before and after it, and its damage as rolled, before any
      # resistance. Casting the hex puts both standings back - undoing Blood Link where the hit set it off -
      # puts the effect on the familiar at the spell's rank, deals the kept damage again through the usual
      # resistances (so the familiar's own and the spell's don't stack), and takes the effect off. It is a hex,
      # so a patron's rider follows as for any other.
      module Phase

        SPELL = 'Phase Familiar'.freeze
        EFFECT = 'Spell Effect: Phase Familiar'.freeze
        KEY = 'phased'.freeze

        def self.spell?(name)
          name.to_s.strip.casecmp?(SPELL)
        end

        # What a hit can put back: nil unless the holder is a familiar whose master knows the hex.
        def self.before(holder)
          # The hit dealt again by the hex itself is not offered again.
          return nil if Thread.current[KEY]
          return nil unless Actors.of(holder).minion_kind == 'familiar'

          state = holder.master
          return nil unless state&.magic && knows?(state)

          { 'familiar' => Actors.of(holder).standing, 'master' => Lifelink.master_standing(state) }
        end

        def self.knows?(state)
          Pf2emagic::Entries.all_focus(state.magic).any? { |one| spell?(one) }
        end

        # After the hit: kept, and the master told they may answer it. `rows` are the hit's damage as rolled.
        def self.remember(whom, before, rows, critical, out)
          npc = whom.holder.class[whom.holder.id]
          state = npc.master

          TurnState.write(npc, KEY => { 'before' => before['familiar'], 'rows' => rows, 'critical' => critical,
                                        'after' => Actors.of(npc).standing,
                                        'master_before' => before['master'], 'master_after' => Lifelink.master_standing(state) })

          master = Combatants.turn_name(npc.encounter, whom.label)
          out['lines'] << Telling.event('pf2e.familiar_phase_offer', :master => master, :name => whom.label)
        end

        # The familiar the caster's hex answers for, and the hit it answers: `[ combatant, npc, hit ]`, or why
        # it can't be cast. Asked before the Focus Point is spent.
        def self.refusal(scene, spell)
          return nil unless spell?(spell) && scene.encounter

          found = answering(scene)
          found.is_a?(Err) ? found : nil
        end

        def self.answering(scene)
          row = Combatants.minions_of(scene.encounter, scene.actor.number).first
          return Err.new(:no_familiar_here, 'pf2e.familiar_phase_absent') unless row

          familiar = Combatants.combatant(row)
          npc = Pf2eNpc[row['npc']]
          hit = TurnState.of(npc)[KEY]
          return Err.new(:nothing_to_phase, 'pf2e.familiar_phase_no_hit', 'name' => familiar.label) unless hit

          late = hit['after'] != Actors.of(npc).standing || hit['master_after'] != Lifelink.master_standing(scene.actor.holder)
          return Err.new(:too_late, 'pf2e.answer_too_late', 'action' => SPELL) if late

          [ familiar, npc, hit ]
        end

        # The hex is cast: the hit again, with the spell's resistance. Answers whether it was answered.
        def self.cast!(scene, rank, out)
          found = answering(scene)
          return false if found.is_a?(Err)

          familiar, npc, hit = found
          state = scene.actor.holder
          # A focus spell is cast at half its caster's level, rounded up.
          rank = [ rank.to_i, (state.pf2_level.to_i + 1) / 2 ].max

          Actors.of(npc).stand_at(*hit['before'])
          if hit['master_after'] != hit['master_before']
            Actors.of(state).stand_at(*hit['master_before']['standing'])
            state.update(:pf2_conditions => hit['master_before']['conditions'])
            out['lines'] << Telling.event('pf2e.familiar_blood_link_undone', :master => scene.actor.label)
          end

          effect = ActiveEffects.apply(npc, EFFECT, :options => [ "rank #{rank}" ], :applied_by => scene.actor.label,
                                                    :encounter => scene.encounter).state
          out['lines'] << Telling.event('pf2e.familiar_phase_taken', :name => familiar.label, :resistance => resistance(rank))

          # Read again, so the hit is dealt to the familiar as it now stands, with the effect among its sources.
          familiar = Combatants.find(scene.encounter, familiar.label).state

          begin
            Thread.current[KEY] = true
            Acting.deal(Acting::Scene.new(scene.encounter, nil, familiar, scene.enactor, true), familiar, hit['rows'], out,
                        :critical => hit['critical'])
          ensure
            Thread.current[KEY] = nil
          end

          ActiveEffects.remove(Pf2eNpc[npc.id], effect) if effect
          TurnState.write(Pf2eNpc[npc.id], KEY => nil)
          true
        end

        # Resistance 5 at rank 1, and 2 more for each rank above it.
        def self.resistance(rank)
          2 * [ rank.to_i, 1 ].max + 3
        end
      end
    end
  end
end
