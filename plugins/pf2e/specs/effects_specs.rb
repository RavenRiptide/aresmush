require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # `modifies:` - how a feat, an item or a condition says that it changes a number. The thing that
    # has the effect carries the effect, so the engine never learns that Toughness exists.
    describe Effects do

      def source(rows, value = nil)
        { 'name' => 'Something', 'modifies' => rows, 'source' => value ? { 'value' => value } : {} }
      end

      def context(level = 5)
        { 'actor' => { 'level' => level, 'abilities' => { 'con' => { 'mod' => 3 } } } }
      end

      it "should take a row whose domain the statistic has" do
        rows = Effects.modifiers([ source([ { 'domain' => 'hp', 'value' => 4 } ]) ], [ 'hp' ], context)

        expect(rows.size).to eq 1
        expect(rows.first['value']).to eq 4
      end

      it "should skip a row whose domain the statistic does not have" do
        expect(Effects.modifiers([ source([ { 'domain' => 'ac', 'value' => 4 } ]) ], [ 'hp' ], context))
          .to eq []
      end

      it "should read a formula against the character" do
        rows = Effects.modifiers([ source([ { 'domain' => 'hp', 'value' => '@actor.level' } ]) ],
                                 [ 'hp' ], context(7))

        expect(rows.first['value']).to eq 7
      end

      # A condition's value is what scales it, so Frightened 3 and Frightened 1 are the same row.
      it "should read the source's own value" do
        rows = Effects.modifiers([ source([ { 'domain' => 'all', 'value' => '-@source.value' } ], 3) ],
                                 [ 'all' ], context)

        expect(rows.first['value']).to eq(-3)
      end

      it "should read a formula over both roots at once, which is how Drained scales" do
        rows = Effects.modifiers(
          [ source([ { 'domain' => 'hp', 'value' => '-@source.value * @actor.level' } ], 2) ],
          [ 'hp' ], context(5))

        expect(rows.first['value']).to eq(-10)
      end

      it "should carry the type through so stacking can use it" do
        rows = Effects.modifiers([ source([ { 'domain' => 'hp', 'type' => 'Status', 'value' => 1 } ]) ],
                                 [ 'hp' ], context)

        expect(rows.first['type']).to eq 'status'
      end

      # Untyped is the permissive reading, so a row that forgets to say counts rather than vanishing.
      it "should default to untyped" do
        rows = Effects.modifiers([ source([ { 'domain' => 'hp', 'value' => 1 } ]) ], [ 'hp' ], context)

        expect(rows.first['type']).to eq 'untyped'
      end

      it "should name the source, so a breakdown can say where the number came from" do
        rows = Effects.modifiers([ source([ { 'domain' => 'hp', 'value' => 1 } ]) ], [ 'hp' ], context)

        expect(rows.first['source']).to eq 'Something'
      end

      it "should take every matching row from every source" do
        two = [ source([ { 'domain' => 'hp', 'value' => 1 }, { 'domain' => 'hp', 'value' => 2 } ]),
                source([ { 'domain' => 'hp', 'value' => 4 } ]) ]

        expect(Effects.modifiers(two, [ 'hp' ], context).map { |row| row['value'] }).to eq [ 1, 2, 4 ]
      end

      it "should contribute nothing for a source with no rows" do
        expect(Effects.modifiers([ { 'name' => 'Plain' } ], [ 'hp' ], context)).to eq []
      end

      # Most item bonuses are conditional, and a row whose circumstances are unmet is reported rather
      # than counted - `Pf2e::Stat` keeps it out of the stacking and lists it as conditional.
      describe "a row with circumstances" do
        def conditional
          source([ { 'domain' => 'thievery', 'type' => 'item', 'value' => 2,
                     'when' => [ 'action:pick-a-lock' ] } ])
        end

        it "should be met when the circumstances are named" do
          rows = Effects.modifiers([ conditional ], [ 'thievery' ], context, [ 'action:pick-a-lock' ])

          expect(rows.first['met']).to be true
        end

        it "should be unmet when they are not" do
          rows = Effects.modifiers([ conditional ], [ 'thievery' ], context, [])

          expect(rows.first['met']).to be false
        end

        it "should still report the row and what it needs" do
          rows = Effects.modifiers([ conditional ], [ 'thievery' ], context, [])

          expect(rows.first['value']).to eq 2
          expect(rows.first['when']).to eq [ 'action:pick-a-lock' ]
        end

        it "should be met when there are no circumstances to meet" do
          rows = Effects.modifiers([ source([ { 'domain' => 'hp', 'value' => 1 } ]) ], [ 'hp' ], context)

          expect(rows.first['met']).to be true
        end

        # A predicate on an item's own rule often asks about that item, so a source may carry its own
        # options alongside the ones the roller supplied.
        it "should test a source's own options too" do
          lens = conditional.merge('options' => [ 'action:pick-a-lock' ])

          expect(Effects.modifiers([ lens ], [ 'thievery' ], context, []).first['met']).to be true
        end
      end

      # A key nothing reads is a rule that silently does nothing, which is the failure this vocabulary
      # exists to prevent.
      describe "a key nothing reads" do
        it "should say so in the log" do
          logger = double
          allow(Global).to receive(:logger).and_return(logger)

          expect(logger).to receive(:warn).with(/keys nothing reads: unless/)

          Effects.modifiers([ source([ { 'domain' => 'hp', 'value' => 1,
                                        'unless' => 'something' } ]) ], [ 'hp' ], context)
        end
      end
    end
  end
end
