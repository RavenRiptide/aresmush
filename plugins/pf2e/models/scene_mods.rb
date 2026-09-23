module AresMUSH
  
  class Scene < Ohm::Model

    # Deleted with it: see `on_delete`.
    collection :encounters, "AresMUSH::PF2Encounter"

  end
end
