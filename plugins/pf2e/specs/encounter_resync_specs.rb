require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # `+e/resync <who>`: the GM brings a character's gear and money in the encounter up to their sheet, as
    # a change on its history.
    describe "resyncing what a character carries", :dbtest => true do
      include FightBench

      before(:each) { bench! }
      after(:each) do
        PF2Weapon.find(:character_id => @hero.id).each(&:delete)
        clear_bench!
      end

      def carried
        Pf2egear::Inventory.held(hero, 'weapons').map(&:name)
      end

      it "should bring in what they bought, and be taken back by undo" do
        PF2Weapon.create(:name => 'Falchion', :equipped => true, :character => @hero)

        run(PF2EncounterResyncCmd, "e/resync #{@hero.name}")

        expect(refused).to eq []
        expect(carried).to eq [ 'Falchion' ]
        expect(heard).to include(@hero.name)

        run(PF2EncounterUndoCmd, 'e/undo')

        expect(carried).to eq []
      end

      it "should be the GM's alone" do
        run(PF2EncounterResyncCmd, "e/resync #{@hero.name}", @hero)

        expect(refused.join).to include(t('pf2e.not_organizer'))
      end

      it "should refuse a creature" do
        add('goblin warrior')
        run(PF2EncounterResyncCmd, 'e/resync #2')

        expect(refused).to eq [ t('pf2e.encounter_sheet_creature', :ref => '#2') ]
      end
    end
  end
end
