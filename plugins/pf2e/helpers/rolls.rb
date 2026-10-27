module AresMUSH
  module Pf2e

    # Where a finished roll message goes, as opposed to how it is calculated. The roll math lives in utils.rb.
    #
    # Private rolls skip all of it and are emitted to the client directly by the command, and logging stays with the commands too, since a private roll is still logged.

    # Sends a roll message to the room, to the room's scene and any encounter active in it, and to the roll channel if one is configured.
    # Each hears it marked with the game's prefix at their own level; the channel hears the game's default.
    def self.broadcast_roll(room, msg)
      SystemPrefix.tell_room(room, msg, 'action')

      scene = room.scene

      if scene
        active_encounter = PF2Encounter.scene_active_encounter(scene)
        PF2Encounter.send_to_encounter(active_encounter, msg, :line => 'action') if active_encounter
      end

      channel = Global.read_config("pf2e", "roll_channel")
      Channels.send_to_channel(channel, SystemPrefix.kept(msg, 'action')) if channel
    end

  end
end
