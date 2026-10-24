require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Whose a check's d20 is, for the record of a change's dice: a creature's is never taken for a
    # character's of the same name.
    describe "the roller of a check" do
      it "should be a character by name" do
        check = double('check', :char => double('character', :name => 'Wolf'))

        expect(Resolve.roller([ check ])).to eq 'Wolf'
      end

      it "should be a creature by name, apart from any character of that name" do
        npc = Pf2eNpc.new
        allow(npc).to receive(:name).and_return('Wolf')

        expect(Resolve.roller([ double('check', :char => npc) ])).to eq 'creature:Wolf'
      end

      it "should be nobody for a roll with no check in it" do
        expect(Resolve.roller([])).to be_nil
      end
    end
  end
end
