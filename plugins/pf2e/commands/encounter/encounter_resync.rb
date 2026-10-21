module AresMUSH
  module Pf2e

    # `+e/resync [<encounter ID>=]<#id or name>`: the GM brings what a character carries in the encounter up
    # to their sheet - what they bought since joining, and their money - keeping what they drew and used
    # there (`Equipment.resync!`). It goes on the encounter's history, so `+e/undo` takes it back.
    class PF2EncounterResyncCmd
      include CommandHandler

      attr_accessor :name, :encounter_id

      def parse_args
        args = trimmed_list_arg(cmd.args, "=")
        args.unshift(nil) unless args[1]

        self.encounter_id = args[0] ? integer_arg(args[0]) : nil
        self.name = args[1]
      end

      def required_args
        [ self.name ]
      end

      def handle
        found = Pf2e::Encounters::Finder.find(enactor, enactor_room.scene, self.encounter_id)

        return if Pf2e::CharState.emit_error!(client, found)

        encounter = found.state
        cannot_modify = Pf2e.can_modify_encounter(enactor, encounter)

        return client.emit_failure(cannot_modify) if cannot_modify

        found = Pf2e::Combatants.find(encounter, self.name)

        return if Pf2e::CharState.emit_error!(client, found)
        return client.emit_failure(t('pf2e.encounter_sheet_creature', :ref => found.state.ref)) if found.state.creature?

        Equipment.resync!(found.state.holder, Actors.of(found.state.holder).person)

        Pf2e::Encounters::Announce.tell(encounter, t('pf2e.encounter_resync_ok', :gm => enactor.name, :name => found.state.label),
                                        :room => enactor_room)
      end
    end
  end
end
