module AresMUSH
  module EaEvents

    # event/consent <#>=<on|off>
    class EventConsentCmd
      include CommandHandler

      attr_accessor :num, :setting

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.num = integer_arg(args.arg1)
        self.setting = downcase_arg(args.arg2)
      end

      def required_args
        [ self.num, self.setting ]
      end

      def check_setting
        return nil if [ "on", "off" ].include?(self.setting)
        t('eaevents.invalid_consent_setting')
      end

      def handle
        Events.with_an_event(self.num, client, enactor) do |event|
          if (!Events.can_manage_event?(enactor, event))
            client.emit_failure t('dispatcher.not_allowed')
            return
          end

          on = self.setting == "on"
          EaEvents.set_death_consent(event, on)
          client.emit_success t(on ? 'eaevents.consent_on' : 'eaevents.consent_off', :title => event.title)
        end
      end
    end
  end
end
