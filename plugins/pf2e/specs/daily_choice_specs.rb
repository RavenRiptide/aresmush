require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What picking, taking back and resting do to a character's daily choices, as data.
    describe DailyChoices do

      let(:day) { { 'switch' => 'longevity', 'pick' => 'skill', 'trains' => true, 'lasts' => 'day', 'source' => 'Ancestral Longevity' } }
      let(:held) { { 'switch' => 'swordpractice', 'pick' => 'weapon', 'lasts' => 'until_changed', 'source' => 'Egalrin Weapon Familiarity' } }

      describe "picking" do
        it "should lock the pick it makes, spelled as the option is" do
          result = DailyChoices.choose({}, 'longevity', day, %w{Athletics Stealth}, 'athletics')

          expect(result.ok?).to be true
          expect(result.state['longevity']).to eq('pick' => 'Athletics', 'source' => 'Ancestral Longevity', 'locked' => true)
        end

        it "should keep a feat's own choice with the pick" do
          result = DailyChoices.choose({}, 'flexibility', day, [ 'Advanced Weapon Training' ], 'advanced weapon training',
                                       'choice' => 'Sword')

          expect(result.state['flexibility']).to include('pick' => 'Advanced Weapon Training', 'choice' => 'Sword')
          expect(DailyChoices.label(result.state['flexibility'])).to eq 'Advanced Weapon Training (Sword)'
        end

        it "should refuse something not on offer" do
          result = DailyChoices.choose({}, 'longevity', day, %w{Athletics}, 'Arcana')

          expect(result.code).to eq :not_offered
        end

        it "should refuse a second pick before a rest" do
          picks = { 'longevity' => { 'pick' => 'Athletics', 'locked' => true } }

          expect(DailyChoices.choose(picks, 'longevity', day, %w{Stealth}, 'Stealth').code).to eq :already_picked
        end

        it "should replace a pick still in force from an earlier day, remembering it" do
          picks = { 'swordpractice' => { 'pick' => 'Longsword', 'locked' => false } }

          result = DailyChoices.choose(picks, 'swordpractice', held, %w{Katana Longsword}, 'Katana')

          expect(result.state['swordpractice']).to include('pick' => 'Katana', 'locked' => true, 'previous' => 'Longsword')
        end
      end

      describe "taking a pick back" do
        it "should open the choice again" do
          picks = { 'longevity' => { 'pick' => 'Athletics', 'locked' => true } }

          expect(DailyChoices.unchoose(picks, 'longevity', day).state).to eq({})
        end

        it "should put back the pick it replaced" do
          picks = { 'swordpractice' => { 'pick' => 'Katana', 'source' => 'Egalrin Weapon Familiarity', 'locked' => true,
                                         'previous' => 'Longsword' } }

          expect(DailyChoices.unchoose(picks, 'swordpractice', held).state['swordpractice'])
            .to eq('pick' => 'Longsword', 'source' => 'Egalrin Weapon Familiarity', 'locked' => false)
        end

        it "should refuse while a later pick counts it towards its prerequisites" do
          picks = { 'flexibility' => { 'pick' => 'Incredible Aim', 'locked' => true } }

          result = DailyChoices.unchoose(picks, 'flexibility', day, [ 'Improved Flexibility' ])

          expect(result.code).to eq :needed
        end

        it "should refuse when nothing was picked since the last rest" do
          picks = { 'swordpractice' => { 'pick' => 'Longsword', 'locked' => false } }

          expect(DailyChoices.unchoose(picks, 'swordpractice', held).code).to eq :nothing_picked
        end
      end

      describe "a rest" do
        let(:blocks) { { 'longevity' => day, 'swordpractice' => held } }
        let(:offered) { ->(_switch, _pick) { true } }

        it "should clear a pick that lasts a day" do
          kept, dropped = DailyChoices.rest({ 'longevity' => { 'pick' => 'Athletics', 'locked' => true } }, blocks, offered)

          expect([ kept, dropped ]).to eq [ {}, [] ]
        end

        it "should keep a pick that lasts until changed, unlocked" do
          picks = { 'swordpractice' => { 'pick' => 'Katana', 'locked' => true, 'previous' => 'Longsword' } }

          kept, _dropped = DailyChoices.rest(picks, blocks, offered)

          expect(kept).to eq('swordpractice' => { 'pick' => 'Katana', 'source' => 'Egalrin Weapon Familiarity', 'locked' => false })
        end

        it "should drop, and say, a pick that can no longer be made" do
          picks = { 'swordpractice' => { 'pick' => 'Katana', 'locked' => true } }

          kept, dropped = DailyChoices.rest(picks, blocks, ->(_switch, _pick) { false })

          expect(kept).to eq({})
          expect(dropped.map { |one| [ one['switch'], one['pick'] ] }).to eq [ [ 'swordpractice', 'Katana' ] ]
        end

        it "should drop a pick whose feat has gone" do
          kept, dropped = DailyChoices.rest({ 'swordpractice' => { 'pick' => 'Katana' } }, {}, offered)

          expect([ kept, dropped ]).to eq [ {}, [] ]
        end
      end
    end
  end
end
