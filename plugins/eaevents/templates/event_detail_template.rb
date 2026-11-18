module AresMUSH
  module EaEvents

    # `event <#>`. The stock EventDetailCmd builds this in place of the stock EventDetailTemplate.
    #
    # The stock page plus the player count, the death-consent line, and the roster and waitlist
    # with each character's level and class. A character with screen reader mode on gets each
    # sign-up as a sentence ("1. Kaveh, Level 5 Wizard: comment") instead of spaced columns.
    class EventDetailTemplate < ErbTemplateRenderer

      attr_accessor :event

      def initialize(event, enactor)
        @event = event
        @enactor = enactor
        file = screen_reader? ? "event_detail_screen_reader.erb" : "event_detail.erb"
        super File.dirname(__FILE__) + "/#{file}"
      end

      def screen_reader?
        !!(@enactor && @enactor.screen_reader)
      end

      def start_datetime_local
        @event.start_datetime_local(@enactor)
      end

      def start_time_standard
        @event.start_time_standard
      end

      def roster
        EaEvents.roster(@event)
      end

      def waitlist
        EaEvents.waitlist(@event)
      end

      # "1.  Kaveh        Lvl 5 Wizard    - comment". Padded but never cut (ljust, not left), so a
      # long name or class only pushes the rest of its own line over.
      def signup_line(signup, label)
        char = signup.character
        name = char ? char.name : ""
        comment = signup.comment.blank? ? "" : " - #{signup.comment}"
        "#{label.ljust(4)}#{name.ljust(12)} #{EaEvents.class_label(char).ljust(16)}#{comment}".rstrip
      end

      # "1. Kaveh, Level 5 Wizard: comment", or "1. Kaveh." with no class and no comment.
      def signup_sentence(signup, label)
        char = signup.character
        text = "#{label} #{char ? char.name : ''}"
        class_label = EaEvents.class_label(char, :long)
        text = "#{text}, #{class_label}" if !class_label.blank?
        signup.comment.blank? ? "#{text}." : "#{text}: #{signup.comment}"
      end
    end
  end
end
