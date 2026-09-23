require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What initiative is rolled on: Perception, a skill, or an ability, as a player types it.
    describe "the statistic initiative is rolled on" do

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_skills').and_return('Stealth' => {}, 'Society' => {}, 'Survival' => {})
      end

      it "should take a name in any case" do
        expect(Pf2e.initiative_stat('stealth')).to eq 'Stealth'
        expect(Pf2e.initiative_stat('PERCEPTION')).to eq 'Perception'
        expect(Pf2e.initiative_stat('dexterity')).to eq 'Dexterity'
      end

      it "should take an ability's three letters" do
        expect(Pf2e.initiative_stat('dex')).to eq 'Dexterity'
        expect(Pf2e.initiative_stat('Wis')).to eq 'Wisdom'
      end

      it "should take the start of a name only one statistic has" do
        expect(Pf2e.initiative_stat('stea')).to eq 'Stealth'
        expect(Pf2e.initiative_stat('perc')).to eq 'Perception'
      end

      it "should refuse the start of several names, or of none" do
        expect(Pf2e.initiative_stat('s')).to be_nil
        expect(Pf2e.initiative_stat('flying')).to be_nil
        expect(Pf2e.initiative_stat('(')).to be_nil
      end
    end
  end
end
