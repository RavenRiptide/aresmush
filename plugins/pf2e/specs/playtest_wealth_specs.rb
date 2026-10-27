require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # selfaward/gold pays GM Core's lump sum for a new character, less the 15 gp every character
    # already holds - read from the shipped config, so a typo in the table fails here.
    describe "playtest starting wealth" do

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e', 'playtest_wealth').and_return(
          YAML.load_file(File.expand_path('../../../game/config/pf2e_options.yml', __dir__))['pf2e']['playtest_wealth']
        )
      end

      it "should owe a level 1 character nothing, since approval already paid the 15 gp" do
        expect(Pf2e.playtest_wealth_owed(1)).to eq 0
      end

      it "should owe the lump sum less 15 gp, in copper" do
        expect(Pf2e.playtest_wealth_owed(2)).to eq 1500
        expect(Pf2e.playtest_wealth_owed(5)).to eq 25500
        expect(Pf2e.playtest_wealth_owed(20)).to eq 11_198_500
      end

      it "should cover every level from 1 to 20" do
        (2..20).each { |level| expect(Pf2e.playtest_wealth_owed(level)).to be_positive }
      end

      it "should owe nothing at a level the table does not name" do
        expect(Pf2e.playtest_wealth_owed(0)).to eq 0
        expect(Pf2e.playtest_wealth_owed(21)).to eq 0
      end
    end
  end
end
