require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The order writes to one path are made in. A row's `priority` decides it, lowest first, and a row
    # without one takes its mode's, as Foundry's do: a multiply, then an add, a downgrade, an upgrade, and
    # an override last.
    describe "the order of written values" do

      def source(name, *rows)
        path = 'system.attributes.familiarAbilities.value'

        { 'name' => name, 'rules' => rows.map { |row| { 'key' => 'ActiveEffectLike', 'path' => path }.merge(row) } }
      end

      def order(*sources)
        Rules.writes(sources, []).map { |write| write['source'] }
      end

      it "should put an add before an upgrade when neither names a priority" do
        written = order(source('Upgrade', 'mode' => 'upgrade', 'value' => 2), source('Add', 'mode' => 'add', 'value' => 1))

        expect(written).to eq [ 'Add', 'Upgrade' ]
      end

      # Pet sets the familiar's base ability count at 19, before Leshy Familiar Secrets adds one at its add's 20.
      it "should put an upgrade that names a lower priority before an add" do
        written = order(source('Leshy Familiar Secrets', 'mode' => 'add', 'value' => 1),
                        source('Pet', 'mode' => 'upgrade', 'value' => 2, 'priority' => 19))

        expect(written).to eq [ 'Pet', 'Leshy Familiar Secrets' ]
      end

      it "should keep the order rows were gathered in when their priorities tie" do
        written = order(source('First', 'mode' => 'upgrade', 'value' => 4, 'priority' => 9),
                        source('Second', 'mode' => 'upgrade', 'value' => 2, 'priority' => 9),
                        source('Third', 'mode' => 'upgrade', 'value' => 6, 'priority' => 9))

        expect(written).to eq [ 'First', 'Second', 'Third' ]
      end

      it "should put a mode it doesn't know last" do
        written = order(source('Unknown', 'mode' => 'sideways', 'value' => 1), source('Override', 'mode' => 'override', 'value' => 0))

        expect(written).to eq [ 'Override', 'Unknown' ]
      end

      it "should carry the priority on the write" do
        write = Rules.writes([ source('Pet', 'mode' => 'upgrade', 'value' => 2, 'priority' => 19) ], []).first

        expect(write['priority']).to eq 19
      end

      # The count as `Paths::MODES` folds it: the base set first, then everything added on top.
      it "should come to the base plus the bonus" do
        writes = Rules.writes([ source('Leshy Familiar Secrets', 'mode' => 'add', 'value' => 1),
                                source('Enhanced Familiar', 'mode' => 'upgrade', 'value' => 4, 'priority' => 9),
                                source('Pet', 'mode' => 'upgrade', 'value' => 2, 'priority' => 19) ], [])

        total = writes.reduce(0) { |held, write| Paths::MODES[write['mode']].call(held, write['value']) }

        expect(total).to eq 5
      end
    end
  end
end
