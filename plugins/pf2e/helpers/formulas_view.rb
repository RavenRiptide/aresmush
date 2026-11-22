module AresMUSH
  module Pf2e

    # The Formulas tab of a character's profile, as plain data: their formula book the way `formulas` lists
    # it - a block per catalogue and a row per item level, lowest first, with a formula whose item the
    # catalogue no longer holds last, at no level. The grouping and the catalogue names are the in-game
    # screen's own (`PF2FormulaTemplate`), so the two can't drift apart.
    module FormulasView

      def self.of(char)
        grouped = PF2FormulaTemplate.by_level(char.pf2_formula_book || {}) do |category, name|
          info = Global.read_config("pf2e_#{category.to_s.downcase}", name)

          info.is_a?(Hash) ? info['level'].to_i : nil
        end

        { name: char.name,
          catalogues: grouped.map do |category, levels|
            { label: PF2FormulaTemplate.catalogue_label(category),
              levels: levels.map { |level, names| { level: level, formulas: ProfileSheet.items(names, 'item') } } }
          end }
      end

      # Whether there is anything in their book to show.
      def self.any?(char)
        (char.pf2_formula_book || {}).values.any? { |names| Array(names).any? }
      end
    end
  end
end
