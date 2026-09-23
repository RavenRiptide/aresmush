module AresMUSH
  module Pf2e

    # `+e/focus [<encounter id>]` - which encounter a GM's `+e` commands address while they are away from
    # its scene. With no id, it goes back to the only one they run.
    class PF2EncounterFocusCmd
      include CommandHandler

      attr_accessor :encounter_id

      def parse_args
        self.encounter_id = trim_arg(cmd.args)&.delete_prefix('#')
      end

      def handle
        unless self.encounter_id
          enactor.update(:pf2_encounter_focus => nil)
          return client.emit_success(t('pf2e.focus_cleared'))
        end

        encounter = PF2Encounter[self.encounter_id]

        return client.emit_failure(t('pf2e.bad_id', :type => 'encounter')) unless encounter&.is_active
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        enactor.update(:pf2_encounter_focus => encounter.id)
        client.emit_success t('pf2e.focus_set', :id => encounter.id)
      end
    end

    # `+e/owner [<encounter id>=]<character>` - its GM, or staff, hands an encounter to someone else, who
    # runs it from then on.
    class PF2EncounterOwnerCmd
      include CommandHandler

      attr_accessor :encounter_id, :who

      def parse_args
        first, _, second = cmd.args.to_s.partition('=')

        self.encounter_id, self.who = second.strip.empty? ? [ nil, first.strip ] : [ first.strip.delete_prefix('#'), second.strip ]
      end

      def required_args
        [ self.who ]
      end

      def handle
        encounter = self.encounter_id ? PF2Encounter[self.encounter_id] : Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.bad_id', :type => 'encounter')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        char = Character.named(self.who)

        return client.emit_failure(t('pf2e.not_found')) unless char

        PF2Encounter.hand_to(encounter, char)

        message = t('pf2e.owner_handed', :name => enactor.name, :id => encounter.id, :gm => char.name)
        PF2Encounter.send_to_encounter(PF2Encounter[encounter.id], message)
        client.emit_success message
        Login.emit_ooc_if_logged_in(char, message) unless char == enactor
      end
    end
  end
end
