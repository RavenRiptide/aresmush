module AresMUSH
  class PF2Bag < Ohm::Model
    include ObjectModel

    attribute :name, :default => "Bag"
    attribute :bulk, :type => DataType::Float, :default => 0
    attribute :bulk_bonus, :type => DataType::Float, :default => 0
    attribute :traits, :type => DataType::Array, :default => []
    attribute :level, :type => DataType::Integer, :default => 0
    attribute :price, :type => DataType::Integer, :default => 0
    attribute :capacity, :type => DataType::Integer, :default => 0
    attribute :gear_contents, :type => DataType::Hash, :default => {}
    attribute :nickname

    reference :character, "AresMUSH::Character"
    collection :weapons, "AresMUSH::PF2Weapon", :bag
    collection :armor, "AresMUSH::PF2Armor", :bag
    collection :shields, "AresMUSH::PF2Shield", :bag
    collection :magicitem, "AresMUSH::PF2MagicItem", :bag
    collection :gear, "AresMUSH::PF2Gear", :bag
    collection :consumables, "AresMUSH::PF2Consumable", :bag

  end
end
