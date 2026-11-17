module AresMUSH
  module Pf2e

    # The banner an exploration starts with: an encounter with no initiative, so no stat to declare.
    class PF2ExploreStart < ErbTemplateRenderer
      include CommonTemplateFields

      # The help file on exploring, which the web portal's banner links to as well.
      HELP_TOPIC = 'pf2e_exploration'

      attr_accessor :encounter

      def initialize(encounter)
        @encounter = encounter

        super File.dirname(__FILE__) + "/encounter_explore.erb"
      end

      def title
        t('pf2e.explore_start_title')
      end

      def encounter_id
        @encounter.id
      end

      def organizer
        PF2Encounter.gm_of(@encounter)&.name || @encounter.organizer
      end

      # What the room is to do: join and pick an activity. Carried on from an earlier encounter, whoever
      # was in it is already here, as they left it.
      def instruction
        from = @encounter.carries_on_from

        from ? t('pf2e.explore_start_carried_on', :from => from) : t('pf2e.explore_start_join')
      end

      # What the banner says, without its layout. The encounter's page lays out its own links to the
      # encounter's log and to the help.
      def notice_details
        { 'organizer' => organizer, 'id' => encounter_id,
          'instruction' => AnsiFormatter.strip_ansi(MushFormatter.format(instruction)).strip }
      end

      def log_line
        t('pf2e.encounter_start_log', :url => PF2Encounter.page_url(@encounter))
      end

      # The help, in the game and on the web: a whole address, which a client can open.
      def help_line
        t('pf2e.explore_start_help', :help => "'#{title_color}help exploration%xn'",
                                     :url => "#{Game.web_portal_url}/help/#{HELP_TOPIC}")
      end

    end
  end
end
