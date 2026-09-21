module AresMUSH
  class PF2Encounter < Ohm::Model
    include ObjectModel

    attribute :name
    # The initiative order, one row per combatant; `Pf2e::Combatants` reads and writes it.
    attribute :participants, :type => DataType::Array, :default => []
    attribute :next_init, :type => DataType::Integer, :default => 0
    attribute :organizer
    attribute :is_active, :type => DataType::Boolean, :default => true
    attribute :round, :type => DataType::Integer, :default => 0
    attribute :current
    attribute :messages, :type => DataType::Array, :default => []
    attribute :init_stat

    # The last combatant id given. An id is never reused within an encounter, so `#2` means the same
    # creature all fight long.
    attribute :last_number, :type => DataType::Integer, :default => 0

    # Players the GM has trusted with setting cover and concealment, for this encounter only.
    attribute :trusted, :type => DataType::Array, :default => []

    # A target's cover and concealment, by its id: `{ '3' => 'standard' }`.
    attribute :cover, :type => DataType::Hash, :default => {}
    attribute :concealment, :type => DataType::Hash, :default => {}

    set :characters, "AresMUSH::Character"
    reference :scene, "AresMUSH::Scene"
    collection :npcs, "AresMUSH::Pf2eNpc", :encounter

    before_delete :delete_npcs

    def delete_npcs
      self.npcs.each { |npc| npc.delete }
    end

    ##### CLASS METHODS #####

    def self.in_active_encounter?(char)
      char.encounters.any? { |e| e.is_active }
    end

    def self.scene_active_encounter(scene)
      scene.encounters.select { |e| e.is_active }.first
    end

    def self.get_encounter(char, scene=nil)
      return nil unless scene
      scene_active_encounter(scene)
    end

    def self.active_encounters(char)
      char.encounters.select { |e| e.is_active }
    end

    def self.send_to_encounter(enc, msg)
      message_list = enc.messages
      message_list << [ Time.now, msg ]
      enc.update(messages: message_list)
    end

    def self.is_organizer?(char, encounter)
      char.is_admin? || (char.name == encounter.organizer)
    end

  end
end
