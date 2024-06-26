module AresMUSH
  module Pf2e

    def self.is_valid_init_stat?(stat)

      abilities = [ 'Strength', 'Dexterity', 'Constitution', 'Intelligence', 'Wisdom', 'Charisma' ]
      skills = Global.read_config('pf2e_skills').keys
      combat_stats = ['Perception']

      valid_init_stat = abilities + skills + combat_stats

      # Is there a unique match? Error if no match or multiple matches

      usable_init_stat = valid_init_stat.select { |s| s.match? stat }

      return false unless usable_init_stat.size == 1
      return true
    end

    def self.can_join_encounter(char, encounter)

      encounter_is_active = encounter.is_active

      return "Not an active encounter" unless encounter_is_active

      is_organizer = PF2Encounter.is_organizer?(char, encounter)

      return "You are the organizer" if is_organizer

      active_encounter = PF2Encounter.in_active_encounter? char

      return "In another encounter" if active_encounter

      scene = encounter.scene
      is_participant = scene.participants.include? char

      return "Not a scene participant" unless is_participant
      return nil
    end

    def self.can_damage_pc?(char, target_list, encounter=nil)

      return true if char.has_permission?('kill_pc')

      encounter = PF2Encounter[encounter]

      return false unless encounter

      participants = encounter.participants.collect { |p| p[1] }
      targets_in_encounter = target_list.all? { |t| participants.include? t }

      PF2Encounter.is_organizer?(char, encounter) && targets_in_encounter
    end

    def self.can_modify_encounter(char, encounter)
      # Enactor needs to be the organizer for the encounter in question.
      return t('pf2e.not_organizer') unless PF2Encounter.is_organizer?(char, encounter)

      # You cannot modify an encounter if its associated scene is completed.
      scene = encounter.scene
      return t('pf2e.encounter_cant_restart', :id => encounter.id, :reason => "Scene not running") if (scene.completed)

      # Encounter should not be modifiable if not active.
      return t('pf2e.encounter_already_ended', :id => encounter.id) unless encounter.is_active

      return nil
    end

  end
end
