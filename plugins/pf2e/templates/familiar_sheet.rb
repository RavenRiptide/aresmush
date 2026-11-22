module AresMUSH
  module Pf2e

    # sheet/familiar: lays out what `Familiar::SheetView` built. A row of cells shares the line: two at
    # 39 columns, three at 26, as the character sheet's columns are.
    class PF2FamiliarSheetTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :view, :client

      def initialize(view, client)
        @view = view
        @client = client

        super File.dirname(__FILE__) + "/familiar_sheet.erb"
      end

      def title
        @view['title']
      end

      def sections
        @view['sections']
      end

      def section_line(text)
        @client.screen_reader ? text : line_with_text(text)
      end

      def row_text(row)
        return row if row.is_a?(String)

        width = row.size > 2 ? 26 : 39
        cells = row.map { |label, value| "#{item_color}#{label}%xn: #{value}" }

        return cells.first if cells.size == 1

        cells.each_with_index.map { |cell, index| index == cells.size - 1 ? cell : left(cell, width) }.join
      end
    end
  end
end
