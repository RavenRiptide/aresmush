module AresMUSH
  module Pf2e

    # `encounter/companion [<character>]` - your animal companion is here in the fight;
    # `encounter/companion/leave [<character>]` - it has gone. The GM may name anyone's.
    class PF2EncounterCompanionCmd
      include CommandHandler

      attr_accessor :target, :leaving

      def parse_args
        self.leaving = cmd.switch.to_s.downcase.end_with?('/leave')
        self.target = trim_arg(cmd.args)
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter

        char = master(encounter)
        return unless char

        row = Combatants.rows(encounter).find { |one| one['char'].to_s == char.id.to_s }
        outcome = self.leaving ? Companion::Joining.leave!(encounter, char, row) : Companion::Joining.join!(encounter, char, row)

        return if CharState.emit_error!(client, outcome)

        lines = Telling.lines(Array(outcome.state['freed']))
        message = outcome.messages.map { |one| t(one['key'], **CharState.symbolize(one['args'])) }

        Encounters::Announce.tell(encounter, (message + lines).join('%r'), :room => enactor_room)
      end

      # Whose companion: their own, or for the GM, whoever they name.
      def master(encounter)
        return enactor unless self.target

        unless Combatants.gm?(enactor, encounter)
          client.emit_failure t('pf2e.not_organizer')
          return nil
        end

        char = Pf2e.get_character(self.target, enactor)
        client.emit_failure t('pf2e.not_found') unless char
        char
      end
    end
  end
end
