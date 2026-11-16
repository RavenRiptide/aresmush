module AresMUSH
  module Pf2e

    # A formula book, a section per catalogue and a heading per item level, the way a spellbook lists
    # its spells by rank. The formulas a choice offers (cg/info, advance/info) use the same layout,
    # under the choice's name, and page by whole level groups when there are too many for one screen.
    class PF2FormulaTemplate < ErbTemplateRenderer
      include CommonTemplateFields
      include PagedTemplate

      attr_accessor :char, :result, :client, :paginator

      # The catalogue keys the formula pools and books use, as a player reads them. A catalogue
      # missing here shows capitalized.
      CATALOGUE_LABELS = {
        'consumables' => 'Consumables',
        'magicitem' => 'Magic Items',
        'runes' => 'Runes',
        'armor' => 'Armor',
        'shields' => 'Shields',
        'weapons' => 'Weapons',
        'gear' => 'Gear'
      }.freeze

      # `title` replaces the "Formulas Known By" title. With `page_size`, the list is cut into pages
      # of at most that many formulas, and `cmd` supplies the page asked for and the next-page hint.
      def initialize(result, char, client = nil, title: nil, cmd: nil, page_size: nil)
        @char = char
        @result = result || {}
        @client = client
        @title = title
        @cmd = cmd

        if page_size
          pages = PF2FormulaTemplate.pages(grouped, page_size)
          @paginator = Paginator.paginate(pages, cmd ? cmd.page : 1, 1)
        end

        super File.dirname(__FILE__) + "/formulas.erb"
      end

      def title
        @title || t('pf2e.formula_char_title', :char => @char.name)
      end

      def empty?
        sections.empty?
      end

      def none
        t('pf2e.formula_none')
      end

      # Only a list that runs past one page shows the page bar.
      def paged?
        !!@paginator && @paginator.total_pages > 1
      end

      def sections
        @sections ||= page_rows.chunk_while { |a, b| a[0] == b[0] }
                               .map { |rows| format_section(rows[0][0], rows.map { |_category, level, names| [ level, names ] }) }
      end

      # { category => [ [ level, names ], ... ] } for the whole list.
      def grouped
        @grouped ||= PF2FormulaTemplate.by_level(@result) do |category, name|
          info = Global.read_config("pf2e_#{category.to_s.downcase}", name)

          info.is_a?(Hash) ? info['level'].to_i : nil
        end
      end

      # [ category, level, names ] rows on the page shown: all of them when unpaged.
      def page_rows
        return Array(@paginator.page_items.first) if @paginator

        grouped.flat_map { |category, levels| levels.map { |level, names| [ category, level, names ] } }
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

      # The grouped list cut into pages of at most `per_page` formulas, each page an array of
      # [ category, level, names ] rows. A level group starts a new page rather than split across
      # two, unless it alone is longer than a page; then it fills pages of its own, its heading
      # repeated on each.
      def self.pages(grouped, per_page)
        per_page = [ per_page.to_i, 1 ].max
        pages = [ [] ]
        count = 0

        grouped.each do |category, levels|
          levels.each do |level, names|
            names.each_slice(per_page) do |slice|
              if count > 0 && count + slice.size > per_page
                pages << []
                count = 0
              end

              pages.last << [ category, level, slice ]
              count += slice.size
            end
          end
        end

        pages
      end

      def self.catalogue_label(category)
        CATALOGUE_LABELS[category.to_s.downcase] || category.to_s.capitalize
      end

      def format_section(category, levels)
        lines = [ section_title(PF2FormulaTemplate.catalogue_label(category)) ]

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
