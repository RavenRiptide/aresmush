module AresMUSH
  class PF2Shield < Ohm::Model
    include ObjectModel

    attribute :name, :default => "Shield"
    attribute :bulk, :type => DataType::Float, :default => 0
    attribute :traits, :type => DataType::Array, :default => []
    attribute :level, :type => DataType::Integer, :default => 1
    attribute :price, :type => DataType::Integer, :default => 0
    attribute :hardness, :type => DataType::Integer, :default => 0
    attribute :hp, :type => DataType::Integer, :default => 0
    attribute :damage, :type => DataType::Integer, :default => 0
    attribute :ac_bonus, :type => DataType::Integer, :default => 0
    attribute :equipped, :type => DataType::Boolean, :default => false
    attribute :nickname

    reference :character, "AresMUSH::Character"
    # An encounter's copy of a character's item, taken as they entered it: the encounter reads and changes
    # this, never the item itself. `copied_from` is the character's own item.
    reference :state, "AresMUSH::Pf2eCombatantState"
    attribute :copied_from
    reference :weapon, "AresMUSH::PF2Weapon"
    reference :bag, "AresMUSH::PF2Bag"

  end
end
