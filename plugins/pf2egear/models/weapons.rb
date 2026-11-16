module AresMUSH
  class PF2Weapon < Ohm::Model
    include ObjectModel

    attribute :name, :default => "Weapon"
    attribute :bulk, :type => DataType::Float, :default => 0
    attribute :traits, :type => DataType::Array, :default => []
    attribute :level, :type => DataType::Integer, :default => 0
    attribute :price, :type => DataType::Integer, :default => 0
    # The precious material it's made of, chosen when it's bought and never changed: `{ 'name' => 'Cold Iron',
    # 'grade' => 'standard' }`, or empty for an ordinary item (`Pf2egear::Materials`).
    attribute :material, :type => DataType::Hash, :default => {}

    attribute :talisman, :type => DataType::Array, :default => []
    attribute :nickname
    attribute :wp_damage, :default => "0"
    attribute :wp_damage_2h
    attribute :wp_damage_type, :default => "B"
    attribute :wp_type, :default => ""
    attribute :category, :default => ""
    attribute :range, :type => DataType::Integer, :default => 0
    attribute :reload, :type => DataType::Integer, :default => 0
    attribute :hands, :type => DataType::Integer, :default => 1
    attribute :group, :default => ""
    attribute :runes, :type => DataType::Hash, :default => { 'fundamental' => {}, 'property' => {} }
    attribute :equipped, :type => DataType::Boolean, :default => false
    attribute :invested, :type => DataType::Boolean, :default => false    
    attribute :invest_on_refresh, :type => DataType::Boolean
    attribute :use, :type => DataType::Hash, :default => {}

    # An injury poison on it, waiting for the first Strike that hits: `{ 'name', 'dc', 'damage', 'by' }`.
    # Empty when there is none. Pf2e::WeaponPoison reads and writes it.
    attribute :poison, :type => DataType::Hash, :default => {}

    # What a class feature handed over, by the feature: a Staff Nexus wizard's makeshift staff
    # (`Pf2e::BoundItems`).
    attribute :bound_to

    # A staff's charges left today, on the encounter's copy of it. Its preparer's daily preparations set them
    # (`Pf2e::Staves`).
    attribute :staff_charges, :type => DataType::Integer, :default => 0

    # The weapon it was bought as, while a shifting rune has its encounter copy in another shape
    # (`Pf2e::ShiftingRune`). Empty in its own shape.
    attribute :shape_of

    # The spell a spell reservoir rune contains: `{ 'spell', 'rank', 'caster' }`, or empty when it contains none
    # (`Pf2e::SpellReservoir`).
    attribute :reservoir, :type => DataType::Hash, :default => {}

    # An animated rune's weapon set free on its encounter copy: `{ 'target' => the combatant's number }` while
    # it fights on its own, `{ 'rested_until' => a round }` after it falls (`Pf2e::AnimatedRune`).
    attribute :animated, :type => DataType::Hash, :default => {}

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
    reference :shield, "AresMUSH::PF2Shield"
    reference :bag, "AresMUSH::PF2Bag"

  end
end
