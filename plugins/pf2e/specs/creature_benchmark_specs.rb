require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Where a creature's figures sit for its level, by GM Core's tables (pp. 114-124), and which are above
    # the highest the book gives: those are flagged to their author and to the admins who approve them.
    describe CreatureBenchmarks do

      # A level 3 creature as the book's moderate column would make it.
      def block(**more)
        { 'level' => 3, 'ac' => 18, 'hp' => 45, 'perception' => 9, 'saves' => { 'fortitude' => 9, 'reflex' => 12, 'will' => 6 },
          'skills' => { 'Athletics' => 9 },
          'strikes' => [ { 'name' => 'Jaws', 'bonus' => 10, 'damage' => [ [ '1d8+6', 'piercing', nil ] ] } ],
          'actions' => [] }.merge(more.transform_keys(&:to_s))
      end

      def bands(held = block)
        CreatureBenchmarks.bands(held).to_h { |one| [ one['figure'], one['band'] ] }
      end

      it "should place each figure in its band for the level" do
        expect(bands).to include('AC' => 'moderate', 'Hit Points' => 'moderate', 'Perception' => 'moderate', 'Fortitude' => 'moderate',
                                 'Reflex' => 'high', 'Will' => 'low', 'Athletics' => 'moderate', 'Jaws attack' => 'moderate',
                                 'Jaws damage' => 'moderate')
      end

      it "should read a band at its own figure and between two" do
        expect(CreatureBenchmarks.band('ac', 3, 22)).to eq 'extreme'
        expect(CreatureBenchmarks.band('ac', 3, 20)).to eq 'high'
        expect(CreatureBenchmarks.band('ac', 3, 23)).to eq 'above extreme'
        expect(CreatureBenchmarks.band('ac', 3, 10)).to eq 'below low'
      end

      it "should read a range of Hit Points by its ends" do
        expect(CreatureBenchmarks.band('hp', 3, 59)).to eq 'high'
        expect(CreatureBenchmarks.band('hp', 3, 50)).to eq 'moderate'
        expect(CreatureBenchmarks.band('hp', 3, 70)).to eq 'above high'
      end

      it "should flag what is above the highest the book gives, and nothing else" do
        flagged = CreatureBenchmarks.warnings(block('ac' => 25, 'strikes' => [ { 'name' => 'Jaws', 'bonus' => 20, 'damage' => [ [ '4d12+10', 'piercing', nil ] ] } ]))

        expect(flagged.map { |one| one['args']['figure'] }).to eq [ 'AC', 'Jaws attack', 'Jaws damage' ]
        expect(flagged.map { |one| one['code'] }.uniq).to eq [ :creature_above ]
        expect(CreatureBenchmarks.warnings(block)).to eq []
      end

      it "should weigh an ability's damage against the book's area damage, limited where it waits" do
        breath = { 'name' => 'Breath', 'type' => 'action', 'cost' => 2, 'traits' => [],
                   'text' => 'Each creature in a cone takes 8d6 fire damage (DC 20 basic Reflex save).' }
        waits = breath.merge('text' => "#{breath['text']} It can't use Breath again for 1d4 rounds.")

        expect(bands(block('actions' => [ breath ]))['Breath damage']).to eq 'above unlimited use'
        expect(bands(block('actions' => [ waits ]))['Breath damage']).to eq 'above limited use'
      end

      it "should not weigh a creature past the levels the book's tables give" do
        expect(CreatureBenchmarks.bands(block('level' => 25, 'hp' => 600))).to eq []
      end

      it "should weigh an ability usable every round as unlimited, though it has a frequency" do
        each_round = { 'name' => 'Spray', 'type' => 'action', 'cost' => 1, 'traits' => [],
                       'text' => 'Frequency once per round%rEach creature in a cone takes 2d6 acid damage (DC 20 basic Reflex save).' }

        expect(bands(block('actions' => [ each_round ]))['Spray damage']).to eq 'unlimited use'
      end

      it "should hold every level from -1 to 24 in every table, each band no higher than the one above it" do
        CreatureBenchmarks.tables.each do |name, table|
          expect(table['levels'].keys.sort).to eq((-1..24).to_a), name

          table['levels'].each do |level, cells|
            tops = cells.map { |one| CreatureBenchmarks.top(one) }.compact
            expect(tops).to eq(tops.sort.reverse), "#{name} at level #{level}" unless name == 'spell' || name == 'resistance' || name == 'area_damage'
          end
        end
      end

      it "should agree with figures copied from the book" do
        expect(CreatureBenchmarks.tables['ac']['levels'][10]).to eq [ 33, 30, 29, 27 ]
        expect(CreatureBenchmarks.tables['strike_attack']['levels'][20]).to eq [ 40, 38, 36, 31 ]
        expect(CreatureBenchmarks.tables['hp']['levels'][1]).to eq [ [ 26, 24 ], [ 21, 19 ], [ 16, 14 ] ]
      end
    end
  end
end
