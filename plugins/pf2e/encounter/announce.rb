module AresMUSH
  module Pf2e
    module Encounters

      # What an encounter says to everyone in it: the room its scene is played in, its own log, and its
      # scene's log. Its GM may be elsewhere when they say it; the scene is where it is.
      #
      # What happens - a Strike, a spell, an effect ending as a turn starts - is the story of the scene,
      # and goes in its log as a system line, which the log kept when the scene is shared includes. The
      # bookkeeping - who joins, whose turn, cover set, the encounter starting and ending - goes in as an
      # OOC line, which the shared log leaves out. That is how the game's own combat logs.
      module Announce
        # An encounter notice - `start`, `end`, `round` or `turn` - and its details go with the line in the
        # encounter's own log and its scene's, for their pages to lay out as their own rather than show the
        # text. Any other line is marked with the game's prefix for whoever hears or reads it: a story line
        # as an `action`, the bookkeeping as `system` (see `SystemPrefix`).
        def self.tell(encounter, message, room: nil, story: false, notice: nil, notice_details: nil)
          scene = encounter.scene
          line = notice ? nil : (story ? 'action' : 'system')
          where = scene&.room || room

          line ? SystemPrefix.emit(where, message, line) : where&.emit(message)
          PF2Encounter.send_to_encounter(encounter, message, :notice => notice, :notice_details => notice_details, :line => line)
          log(scene, message, :story => story, :notice => notice, :notice_details => notice_details)
        end

        def self.log(scene, message, story: false, notice: nil, notice_details: nil)
          return unless scene

          if notice
            Scenes.add_to_scene(scene, message, Game.master.system_character, false, true, nil,
                                :encounter_notice => notice, :encounter_notice_details => notice_details || {})
          else
            SystemPrefix.log(scene, message, story ? 'action' : 'system', :ooc => !story)
          end
        end
      end
    end
  end
end
