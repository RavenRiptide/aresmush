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

      it "should give each catalogue a player's label, and capitalize one it doesn't know" do
        expect(PF2FormulaTemplate.catalogue_label('magicitem')).to eq 'Magic Items'
        expect(PF2FormulaTemplate.catalogue_label('consumables')).to eq 'Consumables'
        expect(PF2FormulaTemplate.catalogue_label('trinkets')).to eq 'Trinkets'
      end

      # A long formula choice pages by whole level groups, so a level's heading isn't left at the
      # bottom of one page with its formulas on the next.
      describe :pages do
        it "should keep everything on one page when it fits" do
          grouped = { 'consumables' => [ [ 1, %w(A B) ], [ 2, %w(C) ] ] }

          expect(PF2FormulaTemplate.pages(grouped, 3)).to eq [ [ [ 'consumables', 1, %w(A B) ], [ 'consumables', 2, %w(C) ] ] ]
        end

        it "should start a new page with a level group that would overflow this one" do
          grouped = { 'consumables' => [ [ 1, %w(A B) ], [ 2, %w(C D) ] ], 'runes' => [ [ 1, %w(E) ] ] }

          expect(PF2FormulaTemplate.pages(grouped, 3)).to eq [
            [ [ 'consumables', 1, %w(A B) ] ],
            [ [ 'consumables', 2, %w(C D) ], [ 'runes', 1, %w(E) ] ]
          ]
        end

        it "should split a level group longer than a page across pages of its own" do
          grouped = { 'consumables' => [ [ 1, %w(A) ], [ 2, %w(B C D E F) ] ] }

          expect(PF2FormulaTemplate.pages(grouped, 2)).to eq [
            [ [ 'consumables', 1, %w(A) ] ],
            [ [ 'consumables', 2, %w(B C) ] ],
            [ [ 'consumables', 2, %w(D E) ] ],
            [ [ 'consumables', 2, %w(F) ] ]
          ]
        end
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
