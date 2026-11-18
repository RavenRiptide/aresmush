module AresMUSH

  module Events
    class EventDetailCmd
      include CommandHandler
      
      attr_accessor :num

      def parse_args
        self.num = cmd.args ? cmd.args.to_i : nil
      end
      
      def required_args
        [ self.num ]
      end
      
      def handle
        Events.with_an_event(self.num, client, enactor) do |event| 
          template = EaEvents::EventDetailTemplate.new(event, enactor) # Emblem of Ea: Custom Ares change: roster and waitlist (eaevents)
          Login.mark_notices_read(enactor, :event, event.id)          
          client.emit template.render
        end
      end
    end
  end
end
