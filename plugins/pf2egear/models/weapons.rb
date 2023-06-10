module AresMUSH
  class PF2Weapon < Ohm::Model
    include ObjectModel

    attribute :name, :default => "Weapon"
    attribute :bulk, :type => DataType::Float, :default => 0
    attribute :traits, :type => DataType::Array, :default => []
    attribute :level, :type => DataType::Integer, :default => 0
    attribute :price, :type => DataType::Integer, :default => 0

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

    reference :character, "AresMUSH::Character"
    reference :shield, "AresMUSH::PF2Shield"
    reference :bag, "AresMUSH::PF2Bag"

  end
end
