module AresMUSH
  module Pf2e

    # The statistic initiative is rolled on, by its own name, from what a player typed: Perception, a skill
    # or an ability, in any case, an ability's three letters, or the start of a name only one of them has.
    # Nil when it names none of them, or several.
    def self.initiative_stat(term)
      wanted = term.to_s.strip.downcase

      return nil if wanted.empty?
      return ABILITY_BY_WORD[wanted] if ABILITY_BY_WORD.key?(wanted)

      names = [ 'Perception' ] + ABILITIES + Global.read_config('pf2e_skills').keys
      exact = names.find { |name| name.downcase == wanted }

      return exact if exact

      starting = names.select { |name| name.downcase.start_with?(wanted) }

      starting.size == 1 ? starting.first : nil
    end

    # What a character adds to an initiative roll.
    #
    # Initiative is a check with some other statistic underneath it - Perception unless the scene runner
    # names a skill - so it takes that statistic's bonuses and anything written against `initiative` as
    # well. Foundry composes it the same way, which is what makes Incredible Initiative one row of
    # config rather than a special case here.
    def self.initiative_bonus(char, stat, options = [])
      named = stat.to_s.strip

      return Check.of(char, 'perception', nil, options, [ 'initiative' ]).total if
        named.casecmp?('Perception')

      if Pf2e::ABILITY_BY_WORD.key?(named.downcase)
        return Pf2e.ability_mod(char, Pf2e::ABILITY_BY_WORD[named.downcase])
      end

      kind = Pf2eSkills.lore?(named) ? 'lore' : 'skill'

      Check.of(char, kind, named, options, [ 'initiative' ]).total
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

      participants = Combatants.rows(encounter).map { |row| row['name'] }
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
