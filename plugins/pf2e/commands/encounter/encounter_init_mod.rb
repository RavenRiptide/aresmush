module AresMUSH
  module Pf2e

    class PF2InitModCmd
      include CommandHandler

      attr_accessor :encounter_id, :name, :init

      def parse_args
        if cmd.args
          args = trimmed_list_arg(cmd.args, "=")

          # If only two args are given, encounter_id is the nil.
          args.unshift(nil) unless args[2]

          self.encounter_id = args[0] ? integer_arg(args[0]) : nil
          self.name = args[1]
          self.init = integer_arg(args[2])
        end
      end

      def required_args
        [ self.name, self.init ]
      end

      def handle
        # If they didn't specify the encounter ID, go get it.

        scene = enactor_room.scene
        found = Pf2e::Encounters::Finder.find(enactor, scene, self.encounter_id)

        return if Pf2e::CharState.emit_error!(client, found)

        encounter = found.state

        # Verify that this character can modify the encounter.

        cannot_modify = Pf2e.can_modify_encounter(enactor, encounter)
        if cannot_modify
          client.emit_failure cannot_modify
          return
        end

        found = Pf2e::Combatants.find(encounter, self.name)

        return if Pf2e::CharState.emit_error!(client, found)

        Pf2e::Combatants.reroll(encounter, found.state.number, self.init)

        client.emit_success t('pf2e.encounter_mod_ok', :name => found.state.label, :encounter => encounter.id,
                              :init => self.init)

      end


    end
  end
end
