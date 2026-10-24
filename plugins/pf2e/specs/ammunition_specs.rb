require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Ordinary ammunition is not counted: a bow always has arrows. Ammunition of a precious material is an
    # item the archer carries, shot by saying the material on the Strike and used up by the shot.
    describe Ammunition do

      def attack(**more)
        { 'name' => 'Shortbow', 'ranged' => true, 'traits' => [ 'Deadly d10' ] }.merge(more.transform_keys(&:to_s))
      end

      describe "what is shot" do
        it "should be a ranged weapon's ammunition" do
          expect(Ammunition.shot?(attack)).to be true
        end

        it "should not be a weapon that is itself thrown, a bomb, or a melee weapon" do
          expect(Ammunition.shot?(attack('traits' => [ 'Agile', 'Thrown' ]))).to be false
          expect(Ammunition.shot?(attack('traits' => [ 'Thrown 10 ft' ], 'ranged' => false))).to be false
          expect(Ammunition.shot?(attack('bomb' => true))).to be false
          expect(Ammunition.shot?(attack('ranged' => false))).to be false
        end
      end

      describe "the materials said of a Strike" do
        it "should be those among its words" do
          expect(Ammunition.said([ 'cold iron', 'flanking', 'range 2' ])).to eq [ 'cold-iron' ]
          expect(Ammunition.said([ 'volley' ])).to eq []
        end
      end
    end

    describe "ammunition in a fight", :dbtest => true do
      include FightBench

      before(:each) do
        bench!
        Character[@hero.id].combat.update(:weapon_prof => { 'unarmed' => 'trained', 'martial' => 'trained', 'simple' => 'trained' })
        run(PF2EncounterAddCmd, 'e/add Imp=ac 14 hp 200; weak cold iron 5')
        bow = Pf2egear.create_item(hero, 'weapons', 'Shortbow', 1, Global.read_config('pf2e_weapons', 'Shortbow'))
        bow.update(:equipped => true)
        @client.said.clear
      end

      after(:each) { clear_bench! }

      def taken
        before = npc.damage
        yield
        npc.damage - before
      end

      def carry(name, many)
        Pf2egear.create_item(hero, 'consumables', name, many, Global.read_config('pf2e_consumables', name))
      end

      def carried(name)
        hero.consumables.to_a.select { |one| one.name == name }.sum { |one| one.quantity.to_i }
      end

      it "should let a bow shoot with nothing carried for it" do
        hero_types('e/strike #2=shortbow')

        expect(refused).to eq []
        expect(heard).to include('with Shortbow')
      end

      it "should not sell ordinary ammunition under any heading" do
        ordinary = [ 'Arrows', 'Bolts', 'Sling Bullets', 'Blowgun Darts' ]
        sold = Pf2egear::Inventory::CATEGORIES.flat_map { |row| (Global.read_config(row['config']) || {}).keys }

        expect(sold & ordinary).to eq []
      end

      describe "of a material" do
        it "should be refused to a bow where none is carried" do
          hero_types('e/strike #2=shortbow/cold iron')

          expect(refused).to eq [ t('pf2e.ammunition_none', :material => 'cold iron', :weapon => 'Shortbow') ]
        end

        it "should hurt what is weak to it, and be used up by the shot" do
          carry('Cold Iron Ammunition (Low-Grade)', 3)
          plain = taken { hero_types('e/strike #2=shortbow') }
          next_turn
          next_turn

          expect(taken { hero_types('e/strike #2=shortbow/cold iron') }).to eq plain + 5
          expect(carried('Cold Iron Ammunition (Low-Grade)')).to eq 2
          expect(heard).to include(t('pf2e.ammunition_shot', :item => 'Cold Iron Ammunition (Low-Grade)', :left => 2).strip)
        end

        it "should be used up by a shot that misses" do
          carry('Silver Ammunition (Low-Grade)', 1)

          hero_types('e/strike #2=shortbow/silver', FightBench::LOW)

          expect(refused).to eq []
          expect(carried('Silver Ammunition (Low-Grade)')).to eq 0
        end

        it "should not be what a material said of another is" do
          carry('Silver Ammunition (Low-Grade)', 1)

          hero_types('e/strike #2=shortbow/cold iron')

          expect(refused).to eq [ t('pf2e.ammunition_none', :material => 'cold iron', :weapon => 'Shortbow') ]
          expect(carried('Silver Ammunition (Low-Grade)')).to eq 1
        end

        it "should still be taken on a fist's say-so, which shoots nothing" do
          plain = taken { hero_types('e/strike #2=fist') }
          next_turn
          next_turn

          expect(taken { hero_types('e/strike #2=fist/cold iron') }).to eq plain + 5
          expect(refused).to eq []
        end

        it "should be shot and not drunk" do
          carry('Silver Ammunition (Low-Grade)', 1)

          hero_types('e/use consumables=0')

          expect(refused).to eq [ t('pf2e.ammunition_shoot_it', :item => 'Silver Ammunition (Low-Grade)', :material => 'silver') ]
        end
      end
    end
  end
end
