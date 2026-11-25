module AresMUSH
  module Pf2e
    module Familiar

      # Lifelink (Player Core p. 214): when its familiar would be reduced to 0 Hit Points by damage, its
      # master may take all the damage as a reaction, and the familiar takes none.
      #
      # Answered after the hit, as Shield Block is. A hit that drops a familiar whose master has Lifelink
      # today is kept on the familiar - what both had before it, what it dealt, and where both stood after -
      # and the room is told the master may answer. Answering puts the familiar's hit points back, undoes
      # what Blood Link did to the master, and deals the master the damage that landed, untyped, since it
      # was already resisted once. Only hit points are put back, so the hit's other effects still apply.
      module Lifelink

        NAME = 'Lifelink'.freeze
        KEY = 'lifelinked'.freeze

        # What a hit can put back: nil unless the holder is a familiar standing whose master has Lifelink.
        def self.before(holder)
          return nil unless Actors.of(holder).minion_kind == 'familiar' && holder.hp_left.to_i.positive?

          state = holder.master
          return nil unless state && Daily.master_ability?(state, NAME)

          { 'familiar' => Actors.of(holder).standing, 'master' => master_standing(state) }
        end

        def self.master_standing(state)
          { 'standing' => Actors.of(state).standing, 'conditions' => state.pf2_conditions || {} }
        end

        # After the hit: kept, and offered, where it dropped the familiar.
        def self.offer(whom, before, taken, out)
          npc = whom.holder.class[whom.holder.id]
          return unless npc && npc.hp_left.to_i <= 0

          state = npc.master
          TurnState.write(npc, KEY => { 'before' => before['familiar'], 'taken' => taken.to_i,
                                        'after' => Actors.of(npc).standing,
                                        'master_before' => before['master'], 'master_after' => master_standing(state) })

          master = Combatants.turn_name(npc.encounter, whom.label)
          out['lines'] << Telling.event('pf2e.familiar_lifelink_offer', :master => master, :name => whom.label)
        end

        # The master's answer. Answers the report, or why it can't be given.
        def self.take(scene, out)
          holder = scene.actor.holder
          return Err.new(:no_lifelink, 'pf2e.familiar_lifelink_none') unless Daily.master_ability?(holder, NAME)

          row = Combatants.minions_of(scene.encounter, scene.actor.number).first
          return Err.new(:no_familiar_here, 'pf2e.familiar_lifelink_absent') unless row

          familiar = Combatants.combatant(row)
          npc = Pf2eNpc[row['npc']]
          hit = TurnState.of(npc)[KEY]
          return Err.new(:nothing_to_take, 'pf2e.familiar_lifelink_no_hit', 'name' => familiar.label) unless hit

          # The scene's own copy, since spending the reaction afterwards saves through it: a fresh copy's
          # damage would be put back by that save.
          state = holder
          late = hit['after'] != Actors.of(npc).standing || hit['master_after'] != master_standing(state)
          return Err.new(:too_late, 'pf2e.answer_too_late', 'action' => NAME) if late

          Actors.of(npc).stand_at(*hit['before'])
          TurnState.write(npc, KEY => nil)

          linked = hit['master_after'] != hit['master_before']
          if linked
            Actors.of(state).stand_at(*hit['master_before']['standing'])
            state.update(:pf2_conditions => hit['master_before']['conditions'])
          end

          out['lines'] << Telling.event('pf2e.familiar_lifelink_taken', :master => scene.actor.label, :name => familiar.label,
                                                                       :amount => hit['taken'])
          out['lines'] << Telling.event('pf2e.familiar_blood_link_undone', :master => scene.actor.label) if linked

          standing = Acting.still_up(state)
          held = Harm.damage(state, hit['taken'], nil)
          out['gm'] << Telling.event('pf2e.act_hp_left', :target => scene.actor.label, :hp => Harm.hit_points(state))
          Acting.dropped(scene.actor, standing, out, held.merge('encounter' => scene.encounter))

          Ok.new(:state => out)
        end
      end
    end
  end
end
