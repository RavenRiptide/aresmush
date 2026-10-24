require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Encounters

      # Moving through an initiative order. `at` is one past whoever's turn it is.
      describe Turn do

        def move(direction, at:, round: 3, size: 4)
          Turn.move(direction, :size => size, :at => at, :round => round)
        end

        describe "forwards" do
          it "should take the next turn in the order" do
            result = move('next', :at => 1)

            expect(result.state['current']).to eq 1
            expect(result.state['upcoming']).to eq 2
            expect(result.state['new_round']).to be false
            expect(result.state['round']).to eq 3
          end

          it "should start a new round when the order wraps" do
            result = move('next', :at => 0)

            expect(result.state['round']).to eq 4
            expect(result.state['new_round']).to be true
          end

          it "should wrap the upcoming turn back to the top" do
            expect(move('next', :at => 3).state['upcoming']).to eq 0
          end
        end

        describe "backwards" do
          # The turn is the third in the order; backing up makes it the second's.
          it "should take the turn before this one" do
            result = move('prev', :at => 3)

            expect(result.state['current']).to eq 1
            expect(result.state['upcoming']).to eq 2
            expect(result.state['new_round']).to be false
          end

          it "should undo a move forwards" do
            forwards = move('next', :at => 2)
            back = move('prev', :at => forwards.state['upcoming'])

            expect(back.state['upcoming']).to eq 2
          end

          # The turn is the last in the order, and `at` has wrapped to the top: it is still this round.
          it "should back up from the last turn without changing the round" do
            result = move('prev', :at => 0)

            expect(result.state['current']).to eq 2
            expect(result.state['new_round']).to be false
          end

          it "should back into the previous round from the round's first turn" do
            result = move('prev', :at => 1)

            expect(result.state['current']).to eq 3
            expect(result.state['upcoming']).to eq 0
            expect(result.state['round']).to eq 2
            expect(result.state['new_round']).to be true
          end

          it "should stay in range for an order of one" do
            result = move('prev', :at => 0, :size => 1)

            expect(result.state['current']).to eq 0
            expect(result.state['upcoming']).to eq 0
          end
        end

        describe "what it refuses" do
          it "should refuse an empty order" do
            expect(move('next', :at => 0, :size => 0).code).to eq :no_participants
          end

          it "should refuse a direction it does not have" do
            expect(move('sideways', :at => 0).code).to eq :unknown_direction
          end
        end

        it "should have a locale entry for each direction's label" do
          locale = YAML.load_file(File.join(Pf2e.plugin_dir, 'locales', 'locale_en.yml'))['en']['pf2e']
          labels = Turn::DIRECTIONS.values.map { |row| row['label'].sub('pf2e.', '') }

          expect(labels.reject { |key| locale.key?(key) }).to eq []
        end
      end
    end
  end
end
