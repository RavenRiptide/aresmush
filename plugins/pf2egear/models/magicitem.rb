module AresMUSH
  class PF2MagicItem < Ohm::Model
    include ObjectModel

    attribute :name, :default => "Magic Item"
    attribute :nickname
    attribute :bulk, :type => DataType::Float, :default => 0
    attribute :traits, :type => DataType::Array, :default => []
    attribute :level, :type => DataType::Integer, :default => 1
    attribute :price, :type => DataType::Integer, :default => 0
    attribute :use, :type => DataType::Hash, :default => {}
    attribute :invested, :type => DataType::Boolean
    attribute :invest_on_refresh, :type => DataType::Boolean
    attribute :consumable, :type => DataType::Boolean

    reference :character, "AresMUSH::Character"
    # An encounter's copy of a character's item, taken as they entered it: the encounter reads and changes
    # this, never the item itself. `copied_from` is the character's own item.
    reference :state, "AresMUSH::Pf2eCombatantState"
    attribute :copied_from
    reference :bag, "AresMUSH::PF2Bag"

  end
end
