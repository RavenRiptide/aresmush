module AresMUSH
  module EaEvents

    # event/levels <#>=<range|any|none>
    class EventLevelsCmd
      include CommandHandler

      attr_accessor :num, :range_text

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.num = integer_arg(args.arg1)
        self.range_text = trim_arg(args.arg2)
      end

      def required_args
        [ self.num, self.range_text ]
      end

      def handle
        range, error = EaEvents.parse_level_range(self.range_text)
        if (error)
          client.emit_failure error
          return
        end

        Events.with_an_event(self.num, client, enactor) do |event|
          if (!Events.can_manage_event?(enactor, event))
            client.emit_failure t('dispatcher.not_allowed')
            return
          end

          newly_out = EaEvents.set_level_range(event, range)

          if (range)
            client.emit_success t('eaevents.level_range_set', :title => event.title,
              :range => EaEvents.event_level_label(event))
          else
            client.emit_success t('eaevents.level_range_removed', :title => event.title)
          end
          if (newly_out.any?)
            names = newly_out.map { |c| "#{c.name} (#{t('eaevents.level_one_short', :level => EaEvents.char_level(c))})" }
            client.emit_ooc t('eaevents.level_range_now_outside', :names => names.join(", "))
          end
        end
      end
    end
  end
end
