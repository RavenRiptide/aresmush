require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The `formulas` screen: each catalogue's formulas grouped by the level of the item they make,
    # lowest first, alphabetical within a level, the way a spellbook lists spells by rank.
    describe PF2FormulaTemplate do

      LEVELS = {
        "Alchemist's Fire (Moderate)" => 3, 'Snake Oil' => 1, 'Arsenic' => 1, "Alchemist's Fire (Lesser)" => 1
      }.freeze

      def grouped(book)
        PF2FormulaTemplate.by_level(book) { |_category, name| LEVELS[name] }
      end

      it "should group by item level, lowest first, alphabetical within a level" do
        found = grouped('consumables' => [ "Alchemist's Fire (Moderate)", 'Snake Oil', 'Arsenic', "Alchemist's Fire (Lesser)" ])

        expect(found).to eq('consumables' => [ [ 1, [ "Alchemist's Fire (Lesser)", 'Arsenic', 'Snake Oil' ] ],
                                               [ 3, [ "Alchemist's Fire (Moderate)" ] ] ])
      end

      it "should keep a formula whose item has left the catalogue, after the known levels" do
        found = grouped('consumables' => [ 'Arsenic', 'Retired Elixir' ])

        expect(found['consumables']).to eq [ [ 1, [ 'Arsenic' ] ], [ nil, [ 'Retired Elixir' ] ] ]
      end

      it "should leave out an empty chapter" do
        expect(grouped('consumables' => [], 'runes' => [ 'Arsenic' ]).keys).to eq [ 'runes' ]
      end

      # The formulas a feat's choice gave are on the formulas screen, so the feat's name carries none.
      describe :feat_display_list do
        before(:each) do
          allow(Pf2e).to receive(:feat_choice_block_for).and_return(nil)
          allow(Pf2e).to receive(:feat_choice_block_for).with('Alchemical Crafting')
            .and_return('count' => 4, 'from_formulas' => { 'traits' => [ 'alchemical' ] })
          allow(Pf2e).to receive(:feat_choice_block_for).with('Assurance').and_return('from_skills' => {})
          allow(Pf2e).to receive(:choice_sequence_depth).and_return(1)
          allow(Pf2e).to receive(:choice_labels_for) do |_char, name|
            { 'Alchemical Crafting' => [ 'Forensic Dye', 'Glow Rod' ], 'Assurance' => [ 'Crafting' ] }[name] || []
          end
        end

        it "should name a formula feat without its picks, and keep another feat's pick" do
          shown = Pf2e.feat_display_list(double(:name => 'Someone'), [ 'Alchemical Crafting', 'Assurance', 'Shield Block' ])

          expect(shown).to eq [ 'Alchemical Crafting', 'Assurance (Crafting)', 'Shield Block' ]
        end
      end
    end
  end
end
