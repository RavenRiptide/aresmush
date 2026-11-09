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

    # The DC a save against it uses where its maker's is higher than its own: an alchemist's class DC,
    # stamped by Powerful Alchemy on what they make. Reads 0 for anything else.
    attribute :dc, :type => DataType::Integer

    # A scroll's spell and the rank it holds it at (`Pf2e::SpellItems`). Nil for anything else.
    attribute :spell
    attribute :spell_rank, :type => DataType::Integer

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
