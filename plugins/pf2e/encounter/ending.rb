module AresMUSH
  module Pf2e
    module Encounters

      # An encounter ending, however it ends: its GM ending it, or its scene stopping.
      #
      # Whatever could not outlast the fight ends with it; so do the turn's counts, what may be used once
      # an encounter, a trust given for this fight, and the cover and concealment set on its combatants.
      # Its history is frozen from here. Answers what ended, as events for whoever tells it.
      module Ending
        def self.end!(encounter)
          PF2Encounter[encounter.id].update(:is_active => false)

          ended = ActiveEffects.encounter_ended(encounter)

          Turns.holders(PF2Encounter[encounter.id]).each do |holder|
            TurnState.reset(holder, 'encounter')
            TurnState.write(holder, 'turn' => {})
          end

          PF2Encounter[encounter.id].update(:trusted => [], :cover => {}, :concealment => {})

          ended
        end
      end
    end
  end
end
