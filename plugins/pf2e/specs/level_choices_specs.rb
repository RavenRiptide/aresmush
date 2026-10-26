require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A feat's repeat picks: named choices that open again on later levels, each with its own count
    # and pool, so Cauldron's later formulas are one of that level and not four 1st-level ones.
    describe :level_choices do

      def cauldron
        {
          'feat_choice' => { 'count' => 4, 'from_formulas' => { 'traits' => [ 'oil', 'potion' ], 'max_level' => 1 } },
          'level_choices' => {
            'Cauldron Formulas' => {
              'levels' => { 'from' => 4, 'every' => 2 },
              'from_formulas' => { 'traits' => [ 'oil', 'potion' ], 'max_level' => 'level' }
            }
          }
        }
      end

      it "should be due from its first level, every so many levels" do
        expect((1..12).select { |level| Pf2e.level_choices_due(cauldron, level).any? }).to eq [ 4, 6, 8, 10, 12 ]
      end

      it "should be due every level when it names no step, and on listed levels when it lists them" do
        every = { 'level_choices' => { 'Scholar' => { 'levels' => { 'from' => 2 } } } }
        listed = { 'level_choices' => { 'Listed' => { 'levels' => [ 3, 7 ] } } }

        expect((1..5).select { |level| Pf2e.level_choices_due(every, level).any? }).to eq [ 2, 3, 4, 5 ]
        expect((1..10).select { |level| Pf2e.level_choices_due(listed, level).any? }).to eq [ 3, 7 ]
      end

      it "should answer nothing for a feat with no repeat picks" do
        expect(Pf2e.level_choices_due({ 'feat_choice' => {} }, 4)).to eq({})
        expect(Pf2e.level_choices_due(nil, 4)).to eq({})
      end

      describe :held_level_choice_block do
        before(:each) do
          allow(Global).to receive(:read_config).and_call_original
          allow(Global).to receive(:read_config).with('pf2e_feats').and_return('Cauldron' => cauldron)
        end

        def holding(feats)
          char = double(:name => 'Someone')
          allow(DraftSheet).to receive(:of).with(char).and_return(double(:feat_names => feats))
          char
        end

        it "should find a repeat pick's block among the feats the character holds" do
          block = Pf2e.held_level_choice_block(holding([ 'Cauldron' ]), 'cauldron formulas')

          expect(block['from_formulas']['max_level']).to eq 'level'
        end

        it "should find nothing for a character without the feat" do
          expect(Pf2e.held_level_choice_block(holding([ 'Assurance' ]), 'Cauldron Formulas')).to be_nil
        end
      end
    end
  end
end
