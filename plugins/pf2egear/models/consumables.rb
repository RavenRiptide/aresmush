module AresMUSH
  class PF2Consumable < Ohm::Model
    include ObjectModel

    attribute :name
    attribute :bulk, :type => DataType::Float, :default => 0
    attribute :traits, :type => DataType::Array, :default => []
    attribute :level, :type => DataType::Integer, :default => 0
    attribute :price, :type => DataType::Integer, :default => 0
    attribute :quantity, :type => DataType::Integer, :default => 1
    attribute :use, :type => DataType::Hash, :default => {}

    reference :character, "AresMUSH::Character"
    # An encounter's copy of a character's item, taken as they entered it: the encounter reads and changes
    # this, never the item itself. `copied_from` is the character's own item.
    reference :state, "AresMUSH::Pf2eCombatantState"
    attribute :copied_from
    reference :bag, "AresMUSH::PF2Bag"

  end
end
