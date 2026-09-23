module AresMUSH
  module Pf2e
    module Encounters

      # Which encounter a command is acting on.
      #
      # The id if one was typed; otherwise the one in the room's scene, or the one a GM away from it runs
      # (`Combatants.encounter_run_by`). Refused if there is none.
      #
      # Whether the character may change it stays in the shell, because `can_modify_encounter` renders
      # its own refusal and an Err carries a locale key rather than a sentence.
      module Finder

        def self.find(enactor, scene, id = nil)
          encounter = id ? PF2Encounter[id] : (PF2Encounter.get_encounter(enactor, scene) || Combatants.encounter_run_by(enactor))

          return Err.new(:bad_id, 'pf2e.bad_id', 'type' => 'encounter') unless encounter

          Ok.new(:state => encounter)
        end
      end
    end
  end
end
