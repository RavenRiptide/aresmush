module AresMUSH
  module Pf2e
    module Companion

      # An animal companion coming into an encounter, and leaving it. As a familiar does, it comes only when
      # its player says it is there, since it may have been left behind.
      #
      # It is a creature record with its master's encounter state as `master` and `minion` 'companion', and a
      # row in the order that names its master's row: it is targeted by its id or its name, and acts on its
      # master's turn. In an encounter that carries on from one it was in, it comes in as it left that one.
      module Joining

        # `row` is the master's row in the order.
        def self.check(encounter, char, row)
          companion = Companion.main(char)

          return Err.new(:companion_none, 'pf2e.companion_none', 'char' => char.name) unless companion
          return Err.new(:master_absent, 'pf2e.companion_master_absent', 'char' => char.name) unless row && row['state']
          return Err.new(:companion_untyped, 'pf2e.companion_encounter_untyped', 'char' => char.name) unless companion['type']
          return Err.new(:not_approved, 'pf2e.companion_encounter_unapproved', 'char' => char.name) unless Companion.approved?(char, companion)
          return Err.new(:companion_dead, 'pf2e.companion_encounter_dead', 'char' => char.name) if Companion.dead?(char, companion)

          name = Companion.approved_record(char, companion)['name'].to_s.strip
          return Err.new(:companion_unnamed, 'pf2e.companion_encounter_unnamed', 'char' => char.name) if name.empty?

          if (here = Combatants.minions_of(encounter, row['id'], 'companion').first)
            return Err.new(:already_here, 'pf2e.companion_encounter_here', 'name' => here['name'])
          end

          clash = Combatants.rows(encounter).find { |one| one['name'].to_s.casecmp?(name) }
          return Err.new(:name_clash, 'pf2e.companion_encounter_clash', 'name' => name, 'ref' => "##{clash['id']}") if clash

          Ok.new(:state => name)
        end

        # It takes its master's place in the order, though it has no turn there.
        def self.join!(encounter, char, row)
          check(encounter, char, row).and_then do |name|
            npc = Pf2eNpc.create(:encounter => encounter, :master => Pf2eCombatantState[row['state']], :name => name,
                                 :minion => 'companion', :number => encounter.last_number.to_i + 1)
            carried = carry_on!(encounter, char, npc)
            joined = Combatants.join(encounter, name, row['init'].to_f, :holder => npc, :master => row['id'])
            # A ranger already hunting a prey here shares their hunter's edge with it.
            hunting = HuntPrey.joined!(encounter, char, Pf2eCombatantState[row['state']], npc)

            done = Ok.new(:state => { 'npc' => npc, 'row' => joined })
                     .with_message(carried ? 'pf2e.companion_encounter_joined_carried' : 'pf2e.companion_encounter_joined',
                                   'name' => name, 'char' => char.name, 'ref' => "##{joined['id']}", 'encounter' => encounter.id)
            hunting ? done.with_message('pf2e.hunt_prey_shared_joined', 'name' => name, 'target' => HuntPrey.prey(Pf2eCombatantState[row['state']])) : done
          end
        end

        # It leaves, letting go of anyone it held and throwing anyone riding it, and is gone with whatever it
        # was under.
        def self.leave!(encounter, char, row)
          here = row ? Combatants.minions_of(encounter, row['id'], 'companion').first : nil
          return Err.new(:not_here, 'pf2e.companion_encounter_absent', 'char' => char.name) unless here

          freed = Holding.let_go(encounter, here['name'])
          freed += Combatants.leave(encounter, here['id'])
          Pf2eNpc[here['npc']]&.delete

          Ok.new(:state => { 'freed' => freed })
            .with_message('pf2e.companion_encounter_left', 'name' => here['name'], 'char' => char.name, 'encounter' => encounter.id)
        end

        # Its record in the encounter this one carries on from, if it was there with its master.
        def self.earlier(encounter, char)
          from = encounter.carries_on_from ? PF2Encounter[encounter.carries_on_from] : nil
          state = from ? CombatantStates.of(from, char) : nil
          return nil unless state

          Pf2eNpc.find(:master_id => state.id).to_a.find { |one| Actors.of(one).minion_kind == 'companion' }
        end

        # As it left the earlier encounter: its damage, temporary Hit Points, conditions, persistent damage and
        # effects, as `CombatantStates.carried` does for its master. True when there was one to carry on from.
        def self.carry_on!(encounter, char, npc)
          prior = earlier(encounter, char)
          return false unless prior

          npc.update(:damage => prior.damage, :temp_hp => prior.temp_hp, :pf2_conditions => prior.pf2_conditions || {},
                     :pf2_persistent => prior.pf2_persistent || [], :pf2_is_dead => prior.pf2_is_dead ? true : false)

          prior.pf2_effects.each do |effect|
            own = effect.attributes.except(:character_id, :npc_id, :state_id, :encounter_id)

            Pf2eEffect.create(own.merge(:npc => npc, :encounter => encounter))
          end

          true
        end
      end
    end
  end
end
