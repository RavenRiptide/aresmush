module AresMUSH
  module Pf2egear

    class PF2MoneyHistoryTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :paginator, :client

      def initialize(char, paginator, client)
        @char = char
        @paginator = paginator
        @client = client

        super File.dirname(__FILE__) + "/money_history.erb"
      end

      def textline(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def title
        t('pf2egear.money_history_title', :char => @char.name)
      end

      def page_items
        @paginator.page_items
      end

      def page_footer
        @paginator.page_footer
      end

      def time(item)
        converted_time = Time.at(item[0])

        OOCTime.local_short_timestr(@char, converted_time)
      end

      def awarded_by(item)
        item[1]
      end

      def award(item)
        Pf2egear.display_money(item[2])
      end

      def reason(item)
        item[3]
      end


    end
  end
end
