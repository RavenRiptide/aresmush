require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A block as the browser sends it, which anyone may craft: cleaned into one the engine reads, whatever
    # its shape, and never raising.
    describe CreatureBlock do

      def cleaned(raw, base = nil)
        CreatureBlock.cleaned(raw, base)
      end

      it "should keep a resistance's value, exceptions and doubling, and nothing else of it" do
        held = cleaned('resistances' => { 'physical' => { 'value' => '5', 'except' => [ 'silver' ], 'double' => [ 'non-magical' ], 'rules' => [ {} ] },
                                          'fire' => '10', 'cold' => [ 5 ], 'acid' => true, 'void' => { 'value' => {} } })

        expect(held['resistances']).to eq('physical' => { 'value' => 5, 'except' => [ 'silver' ], 'double' => [ 'non-magical' ] }, 'fire' => 10)
      end

      it "should take a block of any wrong shape without raising" do
        [ 'x', [ 1 ], { 'strikes' => 'x', 'actions' => [ 'x', 5 ], 'saves' => { 'will' => [ 1 ] }, 'skills' => 'x',
                        'spellcasting' => [ { 'spells' => 'x', 'slots' => [ 1 ] } ], 'level' => [ 1 ], 'traits' => 'x',
                        'strikes2' => nil, 'shield' => 'x' },
          { 'strikes' => [ { 'name' => 'Jaws', 'bonus' => [ 1 ], 'damage' => [ 'x', [ '1d6' ] ], 'range' => {}, 'traits' => 'x' } ],
            'actions' => [ { 'name' => 'Rally', 'cost' => [ 2 ], 'text' => { 'a' => 1 } } ] } ].each do |raw|
          expect { CreatureCheck.errors(cleaned(raw)) }.to_not raise_error
        end
      end

      it "should keep each list and each word to a stat block's size" do
        held = cleaned('traits' => Array.new(500) { |i| "t#{i}" }, 'hp_details' => 'x' * 100_000,
                       'strikes' => [ { 'name' => 'Jaws', 'effects' => Array.new(100) { 'Grab' }, 'damage' => [ [ '1d6', 'piercing', nil ] ] } ])

        expect([ held['traits'].size, held['hp_details'].size, held['strikes'].first['effects'].size ]).to eq [ CreatureBlock::MOST_LISTED, CreatureBlock::LONGEST, CreatureBlock::MOST_LISTED ]
      end
    end

    describe "a damage formula" do
      FORMULAS = { '1d6+4' => true, '2d8' => true, '12' => true, '1d0' => false, '0d6' => false,
                   '99999999d99999999' => false, '51d6' => false, '1d6+100000' => false }.freeze

      FORMULAS.each do |formula, fine|
        it "should #{fine ? 'take' : 'refuse'} #{formula}" do
          expect(CreatureCheck.formula?(formula)).to eq fine
        end
      end

      it "should refuse one a description gives that the game could not roll" do
        expect(Described.read('Bandit', 'ac 15 hp 20; strike jaws +5 99999999d99999999 piercing').code).to eq :described_strike
      end
    end
  end
end
