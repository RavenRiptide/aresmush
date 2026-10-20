require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A saved creature built up a part at a time: `creature/set` and `creature/unset`, in the words of a
    # one-line description.
    describe CreatureDraft do

      def start
        Described.read('Bandit', 'ac 16 hp 30 fort 8; weak fire 5; traits human; strike club +9 1d6+4 bludgeoning; ' \
                                 'ability Rally [1]: It rallies.').state
      end

      def set(words, held = start)
        CreatureDraft.set(held, words)
      end

      it "should start it in a shape its abilities give it, and refuse one they do not" do
        wolf = Bestiary.entry('Werewolf')

        expect(set('shape animal', wolf).state['shape']).to eq 'animal'
        expect(set('shape dragon', wolf).code).to eq :described_shape
        expect(CreatureDraft.unset(set('shape animal', wolf).state, 'shape').state).to_not have_key('shape')
        expect(Described.write(set('shape animal', wolf).state)).to include('; shape animal')
      end

      it "should change the figures named and keep the rest" do
        held = set('ac 18 ref 7').state

        expect([ held['ac'], held['hp'], held['saves'] ]).to eq [ 18, 30, { 'fortitude' => 8, 'reflex' => 7, 'will' => 0 } ]
      end

      it "should replace a Strike or an ability of the same name, and add one of a new name" do
        held = set('strike Club +10 1d8+4 bludgeoning').state
        held = set('ability Charge [2]: It charges.', held).state

        expect(held['strikes'].map { |one| [ one['name'], one['bonus'] ] }).to eq [ [ 'Club', 10 ] ]
        expect(held['actions'].map { |one| one['name'] }).to eq [ 'Rally', 'Charge' ]
      end

      it "should add to its weaknesses, resistances, immunities, skills, senses and traits" do
        held = set('weak cold iron 3').state
        held = set('traits humanoid', held).state

        expect(held['weaknesses']).to eq('fire' => 5, 'cold-iron' => 3)
        expect(held['traits']).to eq [ 'human', 'humanoid' ]
      end

      it "should refuse words it cannot read, as a description would" do
        expect(set('strike club').code).to eq :described_strike
      end

      describe "taking a part off" do
        def unset(words, held = start)
          CreatureDraft.unset(held, words)
        end

        it "should take off a Strike, an ability, a weakness or a trait by its name" do
          expect(unset('strike club').state['strikes']).to eq []
          expect(unset('ability rally').state['actions']).to eq []
          expect(unset('weak fire').state['weaknesses']).to eq({})
          expect(unset('trait human').state['traits']).to eq []
        end

        it "should say when there is nothing of that name to take off" do
          expect(unset('strike bite').code).to eq :creature_nothing_to_unset
          expect(unset('wings').code).to eq :creature_nothing_to_unset
        end
      end
    end
  end
end
