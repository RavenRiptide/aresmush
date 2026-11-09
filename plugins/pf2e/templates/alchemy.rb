module AresMUSH
  module Pf2e

    # An alchemist's versatile vials and prepared items, for whoever they are shown as: their sheet, or
    # their state in an encounter.
    class PF2AlchemyTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :holder, :client

      def initialize(holder, client = nil)
        @holder = holder
        @client = client

        super File.dirname(__FILE__) + "/alchemy.erb"
      end

      def title
        t('pf2e.alchemy_title', :name => @holder.name)
      end

      def textline(title)
        @client && @client.screen_reader ? title : line_with_text(title)
      end

      def standing?
        !Gm.encounter_of(@holder).nil?
      end

      # Their versatile vials and their prepared items, which are separate allowances, said separately.
      def allowances
        day = Alchemy.day(@holder)
        key = standing? ? 'pf2e.alchemy_vials_today' : 'pf2e.alchemy_vials_rested'
        key += '_only' if day['prepared'].to_i.zero?

        t(key, :vials => day['vials'], :left => day['left'], :prepared => day['prepared'])
      end

      def planned
        Alchemy.plan(@holder).map { |name, many| t('pf2e.alchemy_line', :item => name, :many => many) }
      end

      # What was made of reagents and is still to hand, which only an encounter holds.
      def made
        return [] unless standing?

        Alchemy.made(@holder).map do |item|
          lasts = %w{turn turn_end}.include?(item.expires) ? item.expires : 'rest'

          t("pf2e.alchemy_made_#{lasts}", :item => item.name, :many => item.quantity)
        end
      end

      def help_text
        t('pf2e.alchemy_help')
      end
    end
  end
end
