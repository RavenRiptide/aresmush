module AresMUSH
  module Pf2e

    # `encounter/csheet [<combatant>]` - a character's combat sheet as they stand in this encounter: the
    # attacks they can make with what they carry here, and their AC, saves and conditions. `csheet` is the
    # character without any of it.
    class PF2EncounterCombatSheetCmd
      include CommandHandler

      attr_accessor :target

      def parse_args
        self.target = trim_arg(cmd.args)
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter

        found = Combatants.find(encounter, self.target || enactor.name)

        return if CharState.emit_error!(client, found)
        return client.emit_failure(t('pf2e.encounter_sheet_creature', :ref => found.state.ref)) if found.state.creature?

        holder = found.state.holder
        outcome = Sheet.viewable?(enactor, Actors.of(holder).person, 'combat')

        return if CharState.emit_error!(client, outcome)

        client.emit SheetReads.holding(holder) { PF2CombatSheetTemplate.new(holder, client).render }
      end
    end
  end
end
