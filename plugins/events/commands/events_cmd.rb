module AresMUSH

  module Events
    class EventsCmd
      include CommandHandler

      def handle
        events = Event.sorted_events
        title = t('events.all_events_title')
        template = EaEvents::EventsListTemplate.new(events, title, enactor) # Emblem of Ea: Custom Ares change: portal-style list (eaevents)
        client.emit template.render
      end
    end
  end
end
