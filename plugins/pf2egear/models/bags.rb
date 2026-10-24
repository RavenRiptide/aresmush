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
    # An encounter's copy of a character's item, taken as they entered it: the encounter reads and changes
    # this, never the item itself. `copied_from` is the character's own item.
    reference :state, "AresMUSH::Pf2eCombatantState"
    attribute :copied_from

    # What made it, where a character did not simply have it - `loot`, `advanced alchemy`, `crafting` - and
    # how long it lasts: `encounter` for what goes when the encounter that made it does, `rest` for what
    # lasts until the next daily preparations. Nothing means it is theirs to keep (`Pf2e::Equipment`).
    attribute :granted_by
    attribute :expires
    collection :weapons, "AresMUSH::PF2Weapon", :bag
    collection :armor, "AresMUSH::PF2Armor", :bag
    collection :shields, "AresMUSH::PF2Shield", :bag
    collection :magicitem, "AresMUSH::PF2MagicItem", :bag
    collection :gear, "AresMUSH::PF2Gear", :bag
    collection :consumables, "AresMUSH::PF2Consumable", :bag

  end
end
