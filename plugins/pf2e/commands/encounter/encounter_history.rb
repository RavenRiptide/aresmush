module AresMUSH
  module Pf2e

    # `+e/undo` and `+e/redo` - the GM takes back the last change in the encounter here, or puts back the
    # one they last took back. The room is told either way.
    class PF2EncounterUndoCmd
      include CommandHandler

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        undoing = cmd.switch_is?('undo')
        done = undoing ? History.undo(encounter) : History.redo(encounter)

        return if CharState.emit_error!(client, done)

        # The encounter as the undo left it: Ohm saves every attribute of an object it updates, so logging
        # through the copy read before it would put the old one back.
        encounter = PF2Encounter[encounter.id]
        message = t(undoing ? 'pf2e.history_undone' : 'pf2e.history_redone', :name => enactor.name,
                                                                             :said => done.state.said)

        enactor_room.emit_ooc message
        PF2Encounter.send_to_encounter(encounter, message)
        Scenes.add_to_scene(encounter.scene, message, Game.master.system_character, false, true) if encounter.scene
      end
    end

    # `+e/history [<encounter id>]` - every change in an encounter, with where undo and redo stand.
    class PF2EncounterHistoryCmd
      include CommandHandler

      attr_accessor :encounter_id

      def parse_args
        self.encounter_id = trim_arg(cmd.args)&.delete_prefix('#')
      end

      def handle
        encounter = self.encounter_id ? PF2Encounter[self.encounter_id] : Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter

        at = History.at(encounter)
        lines = History.entries(encounter).map do |entry|
          "#{entry.seq == at ? '%xh>%xn' : ' '} #{entry.seq.to_s.rjust(3)}  #{entry.seq > at ? '%xx' : ''}#{entry.said}%xn"
        end

        return client.emit_ooc(t('pf2e.history_empty', :id => encounter.id)) if lines.empty?

        client.emit ([ t('pf2e.history_title', :id => encounter.id) ] + lines).join('%r')
      end
    end
  end
end
