require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The d20 of every check, from `roll` or from an encounter, is rolled here.
    describe Resolve do

      def check(keep: nil, substitution: nil)
        one = double('check', :roll_twice => keep, :substitution => substitution)
        allow(one).to receive(:substituted=)
        one
      end

      let(:assurance) { { 'slug' => 'assurance', 'label' => 'Assurance', 'value' => 10, 'effect_type' => 'fortune' } }

      it "should roll twice and keep the higher for fortune, the lower for misfortune" do
        allow(Pf2e).to receive(:roll_dice).and_return([ 15 ], [ 7 ], [ 15 ], [ 7 ])

        expect(Resolve.d20([ check(:keep => 'keep-higher') ])).to include('die' => 15, 'dice' => [ 15, 7 ])
        expect(Resolve.d20([ check(:keep => 'keep-lower') ])).to include('die' => 7, 'dice' => [ 15, 7 ])
      end

      it "should let a substitution stand in for the die, with no natural face" do
        rolled = Resolve.d20([ check(:substitution => assurance) ])

        expect(rolled).to include('die' => nil, 'face' => 10, 'substitution' => assurance)
      end

      it "should cancel a fortune substitution against misfortune, and roll once" do
        allow(Pf2e).to receive(:roll_dice).and_return([ 12 ])

        rolled = Resolve.d20([ check(:keep => 'keep-lower', :substitution => assurance) ])

        expect(rolled).to include('die' => 12, 'dice' => [ 12 ], 'kept' => nil, 'substitution' => nil)
      end

      it "should cancel fortune on one check against misfortune on another" do
        expect(Resolve.roll_twice([ check(:keep => 'keep-higher'), check(:keep => 'keep-lower') ])).to be_nil
      end

      it "should measure a degree with the adjustments it is handed, and none without a DC" do
        expect(Resolve.degree([ { 'all' => 'to-critical-failure' } ], 40, 15, nil)).to eq Degree::CRITICAL_FAILURE
        expect(Resolve.degree([], 40, nil, nil)).to be_nil
      end
    end
  end
end
