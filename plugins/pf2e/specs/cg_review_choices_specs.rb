require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The Class Features & Other Choices section of cg/review: every choice chargen opened, with what
    # has been picked and how many picks are left.
    describe PF2CGReviewLockDisplay do

      def rows(pending)
        PF2CGReviewLockDisplay.choice_rows(pending) { |name| "what #{name} offers" }
      end

      it "should count what is left and keep what is picked" do
        found = rows("Alchemical Crafting" => [ 'Glow Rod', 'Acid Flask (Lesser)', 'open', 'open' ])

        expect(found).to eq [ { :choice => 'Alchemical Crafting', :picked => [ 'Acid Flask (Lesser)', 'Glow Rod' ],
                                :open => 2, :summary => 'what Alchemical Crafting offers' } ]
      end

      it "should keep a finished choice beside an open one, in name order" do
        found = rows("Witch's Hex" => [ 'Phase Familiar' ], 'Natural Ambition' => [ 'open' ])

        expect(found.map { |row| [ row[:choice], row[:open] ] }).to eq [ [ 'Natural Ambition', 1 ], [ "Witch's Hex", 0 ] ]
      end

      it "should list class features once each, by the specialty's version where there is one" do
        char = double(:pf2_features => { 'charclass_features' => [ 'Versatile Vials', 'Fifth Doctrine', 'Fifth Doctrine (Cloistered)', 'Advanced Alchemy' ] })

        expect(Pf2e.feature_display_list(char, 'charclass_features')).to eq [ 'Advanced Alchemy', 'Fifth Doctrine (Cloistered)', 'Versatile Vials' ]
        expect(Pf2e.feature_display_list(char, 'archetype_features')).to eq []
      end

      it "should show nothing once every choice is made" do
        expect(PF2CGReviewLockDisplay.any_open?(rows("Witch's Hex" => [ 'Phase Familiar' ]))).to be false
        expect(PF2CGReviewLockDisplay.any_open?(rows('Natural Ambition' => [ 'open' ]))).to be true
      end
    end
  end
end
