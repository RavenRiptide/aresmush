require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The bestiary as imported: what the engine reads of each creature it can read.
    describe "the bestiary's data" do

      it "should give every Strike damage the game can roll" do
        unreadable = Bestiary.index.keys.flat_map do |name|
          Array(Bestiary.entry(name)['strikes']).flat_map do |strike|
            Array(strike['damage']).reject { |formula, _type, _category| CreatureCheck.formula?(formula) }
                                   .map { |formula, _type, _category| "#{name}: #{strike['name']} #{formula}" }
          end
        end

        expect(unreadable).to eq []
      end
    end
  end
end
