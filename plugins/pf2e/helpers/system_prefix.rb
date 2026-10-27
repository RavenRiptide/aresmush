module AresMUSH
  module Pf2e

    # The prefix - `[PF]` - that marks what the game tells, so a player can tell it from a pose, at the
    # level each player sets with `rollprefix`:
    #
    #   all      every line the game tells, the ones indented under another too, actions and bookkeeping
    #   actions  the first line of each action and public roll: a Strike, a spell, damage dropping someone
    #   off      none
    #
    # A line is an `action` - what happens - or `system` - the encounter's bookkeeping: who joins, cover
    # set, a change taken back. An encounter notice - its start, end, round or turn - is neither, and is
    # never marked.
    #
    # Everyone in the room hears the line marked for them. What a log keeps is marked at the game's
    # default level, with the line as told beside it, so a page can mark it again for whoever reads it.
    module SystemPrefix
      LEVELS = %w{all actions off}.freeze

      def self.prefix
        Global.read_config('pf2e', 'system_prefix').to_s
      end

      def self.default_level
        level = Global.read_config('pf2e', 'system_prefix_level').to_s

        LEVELS.include?(level) ? level : 'actions'
      end

      # A character's own level, or the game's for one who has not set it - or for nobody, a page read
      # without logging in.
      def self.level_of(char)
        level = char&.pf2_roll_prefix

        LEVELS.include?(level) ? level : default_level
      end

      def self.marked(message, line, level, prefix = self.prefix)
        return message if prefix.empty? || line.nil? || level == 'off'
        return message if level == 'actions' && line.to_s != 'action'

        message.to_s.split(/(%r)/i).map do |part|
          next part if part.match?(/\A(%r)?\z/i) || (level == 'actions' && part.start_with?(' '))

          "#{prefix} #{part}"
        end.join
      end

      def self.for(char, message, line)
        marked(message, line, level_of(char))
      end

      # The line as a log keeps it.
      def self.kept(message, line)
        marked(message, line, default_level)
      end

      # Tells the room, each of its players the line marked at their level. When they would all hear the
      # same, the room is told it once.
      def self.emit(room, message, line, ooc: false)
        return unless room

        heard = room.clients.group_by { |client| self.for(client.char, message, line) }

        if heard.size <= 1
          text = heard.keys.first || kept(message, line)
          return ooc ? room.emit_ooc(text) : room.emit(text)
        end

        return if room == Game.master.quiet_room

        heard.each { |text, clients| clients.each { |client| ooc ? client.emit_ooc(text) : client.emit(text) } }
      end

      # What a scene keeps of the line: its text as the game's default marks it, and the line as told with
      # what kind it is, for `pose_text`.
      def self.log(scene, message, line, ooc: false)
        return unless scene

        Scenes.add_to_scene(scene, kept(message, line), Game.master.system_character, ooc ? false : nil, ooc ? true : nil, nil,
                            :system_line => line, :system_text => message)
      end

      # Tells the room and its scene's log, where there is no encounter to tell it through.
      def self.tell_room(room, message, line, ooc: false)
        emit(room, message, line, :ooc => ooc)
        log(room&.scene, message, line, :ooc => ooc)
      end

      # A scene pose as this viewer reads it: marked at their level - unless it has been edited since the
      # game told it, when it is shown as edited.
      def self.pose_text(pose, viewer)
        told = pose.system_text
        line = pose.system_line

        return pose.pose unless line && told && pose.pose == kept(told, line)

        self.for(viewer, told, line)
      end
    end
  end
end
