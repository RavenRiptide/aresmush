require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A hit's damage of one type is added together before a resistance or weakness to it applies: a
    # rapier's piercing and a swashbuckler's precise strike are one piercing amount, and a bomb's splash
    # joins its fire.
    describe "a hit's damage by type" do
      it "should add the rows of a type together" do
        rows = [ { 'amount' => 14, 'type' => 'piercing', 'category' => nil },
                 { 'amount' => 5, 'type' => 'piercing', 'category' => 'precision' },
                 { 'amount' => 3, 'type' => 'fire', 'category' => nil } ]

        expect(DamageRoll.by_type(rows)).to eq [
          { 'amount' => 19, 'type' => 'piercing', 'categories' => [ 'precision' ], 'splash' => 0, 'formula' => nil, 'dice' => nil },
          { 'amount' => 3, 'type' => 'fire', 'categories' => [], 'splash' => 0, 'formula' => nil, 'dice' => nil } ]
      end

      it "should fold splash into the damage of its type" do
        rows = [ { 'amount' => 6, 'type' => 'fire', 'category' => nil },
                 { 'amount' => 2, 'type' => 'fire', 'category' => 'splash' } ]

        expect(DamageRoll.by_type(rows).map { |row| [ row['amount'], row['splash'] ] }).to eq [ [ 8, 2 ] ]
      end

      it "should keep splash of a type nothing else deals as splash" do
        rows = [ { 'amount' => 2, 'type' => 'fire', 'category' => 'splash' } ]

        expect(DamageRoll.by_type(rows).first['categories']).to eq [ 'splash' ]
      end
    end

    # Damage and healing say how their dice fell, as a check does.
    describe "how damage was rolled" do
      before(:each) do
        faces = [ 4, 8, 6, 3, 5, 1, 2, 6, 1 ]
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, _sides = 20| faces.shift(amount.to_i) }
      end

      it "should show each die and the flat amount" do
        expect(Pf2e.thrown_formula('3d8+24')).to eq('total' => 42, 'shown' => '3d8+24: 4, 8, 6 +24')
        expect(Pf2e.thrown_formula('6')).to eq('total' => 6, 'shown' => nil)
      end

      it "should say what a save made of the total" do
        row = DamageRoll.of_formulas([ [ '6d6', 'fire', nil ] ], false).first

        expect(DamageRoll.scaled_row(row, 0.5)).to include('amount' => 13, 'dice' => '6d6: 4, 8, 6, 3, 5, 1 = 27, halved')
      end

      it "should show a critical hit's doubling" do
        row = DamageRoll.of_formulas([ [ '1d8+4', 'slashing', nil ] ], true).first

        expect(row).to include('amount' => 16, 'dice' => '1d8+4: 4 +4 = 8, doubled')
      end
    end
  end
end
