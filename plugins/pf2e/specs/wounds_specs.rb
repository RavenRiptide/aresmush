require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # How hurt a creature looks to a player, who doesn't see its hit points.
    describe "how hurt someone looks" do
      it "should be unhurt with every hit point" do
        expect(Harm.wound(20, 20)).to eq :unhurt
      end

      it "should be bloodied with any damage, down to more than a quarter left" do
        expect(Harm.wound(19, 20)).to eq :bloodied
        expect(Harm.wound(6, 20)).to eq :bloodied
      end

      it "should be near death at a quarter left or less" do
        expect(Harm.wound(5, 20)).to eq :near_death
        expect(Harm.wound(1, 20)).to eq :near_death
      end

      it "should be dead with no hit points left" do
        expect(Harm.wound(0, 20)).to eq :dead
        expect(Harm.wound(-3, 20)).to eq :dead
      end

      it "should have a word for each" do
        Harm::WOUNDS.each_value { |key| expect(key).to start_with('pf2e.wounds_') }
        expect(Harm::WOUNDS.keys).to eq %i{unhurt bloodied near_death dead}
      end
    end
  end
end
