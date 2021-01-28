module AresMUSH
  module Pf2e
    class Pf2eSheet < Ohm::Model
      include ObjectModel

      attribute :pf2_base_info, :type => DataType::Hash, :default => {ancestry:"", heritage:"", background:"", charclass:"", specialize: ""}
      attribute :pf2_level, :type => DataType::Integer, :default => 1
      attribute :pf2_xp, :type => DataType::Integer, :default => 0
      attribute :pf2_conditions, :type => DataType::Hash, :default => {}
      attribute :pf2_feats, :type => DataType::Array, :default => []
      attribute :pf2_features, :type => DataType::Array, :default => []
      attribute :pf2_skills, :type => DataType::Hash, :default => {}
      attribute :pf2_traits, :type => DataType::Array, :default => []
      attribute :pf2_faith, :type => DataType::Hash, :default => { faith: "", deity: "" }
      attribute :pf2_special, :type => DataType::Array, :default => []


      reference :char, "AresMUSH::Character"
      reference :abilities, "AresMUSH::Pf2e::Pf2eAbilities"

      before_delete :delete_subsheet

      def delete_subsheet
        self.abilities.delete
      end

    end

    class Pf2eAbilities < Ohm::Model
      include ObjectModel

      attribute :strength, :type => DataType::Hash, :default => { base_val: 10, mod_val: false }
      attribute :dexterity, :type => DataType::Hash, :default => { base_val: 10, mod_val: false }
      attribute :constitution, :type => DataType::Hash, :default => { base_val: 10, mod_val: false }
      attribute :intelligence, :type => DataType::Hash, :default => { base_val: 10, mod_val: false }
      attribute :wisdom, :type => DataType::Hash, :default => { base_val: 10, mod_val: false }
      attribute :charisma, :type => DataType::Hash, :default => { base_val: 10, mod_val: false }

      attribute :open_boosts, :type => DataType::Integer, :default => 4
      attribute :working_boosts, :type => DataType::Hash, :default => { "Strength"=>0, "Dexterity"=>0, "Constitution"=>0, "Intelligence"=>0, "Wisdom"=>0, "Charisma"=>0 }

      reference :pf2sheet, "AresMUSH::Pf2e::Pf2eSheet"
    end

  end

  class Character
    attribute :baseinfo_locked, :type => DataType::Boolean

    reference :pf2sheet, "AresMUSH::Pf2e::Pf2eSheet"

    before_delete :delete_pf2sheet

    def delete_pf2sheet
      self.pf2sheet.delete
    end

  end
end