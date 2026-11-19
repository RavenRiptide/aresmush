module AresMUSH
  module Pf2noms

    class PF2RPPTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :player, :client

      def initialize(char, player, client)
        @char = char
        @player = player
        @client = client

        super File.dirname(__FILE__) + "/rpp_template.erb"
      end

      def textline(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def title
        t('pf2noms.rpp_title', :char => @char.name)
      end

      def total_rpp
        @player.total_rpp
      end

      def available_rpp
        @player.available_rpp
      end

      def spent_on_char
        spent = @player.rpp_spent_by_char[@char.name]

        spent ? spent : 0
      end

      def alts
        Pf2noms.calculate_current_alts(@player)
      end


    end
  end
end
