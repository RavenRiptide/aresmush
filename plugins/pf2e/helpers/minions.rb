module AresMUSH
  module Pf2e

    # What a familiar and an animal companion share as minions: neither has a turn of its own, so it acts only
    # on its master's turn and only with the actions it has there (`Actor#turn_actions`). Exploration has no
    # turns, so there it needs neither. What each kind may do with its actions is its own (`Familiar::Minion`,
    # `Companion::Minion`).
    module Minions

      # Outside its master's turn, or with no actions left. `empty_key` is the message for having none, which
      # names the Command its kind needs.
      def self.turn_refusal(encounter, combatant, empty_key)
        return nil if Exploration.exploring?(encounter)

        npc = combatant.holder
        master = Combatants.turn_name(encounter, combatant.label)

        if ActiveEffects.current_turn(encounter) != master
          return Err.new(:not_master_turn, 'pf2e.minion_not_master_turn', 'name' => combatant.label, 'master' => master)
        end

        return nil if TurnState.turn(npc)['actions'].to_i < TurnState.actions(npc)

        Err.new(:not_commanded, empty_key, 'name' => combatant.label, 'ref' => combatant.ref)
      end
    end
  end
end
