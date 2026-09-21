module AresMUSH

  # One change in an encounter's history: what was done, by whom, and the encounter as it stood before and
  # after. `Pf2e::History` writes and replays them.
  class Pf2eEncounterEntry < Ohm::Model
    include ObjectModel

    # Its place in the history, from 1.
    attribute :seq, :type => DataType::Integer

    # What was typed, and who typed it: `Aria: +e/strike #3=longsword`.
    attribute :said

    attribute :before, :type => DataType::Hash, :default => {}
    attribute :after, :type => DataType::Hash, :default => {}

    reference :encounter, "AresMUSH::PF2Encounter"

    index :encounter_id
  end
end
