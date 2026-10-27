module AresMUSH
  module Pf2e

    class PF2EncounterStart < ErbTemplateRenderer
      include CommonTemplateFields

      # The help file on encounters, which the web portal's banner links to as well.
      HELP_TOPIC = 'pf2e_combat'

      attr_accessor :encounter

      def initialize(encounter)
        @encounter = encounter

        super File.dirname(__FILE__) + "/encounter_start.erb"
      end

      def title
        t('pf2e.encounter_start_title')
      end

      def init_stat
        @encounter.init_stat
      end

      def encounter_id
        @encounter.id
      end

      def organizer
        PF2Encounter.gm_of(@encounter)&.name || @encounter.organizer
      end

      # What the room is to do: join, or - for a fight that takes over from an exploration, which has
      # brought everyone in already - nothing but play on.
      def instruction
        from = @encounter.carries_on_from ? PF2Encounter[@encounter.carries_on_from] : nil
        key = Exploration.exploring?(from) ? 'pf2e.encounter_start_from_exploring' : 'pf2e.encounter_start_join'

        t(key)
      end

      # What the banner says, without its layout. The encounter's page lays out its own links to the
      # encounter's log and to the help.
      def notice_details
        { 'organizer' => organizer, 'id' => encounter_id, 'init_stat' => init_stat,
          'instruction' => AnsiFormatter.strip_ansi(MushFormatter.format(instruction)).strip }
      end

      def log_line
        t('pf2e.encounter_start_log', :url => PF2Encounter.page_url(@encounter))
      end

      # The help, in the game and on the web: a whole address, which a client can open.
      def help_line
        t('pf2e.encounter_start_help', :help => "'#{title_color}help initiative%xn'",
                                       :url => "#{Game.web_portal_url}/help/#{HELP_TOPIC}")
      end

      def roll_init_cmd
        "init/join #{encounter_id}[=<alternate stat>]"
      end

    end
  end
end
