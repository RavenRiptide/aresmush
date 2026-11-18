module AresMUSH
  module EaEvents

    # event/limit <#>=<number|none>
    class EventLimitCmd
      include CommandHandler

      attr_accessor :num, :limit_text

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.num = integer_arg(args.arg1)
        self.limit_text = trim_arg(args.arg2)
      end

      def required_args
        [ self.num, self.limit_text ]
      end

      def handle
        limit, error = EaEvents.parse_limit(self.limit_text)
        if (error)
          client.emit_failure error
          return
        end

        Events.with_an_event(self.num, client, enactor) do |event|
          if (!Events.can_manage_event?(enactor, event))
            client.emit_failure t('dispatcher.not_allowed')
            return
          end

          promoted, demoted = EaEvents.set_max_players(event, limit)

          if (limit)
            client.emit_success t('eaevents.limit_set', :title => event.title, :limit => limit)
          else
            client.emit_success t('eaevents.limit_removed', :title => event.title)
          end
          if (demoted.any?)
            client.emit_ooc t('eaevents.limit_moved_to_waitlist', :names => demoted.map { |c| c.name }.join(", "))
          end
          if (promoted.any?)
            client.emit_ooc t('eaevents.limit_moved_to_roster', :names => promoted.map { |c| c.name }.join(", "))
          end
        end
      end
    end
  end
end
