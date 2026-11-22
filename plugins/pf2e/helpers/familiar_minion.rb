module AresMUSH
  module Pf2e
    module Familiar

      # A familiar acting in an encounter (Player Core p. 212, and the minion trait). It has no turn of its
      # own: it acts in its master's, with the 2 actions Command a Minion gives it, or the 1 action Independent
      # gives it without a command. It has no reactions, makes no attacks but Escape and Force Open, and
      # performs manipulate actions only with Manual Dexterity.
      #
      # The GM may have it do anything. A player is refused what the rules don't let it do.
      module Minion

        COMMAND = 'Command a Minion'.freeze
        COMMANDED = 2
        INDEPENDENT = 'Independent'.freeze
        MANUAL_DEXTERITY = 'Manual Dexterity'.freeze
        ATTACKS_ALLOWED = [ 'Escape', 'Force Open' ].freeze

        def self.abilities(npc)
          Array(npc.stat_block['familiar_abilities'])
        end

        def self.commanded?(npc)
          TurnState.turn(npc)['commanded'] == true
        end

        # The actions its turn holds: 2 when Commanded, or as if Commanded while Blood Link and its master
        # being unconscious and dying say so; 1 with Independent; none otherwise.
        def self.turn_actions(npc)
          return COMMANDED if commanded?(npc) || acts_for_dying_master?(npc)

          abilities(npc).include?(INDEPENDENT) ? 1 : 0
        end

        # ------------------------------------------------------------------------------------------------
        # Blood Link (a homunculus)
        # ------------------------------------------------------------------------------------------------

        def self.blood_link(npc)
          Stats.specific_config(npc.stat_block['specific'])['blood_link']
        end

        def self.acts_for_dying_master?(npc)
          state = npc.master
          return false unless state && blood_link(npc)

          held = Pf2e.held_conditions(state)
          held.key?('Unconscious') && Pf2e.condition_level(state, 'Dying').positive?
        end

        # It was destroyed: its master takes the mental damage Blood Link deals, and may fall from it.
        def self.destroyed!(npc, out)
          formula = blood_link(npc)
          state = npc.master
          encounter = npc.encounter
          return unless formula && state && encounter

          row = Combatants.rows(encounter).find { |one| one['state'].to_s == state.id.to_s }
          return unless row

          master = Combatants.combatant(row)
          thrown = Pf2e.thrown_formula(formula)
          standing = Acting.still_up(state)
          held = Actors.of(state).damage(thrown['total'], 'mental')
          Actors.of(state).notify_damage(held['amount'], npc.name, IWR.told(held['applied']))

          out['lines'] << Telling.event('pf2e.familiar_blood_link', :name => npc.name, :master => master.label,
                                                                    :amount => held['amount'], :dice => thrown['shown'])
          Acting.dropped(master, standing, out, held.merge('encounter' => encounter))
        end

        def self.command!(npc)
          TurnState.write(npc, 'turn' => TurnState.turn(npc).merge('commanded' => true))
        end

        # Command a Minion reaches only the actor's own familiar.
        def self.command_refusal(encounter, actor, targets)
          return Err.new(:command_whom, 'pf2e.familiar_command_whom') if targets.size != 1

          target = targets.first
          return nil if encounter && target.minion? && target.master.to_i == actor.number.to_i

          Err.new(:not_your_familiar, 'pf2e.familiar_command_not_yours', 'target' => target.label)
        end

        # What a player may not have it do: act outside their turn or without the actions a command gave it,
        # attack, or manipulate without Manual Dexterity. `term` is the action as typed.
        #
        # Exploration has no turns, so there it needs neither its master's turn nor a command.
        def self.player_refusal(encounter, combatant, term)
          turn_refusal(encounter, combatant) || action_refusal(combatant.holder, combatant.label, term)
        end

        # Its Spellcasting spell, cast as it may act: on its master's turn with commanded actions, or while
        # exploring. The ability lets it cast, so the manipulate refusal doesn't reach it.
        def self.cast_refusal(encounter, combatant, spell)
          turn_refusal(encounter, combatant) || MasterSpells.cast_refusal(combatant.holder, combatant.label, spell)
        end

        # Outside its master's turn, or without the actions a command gave it. Exploration has no turns.
        def self.turn_refusal(encounter, combatant)
          return nil if Exploration.exploring?(encounter)

          npc = combatant.holder
          master = Combatants.turn_name(encounter, combatant.label)

          if ActiveEffects.current_turn(encounter) != master
            return Err.new(:not_master_turn, 'pf2e.familiar_not_master_turn', 'name' => combatant.label, 'master' => master)
          end

          return nil if TurnState.turn(npc)['actions'].to_i < TurnState.actions(npc)

          Err.new(:not_commanded, 'pf2e.familiar_not_commanded', 'name' => combatant.label, 'ref' => combatant.ref)
        end

        def self.action_refusal(npc, label, term)
          own = Actors.of(npc).own_ability(term.to_s.split('=').first.to_s.strip)
          return own_refusal(npc, label, own) if own

          found = term.to_s.strip.empty? ? nil : Actions.find(term)
          return nil unless found&.ok?

          name = found.state
          traits = Array(Actions.info(name)['traits']).map { |trait| trait.to_s.downcase }

          if traits.include?('attack') && !ATTACKS_ALLOWED.include?(name)
            return Err.new(:familiar_attack, 'pf2e.familiar_no_attacks', 'name' => label, 'action' => name)
          end

          if traits.include?('manipulate') && !abilities(npc).include?(MANUAL_DEXTERITY)
            return Err.new(:familiar_manipulate, 'pf2e.familiar_no_manipulate', 'name' => label, 'action' => name)
          end

          nil
        end

        # One of its own abilities, as often as its words allow: Euphoric Breath once per hour. Its count is
        # its record's, made each time it joins an encounter, so it starts over in the next one.
        def self.own_refusal(npc, label, own)
          frequency = CreatureAbilities.frequency(own['text'])
          return nil unless frequency && TurnState.used(npc, own['name']) >= frequency['max'].to_i

          Err.new(:familiar_spent, 'pf2e.familiar_ability_spent', 'name' => label, 'action' => own['name'],
                  'per' => frequency['per'])
        end
      end
    end
  end
end
