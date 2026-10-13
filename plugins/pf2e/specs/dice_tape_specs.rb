require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The dice of one change, kept so the change can be made again with every die as it fell but one.
    describe DiceTape do

      # The dice that would be thrown, in order.
      def thrown(*faces)
        waiting = faces.flatten

        allow(Pf2e).to receive(:throw_dice) { |amount, _sides| waiting.shift(amount.to_i) }
      end

      def check(who, kept = nil)
        DiceTape.for_check(who, kept) { Pf2e.roll_dice(1, 20).first }
      end

      # An ability's damage, then a save from each of two heroes, as a GM's one command rolls them.
      def breath
        [ Pf2e.roll_dice(2, 6), check('Aria'), check('Bren') ]
      end

      it "should keep each roll, and whose check a d20 was" do
        thrown(3, 4, 7, 15)

        tape = DiceTape.recording { breath }

        expect(tape).to eq [ { 'n' => 2, 'd' => 6, 'faces' => [ 3, 4 ] },
                             { 'n' => 1, 'd' => 20, 'faces' => [ 7 ], 'who' => 'Aria' },
                             { 'n' => 1, 'd' => 20, 'faces' => [ 15 ], 'who' => 'Bren' } ]
      end

      it "should keep nothing where nothing is recording, and roll all the same" do
        thrown(3, 4, 7, 15)

        expect(breath).to eq [ [ 3, 4 ], 7, 15 ]
      end

      it "should say which of someone's checks was their last, or that they made none" do
        thrown(3, 4, 7, 15)
        tape = DiceTape.recording { breath }

        expect(DiceTape.last_check(tape, 'Aria')).to include('faces' => [ 7 ])
        expect(DiceTape.last_check(tape, 'Cael')).to be_nil
      end

      describe "made again" do
        before(:each) do
          thrown(3, 4, 7, 15)
          @tape = DiceTape.recording { breath }
        end

        it "should roll the one check afresh and leave every other die as it fell" do
          thrown(18)
          rolled = nil

          again = DiceTape.recording { DiceTape.replaying(@tape, :who => 'Aria') { rolled = breath } }

          expect(rolled).to eq [ [ 3, 4 ], 18, 15 ]
          expect(again[1]).to eq('n' => 1, 'd' => 20, 'faces' => [ 18 ], 'who' => 'Aria', 'hero' => true)
        end

        it "should put a face in place of the check where one is given" do
          thrown
          rolled = nil

          DiceTape.replaying(@tape, :who => 'Aria', :face => 17) { rolled = breath }

          expect(rolled).to eq [ [ 3, 4 ], 17, 15 ]
        end

        it "should change only the last of several checks by the same one" do
          thrown(2, 9)
          tape = DiceTape.recording { [ check('Aria'), check('Aria') ] }
          thrown(20)
          rolled = nil

          DiceTape.replaying(tape, :who => 'Aria') { rolled = [ check('Aria'), check('Aria') ] }

          expect(rolled).to eq [ 2, 20 ]
        end

        it "should roll afresh what was not rolled the first time, and move nobody else's die" do
          thrown(18, 5)
          rolled = nil

          # Aria's new result has her burn, which rolls a die nothing rolled before.
          DiceTape.replaying(@tape, :who => 'Aria') do
            rolled = [ Pf2e.roll_dice(2, 6), check('Aria'), Pf2e.roll_dice(1, 4), check('Bren') ]
          end

          expect(rolled).to eq [ [ 3, 4 ], 18, [ 5 ], 15 ]
        end

        it "should keep a later die where an earlier roll is no longer made" do
          thrown(6, 3, 15)
          tape = DiceTape.recording { [ check('Aria'), Pf2e.roll_dice(1, 4), check('Bren') ] }
          thrown(19)
          rolled = nil

          # Aria's new result spares her the d4 the first one cost her.
          DiceTape.replaying(tape, :who => 'Aria') { rolled = [ check('Aria'), check('Bren') ] }

          expect(rolled).to eq [ 19, 15 ]
        end

        it "should leave nothing behind it" do
          DiceTape.replaying(@tape, :who => 'Aria', :face => 17) { breath }
          thrown(1, 1, 2, 3)

          expect(breath).to eq [ [ 1, 1 ], 2, 3 ]
        end
      end

      it "should keep that a check was rolled twice for fortune or misfortune" do
        thrown(4, 16)

        tape = DiceTape.recording { DiceTape.for_check('Aria', 'keep-higher') { [ Pf2e.roll_dice(1, 20), Pf2e.roll_dice(1, 20) ] } }

        expect(tape.map { |row| row['kept'] }).to eq [ 'keep-higher', 'keep-higher' ]
      end
    end
  end
end
