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

      # Plain `equip` mid-encounter changes the sheet, which a resync leaves the encounter's copy alone
      # on; the player hears how to equip it there instead.
      describe "equipping on the sheet mid-encounter" do
        before(:each) do
          PF2Weapon.create(:name => 'Falchion', :character => @hero)
          run(PF2EncounterResyncCmd, "e/resync #{@hero.name}")
          @client.said.clear
        end

        def equipped_here
          Pf2egear::Inventory.held(hero, 'weapons').first.equipped
        end

        def note(key)
          t("pf2egear.#{key}", :name => 'Falchion', :category => 'weapons', :number => 0)
        end

        it "should tell them the encounter still has it unequipped, and leave a resync equipping nothing" do
          run(Pf2egear::PF2GearEquipCmd, 'equip weapons=0', @hero)

          expect(heard).to include(note('equip_sheet_only'))

          run(PF2EncounterResyncCmd, "e/resync #{@hero.name}")

          expect(equipped_here).to be_falsey
        end

        it "should say nothing when encounter/equip equipped it there already" do
          run(Pf2egear::PF2EncounterEquipCmd, 'e/equip weapons=0', @hero)
          @client.said.clear
          run(Pf2egear::PF2GearEquipCmd, 'equip weapons=0', @hero)

          expect(equipped_here).to be true
          expect(heard).to_not include('encounter/equip')
        end

        it "should tell them the encounter still has it equipped after unequipping on the sheet" do
          run(Pf2egear::PF2EncounterEquipCmd, 'e/equip weapons=0', @hero)
          run(Pf2egear::PF2GearEquipCmd, 'equip weapons=0', @hero)
          @client.said.clear
          run(Pf2egear::PF2GearUnequipCmd, 'unequip weapons=0', @hero)

          expect(heard).to include(note('unequip_sheet_only'))
        end
      end

      it "should tell them to ask for a resync when they equip something bought since joining" do
        PF2Weapon.create(:name => 'Falchion', :character => @hero)

        run(Pf2egear::PF2GearEquipCmd, 'equip weapons=0', @hero)

        expect(heard).to include(t('pf2egear.equip_sheet_not_here', :name => 'Falchion'))
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
