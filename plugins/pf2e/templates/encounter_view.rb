module AresMUSH
  module Pf2e

    class PF2EncounterViewTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :encounter

      def initialize(encounter, client)
        @encounter = encounter
        @client = client

        super File.dirname(__FILE__) + "/encounter_view.erb"
      end

      def title
        t('pf2e.initiative_view_title', :id => @encounter.id)
      end

      def section_line(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def header_line
        "%b#{left("Id", 4)}#{left("Init", 5)}%b#{left("Name", 24)}%b#{left("Conditions, cover", 40)}"
      end

      def initiative_list

        list = []

        return list if @encounter.participants.empty?

        @encounter.participants.each do |p|
          list << format_init_list_item(p)
        end

        list

      end

      # A combatant's id, what it is under, and the cover and concealment set on it.
      def format_init_list_item(participant)
        initiative = participant[0].to_i
        name = participant[1]
        holder = Pf2e::Combatants.holder_named(@encounter, name)
        number = Pf2e::Combatants.number(@encounter, name)
        conditions = holder ? Pf2e.condition_labels(holder, false) : []
        cover = (@encounter.cover || {})[number.to_s]
        concealment = (@encounter.concealment || {})[number.to_s]
        said = conditions + [ cover ? "#{cover} cover" : nil, concealment ].compact

        "%b#{left("##{number}", 4)}#{left(initiative, 5)}%b#{left(name, 24)}%b#{left(said.join(", "), 40)}"
      end

      def trusted
        Array(@encounter.trusted)
      end

    end
  end
end
