module AresMUSH

  # The Hero Points held in one scene, by character id (`Pf2e::HeroPoints`). Someone not written here yet
  # holds what a scene starts them with. A scene has one, made when a count first changes, and it goes
  # with the scene.
  class Pf2eHeroPool < Ohm::Model
    include ObjectModel

    attribute :counts, :type => DataType::Hash, :default => {}

    reference :scene, "AresMUSH::Scene"
  end
end
