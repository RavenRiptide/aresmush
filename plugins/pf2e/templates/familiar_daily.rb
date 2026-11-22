module AresMUSH
  module Pf2e

    # prepare/familiar with nothing after it: lays out what `Familiar::Daily.listing` built. The day's picks
    # come first, then what the familiar can have, each list in two columns read down then across.
    class PF2FamiliarDailyTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :shown, :client

      WIDTH = 37

      def initialize(shown, client)
        @shown = shown
        @client = client

        super File.dirname(__FILE__) + "/familiar_daily.erb"
      end

      def title
        name = @shown['name']

        name ? t('pf2e.familiar_daily_title', :name => name) : t('pf2e.familiar_daily_title_yours')
      end

      def section_line(key)
        text = t(key)

        @client.screen_reader ? text : line_with_text(text)
      end

      def selected_rows
        @shown['selected'].empty? ? [ t('pf2e.familiar_daily_none_selected') ] : columns(@shown['selected'])
      end

      # The lists under Available Abilities that have something in them, each a heading and its lines.
      def available
        needs = @shown['needs'].map do |label, names|
          "%b%b#{left(label, WIDTH)}#{t('pf2e.familiar_daily_needs', :abilities => names.to_sentence)}"
        end

        [
          [ 'pf2e.familiar_daily_familiar_heading', columns(@shown['familiar']) ],
          [ 'pf2e.familiar_daily_needs_heading', needs.empty? ? [] : [ t('pf2e.familiar_daily_needs_explained') ] + needs ],
          [ 'pf2e.familiar_daily_master_heading', columns(@shown['master']) ],
          [ 'pf2e.familiar_daily_leshy_heading', columns(@shown['leshy']) ]
        ].reject { |_key, lines| lines.empty? }.map { |key, lines| [ heading(key), lines ] }
      end

      def budget_line
        count = @shown['budget']
        key = if @shown['pooled'].positive? then 'pf2e.familiar_daily_budget_leshy'
              elsif count == 1 then 'pf2e.familiar_daily_budget_one'
              else 'pf2e.familiar_daily_budget'
              end

        "#{t(key, :count => count)} #{t('pf2e.familiar_daily_how')}"
      end

      def heading(key)
        "#{item_color}#{t(key)}%xn"
      end

      # Two columns, the first holding the extra one when the count is odd.
      def columns(list)
        down = (list.size + 1) / 2

        list.first(down).each_with_index.map do |one, index|
          right = list[down + index]

          right ? "%b%b#{left(one, WIDTH)}#{right}" : "%b%b#{one}"
        end
      end
    end
  end
end
