module AresMUSH
  module Pf2e

    class PF2RollForCommand
      include CommandHandler

      attr_accessor :mods, :dc, :string, :target

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_optional_arg3)

        self.target = trim_arg(args.arg1)

        self.string = trim_arg(args.arg2)

        mod_list = args.arg2.gsub("-", "+-").gsub("--","-").split("+")
        self.mods = mod_list.map { |v| v.strip }

        self.dc = args.arg3 ? args.arg3.to_i : nil
      end

      def check_valid_dc
        return nil if !self.dc
        if self.dc.between?(5,50)
          return nil
        else
          return t('pf2e.dc_must_be_integer')
        end
      end

      def required_args
        [ self.mods, self.target ]
      end

      def handle
        subject = ClassTargetFinder.find(self.target, Character, enactor)
        if (subject.found)
          subject = subject.target
          subject_name = subject.name
        else
          client.emit_failure t('pf2e.char_not_found')
          return
        end

        roll = Pf2e.parse_roll_string(subject,self.mods)
        list = roll['list']
        result = roll['result']
        total = roll['total']

        # Determine degree of success if DC is given
        degree = self.dc ? Pf2e.get_degree(list, result, total, self.dc) : ""

        roll_msg = t('pf2e.die_roll',
                  :roller => "%xy#{enactor.name}%xn (for %x24#{subject_name}%xn)",
                  :string => self.string,
                  :parsed => result.join(" + "),
                  :result => total,
                  :degree => degree
                )

        enactor_room.emit roll_msg

        channel = Global.read_config("pf2e", "roll_channel")
        if (channel)
          Channels.send_to_channel(channel, roll_msg)
        end

        if (enactor_room.scene)
          Scenes.add_to_scene(enactor_room.scene, roll_msg)
        end

        Global.logger.info "PF2 ROLL: #{roll_msg}"
      end

    end
  end
end
