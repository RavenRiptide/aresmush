require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # PF2e's bonus arithmetic. A figure is a base plus a list of modifiers, and the type on each
    # modifier decides which of them count - two item bonuses are the better one, not their sum.
    describe Modifiers do

      def mod(type, value, source = 'something')
        { 'source' => source, 'type' => type, 'value' => value }
      end

      def enabled(rows)
        rows.select { |row| row['enabled'] }.map { |row| row['source'] }
      end

      describe "untyped" do
        it "should count every one of them" do
          rows = Modifiers.stack([ mod('untyped', 1, 'a'), mod('untyped', 2, 'b') ])

          expect(enabled(rows)).to eq [ 'a', 'b' ]
          expect(Modifiers.total(rows)).to eq 3
        end
      end

      describe "the ordinary types" do
        it "should take the highest bonus of a type and switch the rest off" do
          rows = Modifiers.stack([ mod('item', 1, 'ring'), mod('item', 2, 'spell') ])

          expect(enabled(rows)).to eq [ 'spell' ]
          expect(Modifiers.total(rows)).to eq 2
        end

        it "should leave the overridden modifier on the list, for the breakdown" do
          rows = Modifiers.stack([ mod('item', 1, 'ring'), mod('item', 2, 'spell') ])

          expect(rows.size).to eq 2
          expect(rows.find { |row| row['source'] == 'ring' }['enabled']).to be false
        end

        it "should take the lowest penalty as well as the highest bonus" do
          rows = Modifiers.stack([ mod('status', 2, 'up'), mod('status', -1, 'small'),
                                   mod('status', -3, 'big') ])

          expect(enabled(rows)).to eq [ 'up', 'big' ]
          expect(Modifiers.total(rows)).to eq(-1)
        end

        it "should keep types apart, so an item bonus and a status bonus both count" do
          rows = Modifiers.stack([ mod('item', 1, 'ring'), mod('status', 1, 'blessing') ])

          expect(Modifiers.total(rows)).to eq 2
        end

        it "should count a zero as neither bonus nor penalty" do
          rows = Modifiers.stack([ mod('item', 0, 'nothing') ])

          expect(enabled(rows)).to eq []
        end

        it "should break a tie by the order it was given, so a total is not luck" do
          rows = Modifiers.stack([ mod('item', 2, 'first'), mod('item', 2, 'second') ])

          expect(enabled(rows)).to eq [ 'first' ]
        end
      end

      # This is what makes "use your best attribute for AC" fall out rather than being special-cased:
      # offer both attributes as ability modifiers and the better one applies alone.
      describe "attribute modifiers" do
        it "should take the best one and no other" do
          rows = Modifiers.stack([ mod('ability', 2, 'dex'), mod('ability', 4, 'cha') ])

          expect(enabled(rows)).to eq [ 'cha' ]
          expect(Modifiers.total(rows)).to eq 4
        end

        it "should take the least bad when every attribute is a penalty" do
          rows = Modifiers.stack([ mod('ability', -1, 'dex'), mod('ability', -3, 'str') ])

          expect(enabled(rows)).to eq [ 'dex' ]
          expect(Modifiers.total(rows)).to eq(-1)
        end

        it "should count a zero attribute modifier, which is a real score" do
          rows = Modifiers.stack([ mod('ability', 0, 'dex') ])

          expect(enabled(rows)).to eq [ 'dex' ]
        end
      end

      describe "a figure and its arithmetic" do
        it "should report the base, the total and the rows together" do
          result = Modifiers.breakdown(12, [ mod('item', 1, 'ring'), mod('status', -2, 'frightened') ])

          expect(result['base']).to eq 12
          expect(result['total']).to eq 11
          expect(result['modifiers'].size).to eq 2
        end

        it "should be the base alone when nothing modifies it" do
          expect(Modifiers.breakdown(12, [])['total']).to eq 12
        end
      end

      # Proficiency is the other half of every figure's base, and a rank spelled some way the table
      # does not know used to be `nil + level`.
      describe "a proficiency rank we do not know" do
        it "should read it as untrained rather than raise" do
          allow(Global).to receive(:logger).and_return(double(:warn => nil))
          allow(Pf2e).to receive(:has_feat?).and_return(false)
          char = double(:pf2_level => 5)

          expect(Pf2e.get_prof_bonus(char, 'exprt')).to eq 0
        end

        it "should say so in the log" do
          logger = double
          allow(Global).to receive(:logger).and_return(logger)
          allow(Pf2e).to receive(:has_feat?).and_return(false)

          expect(logger).to receive(:warn).with(/proficiency rank/)

          Pf2e.get_prof_bonus(double(:pf2_level => 5), 'exprt')
        end

        it "should read a missing rank as untrained without complaining" do
          allow(Pf2e).to receive(:has_feat?).and_return(false)

          expect(Pf2e.get_prof_bonus(double(:pf2_level => 5), nil)).to eq 0
        end
      end

      describe "a type we do not know" do
        it "should count it rather than lose it" do
          allow(Global).to receive(:logger).and_return(double(:warn => nil))

          rows = Modifiers.stack([ mod('cirmcumstance', 2, 'typo') ])

          expect(Modifiers.total(rows)).to eq 2
        end

        it "should say so in the log" do
          logger = double
          allow(Global).to receive(:logger).and_return(logger)

          expect(logger).to receive(:warn).with(/unknown type/)

          Modifiers.stack([ mod('cirmcumstance', 2, 'typo') ])
        end
      end
    end
  end
end
