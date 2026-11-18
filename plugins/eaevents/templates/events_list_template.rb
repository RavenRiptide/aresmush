module AresMUSH
  module EaEvents

    # The `events` list. The stock EventsCmd builds this in place of the stock EventsListTemplate.
    #
    # Laid out like the web portal's events table: Title, Organizer, Date/Time, and Players, with a
    # second line per event for what the portal stacks underneath (server time, the waitlist or
    # "No limit") and for the sign-up marker, the death-consent mark, and tags. A character with
    # screen reader mode on gets one sentence per event instead, with words in place of columns
    # and symbols.
    class EventsListTemplate < ErbTemplateRenderer

      attr_accessor :events, :title

      # Column widths, together 66 of the 78 characters; Players takes the rest.
      MARKER = 5
      TITLE = 24
      ORGANIZER = 11
      WHEN = 26

      def initialize(events, title, enactor)
        @events = events
        @title = title
        @enactor = enactor
        file = screen_reader? ? "events_list_screen_reader.erb" : "events_list.erb"
        super File.dirname(__FILE__) + "/#{file}"
      end

      def screen_reader?
        !!(@enactor && @enactor.screen_reader)
      end

      def header
        "#{left('#', MARKER)}#{left(t('eaevents.col_title'), TITLE)}#{left(t('eaevents.col_organizer'), ORGANIZER)}" +
          "#{left(t('eaevents.col_when'), WHEN)}#{t('eaevents.col_players')}"
      end

      # The event's two lines for the visual list.
      def rows(event, num)
        marker = { waitlisted: "[W]", signed_up: "[*]" }[signup_status(event)] || ""
        tags = event.content_tags.join(" ")
        under_title = event.death_consent ? "[DC] #{tags}" : tags
        under_title = left(under_title, TITLE - 1).rstrip.sub("[DC]", "%xh%xr[DC]%xn")
        when_color = event.color

        first = "#{left("#{num}.", MARKER)}%xh#{left(event.title, TITLE - 1)}%xn " +
          "#{left(event.organizer_name, ORGANIZER - 1)} " +
          "#{when_color}#{left(local_when(event), WHEN - 1)}%xn #{players(event)}"
        second = "#{left(marker, MARKER)}#{left(under_title, TITLE)}#{left('', ORGANIZER)}" +
          "#{left("(#{event.start_time_standard})", WHEN)}#{players_note(event)}"

        [ first.rstrip, second.rstrip ]
      end

      # The event as one sentence, for screen readers.
      def sentence(event, num)
        parts = [ "#{num}. #{event.title}." ]
        parts << t('eaevents.sr_death_consent') if event.death_consent
        parts << t('eaevents.sr_organizer', :name => event.organizer_name)
        parts << t('eaevents.sr_when', :local => local_when(event), :server => event.start_time_standard)
        parts << t('eaevents.sr_players', :players => EaEvents.screen_reader_players(event))
        case signup_status(event)
        when :waitlisted
          parts << t('eaevents.sr_you_are_waitlisted')
        when :signed_up
          parts << t('eaevents.sr_you_are_signed_up')
        end
        tags = event.content_tags
        parts << t('eaevents.sr_tags', :tags => tags.join(" ")) if tags.any?
        parts.join(" ")
      end

      # The stock list's marker counts the player's alts and the organizer as signed up; waiting
      # on the list takes precedence.
      def signup_status(event)
        return :waitlisted if EaEvents.any_alt_waitlisted?(event, @enactor)
        return :signed_up if event.is_signed_up?(@enactor)
        nil
      end

      def local_when(event)
        OOCTime.local_short_date_and_time(@enactor, event.starts).squeeze(" ").strip
      end

      # "3 / 6", "5 / 5 Full", or "0 signed up" with no limit.
      def players(event)
        limit = EaEvents.max_players(event)
        count = event.signups.count
        return t('eaevents.players_no_limit', :count => count) if !limit
        shown = "#{[count, limit].min} / #{limit}"
        EaEvents.is_full?(event) ? "#{shown} #{t('eaevents.full')}" : shown
      end

      # "2 waitlisted", "No limit", or nothing.
      def players_note(event)
        return t('eaevents.no_limit') if !EaEvents.max_players(event)
        waiting = EaEvents.waitlist(event).count
        waiting > 0 ? t('eaevents.waitlisted_count', :waiting => waiting) : ""
      end
    end
  end
end
