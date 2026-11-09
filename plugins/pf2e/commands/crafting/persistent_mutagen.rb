module AresMUSH
  module Pf2e

    # `encounter/persistentmutagen` - Persistent Mutagen: once a day, the mutagen just drunk lasts until the
    # next daily preparations instead of its normal duration. Mutagens are drunk in an encounter, so this
    # is one too.
    class PF2PersistentMutagenCmd
      include CommandHandler

      def encounter
        @encounter ||= Combatants.encounter_here(enactor)
      end

      def handle
        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter

        state = CombatantStates.of(encounter, enactor)

        return client.emit_failure(t('pf2e.encounter_gear_not_in')) unless state

        made = Mutagens.persist!(state)

        return if CharState.emit_error!(client, made)

        message = t('pf2e.persistent_mutagen_done', :name => enactor.name, :mutagen => ActiveEffects.bare_name(made.state))

        Pf2e::Encounters::Announce.tell(PF2Encounter[encounter.id], message, :room => enactor_room, :story => true)
      end
    end
  end
end
