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

    # What made it, where a character did not simply have it - `loot`, `advanced alchemy`, `crafting` - and
    # how long it lasts: `encounter` for what goes when the encounter that made it does, `rest` for what
    # lasts until the next daily preparations. Nothing means it is theirs to keep (`Pf2e::Equipment`).
    attribute :granted_by
    attribute :expires
    # The feat a bound item belongs to, which it is usable only while they hold (`Pf2e::BoundItems`).
    attribute :bound_to

    # A wand's spell and the rank it holds it at, and its day (`Pf2e::SpellItems`): whether it has been cast
    # from today, whether it was overcharged today, and whether an overcharge broke it. A rest gives back
    # the first two; only a repair mends the third.
    attribute :spell
    attribute :spell_rank, :type => DataType::Integer
    # A specialty wand's kind - `widening`, `continuation` - which changes the spell as it's cast.
    attribute :specialty
    attribute :used_today, :type => DataType::Boolean
    attribute :overcharged, :type => DataType::Boolean
    attribute :broken, :type => DataType::Boolean
    # How many of the day's activations a bound item has spent: an egalrin feather fan's Wave Fan. A rest
    # gives them back.
    attribute :activations_used, :type => DataType::Integer, :default => 0
    reference :bag, "AresMUSH::PF2Bag"

  end
end
