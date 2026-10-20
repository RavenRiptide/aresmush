require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a revision changed, as its summary says it.
    describe "a revision's summary" do
      def block(**more)
        { 'ac' => 18, 'hp' => 40, 'level' => 3, 'saves' => { 'fortitude' => 9 } }.merge(more.transform_keys(&:to_s))
      end

      it "should name each figure that moved, and the shape it starts in" do
        expect(Creatures.changes(block, block(:ac => 19))).to eq 'AC 18 to 19'
        expect(Creatures.changes(block, block(:shape => 'animal'))).to eq 'starting shape - to animal'
        expect(Creatures.changes(block, block)).to eq 'no change'
      end
    end
  end
end
