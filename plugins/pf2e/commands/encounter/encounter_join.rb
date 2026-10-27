module AresMUSH
  module Pf2e

    class PF2InitJoinCmd
      include CommandHandler

      attr_accessor :encounter_id, :init_stat

      def parse_args
        # Another command that Faraday's argparser doesn't touch, so we roll our own.

        if cmd.args
          args = trimmed_list_arg(cmd.args, "=")

          if args.size >= 2
            self.encounter_id = integer_arg(args[0])
            self.init_stat = trim_arg(args[1])
            # And throw out anything else.
          else
            # If only one option is given, if it translates to a number, interpret as an encounter ID.
            # Otherwise, interpret as an init stat.

            unknown = args[0]

            if (unknown.to_i.to_s == unknown)
              self.encounter_id = integer_arg(unknown)
            else
              self.init_stat = unknown
            end
          end

        end

      end

      def handle
        scene = enactor_room.scene
        found = Pf2e::Encounters::Finder.find(enactor, scene, self.encounter_id)

        return if Pf2e::CharState.emit_error!(client, found)

        encounter = found.state

        # Can the character join this encounter?

        cannot_join = Pf2e.can_join_encounter(enactor, encounter)

        if cannot_join
          client.emit_failure t('pf2e.encounter_cannot_join', :reason => cannot_join, :id => encounter.id)
          return
        end

        # Exploring has no initiative: they are simply there, doing what they say they are doing.
        return join_exploration(encounter) if Pf2e::Exploration.exploring?(encounter)

        # If they specified an init stat, error if invalid, otherwise use the one
        # specified by the organizer.

        init_stat = Pf2e.initiative_stat(self.init_stat || encounter.init_stat)

        unless init_stat
          client.emit_failure t('pf2e.bad_initiative_stat', :stat => self.init_stat || encounter.init_stat)
          return
        end

        # Calculate initiative and add the enactor to the encounter participants list.
        roll = [ "1d20", Pf2e.initiative_bonus(enactor, init_stat).to_s ]

        initiative = Pf2e.parse_roll_string(enactor, roll)['total']

        Pf2e::Combatants.join(encounter, enactor.name, initiative, :holder => enactor)

        # Set management for later use.

        enactor.encounters.add encounter
        encounter.characters.add enactor

        @message = t('pf2e.encounter_joined_ok',
          :roll => initiative,
          :encounter => encounter.id,
          :name => enactor.name
        )

        # To the room, the encounter's log and the scene's, as an OOC line.
        Pf2e::Encounters::Announce.tell(encounter, @message, :room => enactor_room)

      end

      def join_exploration(encounter)
        Pf2e::Combatants.join(encounter, enactor.name, 0, :holder => enactor)
        enactor.encounters.add encounter
        encounter.characters.add enactor

        message = t('pf2e.explore_joined', :name => enactor.name, :encounter => encounter.id)

        Pf2e::Encounters::Announce.tell(encounter, message, :room => enactor_room)
      end
    end
  end
end
