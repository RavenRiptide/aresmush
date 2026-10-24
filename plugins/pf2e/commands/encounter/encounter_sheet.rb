module AresMUSH
  module Pf2e

    # `+e/sheet[/<section>] [<combatant>]` - a character's sheet as they stand in this encounter: the
    # damage they have taken, what they are under, and what they have left to spend. `+sheet` is the
    # character without any of it.
    class PF2EncounterSheetCmd
      include CommandHandler

      attr_accessor :section, :target

      def parse_args
        self.section = cmd.args.to_s.include?('/') ? cmd.args.split('/', 2).last.strip.downcase : 'all'
        self.target = trim_arg(cmd.args.to_s.split('/', 2).first)
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter

        found = Combatants.find(encounter, self.target || enactor.name)

        return if CharState.emit_error!(client, found)
        return client.emit_failure(t('pf2e.encounter_sheet_creature', :ref => found.state.ref)) if found.state.creature?

        holder = found.state.holder
        char = Actors.of(holder).person
        outcome = Sheet.viewable?(enactor, char, self.section).and_then { Sheet.available(char, self.section) }

        return if CharState.emit_error!(client, outcome)

        template = Pf2eSheetTemplate.new(holder, outcome.state, client, char.pf2_base_info, char.pf2_faith)

        client.emit SheetReads.holding(holder) { template.render }
      end
    end
  end
end
