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

    # What made it, where a character did not simply have it - `loot`, `advanced alchemy`, `crafting` - and
    # how long it lasts: `encounter` for what goes when the encounter that made it does, `rest` for what
    # lasts until the next daily preparations. Nothing means it is theirs to keep (`Pf2e::Equipment`).
    attribute :granted_by
    attribute :expires
    reference :bag, "AresMUSH::PF2Bag"

  end
end
