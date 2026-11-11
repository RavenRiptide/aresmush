module AresMUSH
  module AltTracker

    class RegisterPlayerCmd
      include CommandHandler

      attr_accessor :codeword, :email, :target

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.target = trim_arg(args.arg1)
        self.codeword = trim_arg(args.arg2)
      end

      def required_args
        [ self.target, self.codeword ]
      end

      def handle
        valid_email = /\A([\w+\-].?)+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/i

        is_email = self.target =~ valid_email

        # Use safe navigation operator to force player to nil if character not found.
        player = is_email ?
            AltTracker.find_player_by_email(self.target, enactor) :
            Character.find_one_by_name(self.target)&.player

        if !player
          if is_email
            player = Player.create(name: self.target, codeword: self.codeword)

            enactor.update(player: player)

            client.emit_success t('alttracker.register_ok')
            return
          else
            client.emit_failure t('alttracker.must_use_email')
            return
          end
        end

        max_alts = Pf2noms.calculate_max_alts(player)
        current_alts = Pf2noms.calculate_current_alts(player)

        if player.banned
          client.emit_failure t('alttracker.player_banned')
          return
        elsif current_alts >= max_alts
          client.emit_failure t('alttracker.max_alts_exceeded', :max_alts => max_alts)
          return
        elsif !(self.codeword == player.codeword)
          # A player registering for the first time can pick an email that is already on
          # file; say so, or a bare "invalid codeword" reads as a broken command.
          if is_email
            client.emit_failure t('alttracker.email_already_registered', :email => self.target)
          else
            client.emit_failure t('alttracker.invalid_codeword')
          end
          return
        else
          enactor.update(player: player)
          player.update(mark_idle: nil)
          client.emit_success t('alttracker.register_ok')
        end

      end
    end

  end
end
