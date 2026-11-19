module AresMUSH
  module EaEvents

    # The `events` list. The stock EventsCmd builds this in place of the stock EventsListTemplate.
    #
    # Events are grouped under a divider for each day, counted in the viewer's own time zone,
    # which the title line names. Each event gets a line for Title, Organizer, local Time, and
    # Players; a second line for the sign-up marker, the level range, the death-consent mark,
    # the server time, and the waitlist or "No limit"; and, when it has tags, a third line of
    # tags that wraps rather than cutting any off. Numbering runs on across days so `event <#>`
    # still matches. A character with screen reader mode on gets one sentence per event instead,
    # with words in place of columns and symbols.
    class EventsListTemplate < ErbTemplateRenderer

      attr_accessor :events, :title

      WIDTH = 78
      DEFAULT_ZONE = "America/New_York"

      # Column widths, together 58 of the 78 characters; Players takes the rest.
      MARKER = 4
      TITLE = 27
      ORGANIZER = 13
      TIME = 14

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

      def zone_name
        (@enactor && @enactor.timezone) || DEFAULT_ZONE
      end

      def zone
        Timezone[zone_name]
      end

      # "All Upcoming Events" on the left, "America/Chicago (CST)" on the right.
      def title_line
        label = "#{zone_name} (#{zone.abbr(Time.now)})"
        "%xh#{left(title, WIDTH - label.length)}%xn#{label}"
      end

      def sr_zone_line
        t('eaevents.sr_times_in_zone', :zone => zone_name)
      end

      def header
        "#{left('#', MARKER)}#{left(t('eaevents.col_title'), TITLE)}#{left(t('eaevents.col_organizer'), ORGANIZER)}" +
          "#{left(t('eaevents.col_time'), TIME)}#{t('eaevents.col_players')}"
      end

      # [ [ divider, [ [event, num], ... ] ], ... ] with events in list order, numbered from 1.
      def days
        numbered = events.each_with_index.map { |ev, i| [ ev, i + 1 ] }
        numbered.chunk { |ev, num| local_day(ev) }.map do |day, group|
          [ day_divider(group.first[0]), group ]
        end
      end

      def local_day(event)
        OOCTime.localtime(@enactor, event.starts).strftime("%Y-%m-%d")
      end

      # "----------< Wed Nov 18 2026 CST >----------"
      def day_divider(event)
        local = OOCTime.localtime(@enactor, event.starts)
        date = "#{local.strftime('%a %b %-d %Y')} #{zone.abbr(event.starts)}"
        center("< %xh#{date}%xn >", WIDTH, "-")
      end

      # The event's lines for the visual list: two, plus one or more of tags.
      def rows(event, num)
        marker = { waitlisted: "[W]", signed_up: "[*]" }[signup_status(event)] || ""
        level = EaEvents.event_level_label(event, :short)
        under_title = [ level, event.death_consent ? "%xh%xr[DC]%xn" : "" ].reject { |part| part.blank? }.join(" ")

        first = "#{left("#{num}.", MARKER)}%xh#{left(event.title, TITLE - 1)}%xn " +
          "#{left(event.organizer_name, ORGANIZER - 1)} " +
          "#{event.color}#{left(local_time(event), TIME - 1)}%xn #{players(event)}"
        second = "#{left(marker, MARKER)}#{left(under_title, TITLE + ORGANIZER)}" +
          "#{left("(#{event.start_time_standard})", TIME)}#{players_note(event)}"

        [ first.rstrip, second.rstrip ] + tag_lines(event)
      end

      # "Tags: a b c", wrapped at word breaks to the width of the list, continuation lines lined
      # up under the first tag. No tags, no lines.
      def tag_lines(event)
        tags = event.content_tags
        return [] if tags.empty?
        label = "#{t('eaevents.tags_label')} "
        indent = " " * (MARKER + label.length)
        room = WIDTH - indent.length
        lines = [ "" ]
        tags.each do |tag|
          if lines.last.empty?
            lines[-1] = tag
          elsif lines.last.length + 1 + tag.length <= room
            lines[-1] = "#{lines.last} #{tag}"
          else
            lines << tag
          end
        end
        lines.each_with_index.map { |line, i| "#{i == 0 ? (' ' * MARKER) + label : indent}#{line}" }
      end

      # The event as one sentence, for screen readers.
      def sentence(event, num)
        parts = [ "#{num}. #{event.title}." ]
        parts << t('eaevents.sr_death_consent') if event.death_consent
        range = EaEvents.event_level_label(event, :sr)
        parts << t('eaevents.sr_level_range', :range => range) if !range.blank?
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

      def local_time(event)
        local = OOCTime.localtime(@enactor, event.starts)
        l(local, format: Global.read_config("datetime", "time_format")).strip
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
