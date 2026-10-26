module AresMUSH
  module Pf2e

    # A formula book, a section per catalogue and a heading per item level, the way a spellbook lists
    # its spells by rank.
    class PF2FormulaTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :result, :client

      def initialize(result, char, client = nil)
        @char = char
        @result = result || {}
        @client = client

        super File.dirname(__FILE__) + "/formulas.erb"
      end

      def title
        t('pf2e.formula_char_title', :char => @char.name)
      end

      def empty?
        sections.empty?
      end

      def none
        t('pf2e.formula_none')
      end

      def sections
        @sections ||= PF2FormulaTemplate.by_level(@result) do |category, name|
          info = Global.read_config("pf2e_#{category.to_s.downcase}", name)

          info.is_a?(Hash) ? info['level'].to_i : nil
        end.map { |category, levels| format_section(category, levels) }
      end

      # { category => [ [ level, names ], ... ] }, lowest level first and names alphabetical. A formula
      # whose item the catalogue no longer holds has no level, and comes last.
      def self.by_level(book)
        book.each_with_object({}) do |(category, names), out|
          names = Array(names).map(&:to_s)
          next if names.empty?

          grouped = names.group_by { |name| yield(category, name) }

          out[category] = grouped.keys.sort_by { |level| level.nil? ? Float::INFINITY : level }
                                 .map { |level| [ level, grouped[level].sort_by(&:downcase) ] }
        end
      end

      def format_section(category, levels)
        lines = [ section_title(category.to_s.capitalize) ]

        levels.each do |level, names|
          label = level.nil? ? t('pf2e.formula_level_unknown') : t('pf2e.formula_level', :level => level)

          lines << "#{item_color}#{label}:%xn"
          lines << "%b%b#{names.join(', ')}"
        end

        lines.join("%r")
      end

      def section_title(title)
        @client&.screen_reader ? "#{title}:" : line_with_text(title)
      end
    end
  end
end
