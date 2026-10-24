module AresMUSH
  
  class Scene < Ohm::Model

    # Deleted with it: see `on_delete`.
    collection :encounters, "AresMUSH::PF2Encounter"
    collection :hero_pools, "AresMUSH::Pf2eHeroPool"

  end
end
