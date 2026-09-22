require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a character carries in an encounter: a copy of their gear and money as they entered it. When it
    # ends, the consumables they used come off their own and what it gave them becomes theirs.
    describe Equipment, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @hero = Character.create(:name => "Hero#{rand(1000000)}", :pf2_level => 3, :pf2_money => 900)
        @sword = PF2Weapon.create(:name => 'Longsword', :equipped => true, :character => @hero)
        @bag = PF2Bag.create(:name => 'Backpack', :character => @hero)
        @rope = PF2Gear.create(:name => 'Rope', :character => @hero, :bag => @bag)
        @potions = PF2Consumable.create(:name => 'Minor Healing Potion', :quantity => 3, :character => @hero)
        @encounter = start
        @encounters = [ @encounter ]
      end

      after(:each) do
        @encounters.each { |one| PF2Encounter[one.id]&.delete }
        [ PF2Weapon, PF2Bag, PF2Gear, PF2Consumable ].each { |model| model.find(:character_id => @hero.id).each(&:delete) }
        @hero.delete
      end

      def start(from: nil)
        encounter = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true, :carries_on_from => from&.id)
        Combatants.join(encounter, @hero.name, 10, :holder => Character[@hero.id])
        encounter
      end

      def standing(encounter = @encounter)
        CombatantStates.of(PF2Encounter[encounter.id], Character[@hero.id])
      end

      def drink(count, encounter = @encounter)
        potion = standing(encounter).consumables.to_a.first
        left = potion.quantity - count
        left.zero? ? potion.delete : potion.update(:quantity => left)
      end

      def finish(encounter = @encounter)
        Encounters::Ending.end!(PF2Encounter[encounter.id])
      end

      it "should copy what they carry as they enter, worn, bagged and paid for" do
        sword = standing.weapons.to_a.first

        expect(sword.name).to eq 'Longsword'
        expect(sword.equipped).to be true
        expect(sword.copied_from).to eq @sword.id
        expect(standing.gear.to_a.first.bag.name).to eq 'Backpack'
        expect(standing.gear.to_a.first.bag.id).not_to eq @bag.id
        expect(standing.pf2_money).to eq 900
      end

      it "should read the copy, not what they buy meanwhile" do
        PF2Weapon.create(:name => 'Dagger', :character => @hero)

        expect(Pf2egear::Inventory.held(standing, 'weapons').map(&:name)).to eq [ 'Longsword' ]
      end

      it "should take what they used of their consumables off their own when it ends" do
        drink(1)

        finish

        expect(PF2Consumable[@potions.id].quantity).to eq 2
      end

      it "should take a consumable used up off their own altogether" do
        drink(3)

        finish

        expect(PF2Consumable[@potions.id]).to be_nil
      end

      it "should give them a consumable the encounter gave them" do
        PF2Consumable.create(:name => 'Elixir of Life', :quantity => 1, :state => standing)

        finish

        expect(PF2Consumable.find(:character_id => @hero.id).map(&:name)).to include('Elixir of Life')
      end

      it "should leave their other gear and money as they are" do
        standing.weapons.to_a.first.delete
        standing.update(:pf2_money => 0)

        finish

        expect(PF2Weapon[@sword.id]).not_to be_nil
        expect(Character[@hero.id].pf2_money).to eq 900
      end

      it "should say what it could not settle, and settle the rest" do
        drink(1)
        @potions.delete

        ended = finish

        expect(ended.map { |one| one['key'] }).to include('pf2e.settle_missing')
      end

      it "should settle only once, however often the encounter is restarted and ended" do
        drink(1)
        finish
        PF2Encounter[@encounter.id].update(:is_active => true)
        finish

        expect(PF2Consumable[@potions.id].quantity).to eq 2
      end

      describe "what a GM gives out" do
        class LootClient
          attr_reader :failures, :said

          def initialize
            @failures = []
            @said = []
          end

          def logged_in?
            true
          end

          def emit_failure(message)
            @failures << message.to_s
          end

          %w{emit_success emit emit_ooc}.each { |name| define_method(name) { |message| @said << message.to_s } }
        end

        before(:each) do
          @client = LootClient.new
          @room = Room.create(:name => "Vault#{rand(1000000)}")
          @scene = Scene.create(:room => @room)
          @room.update(:scene => @scene)
          @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
          PF2Encounter[@encounter.id].update(:scene => @scene, :owner => @gm, :organizer => @gm.name)

          allow_any_instance_of(Room).to receive(:emit_ooc)
        end

        after(:each) do
          PF2Consumable.find(:character_id => @hero.id).each(&:delete)
          [ @gm, @scene, @room ].each { |one| one&.delete }
        end

        def loot(text = "e/loot #{@hero.name}=consumables healing potion (minor)/2", who = @gm)
          Pf2egear::PF2EncounterLootCmd.new(@client, Command.new(text), Character[who.id]).on_command
        end

        it "should refuse a GM who is not trusted" do
          loot

          expect(@client.failures).to eq [ t('pf2e.loot_not_trusted') ]
          expect(standing.consumables.to_a.size).to eq 1
        end

        it "should let a trusted GM give it, in the encounter" do
          allow_any_instance_of(Character).to receive(:has_permission?).and_call_original
          allow_any_instance_of(Character).to receive(:has_permission?).with('trusted_gm') { |char, _| char.name == @gm.name }

          loot

          expect(@client.failures).to eq []
          given = standing.consumables.to_a.find { |one| one.name.start_with?('Healing Potion') }
          expect(given.quantity).to eq 2
          expect(PF2Consumable.find(:character_id => @hero.id).map(&:name)).to eq [ 'Minor Healing Potion' ]
        end

        it "should let staff give it, and it is theirs when the encounter ends" do
          allow_any_instance_of(Character).to receive(:is_admin?) { |char| char.name == @gm.name }

          loot
          finish

          expect(PF2Consumable.find(:character_id => @hero.id).map(&:name)).to include('Healing Potion (Minor)')
        end
      end

      it "should carry the copy on to an encounter that carries on, and settle only what that one used" do
        drink(1)
        finish

        second = start(:from => @encounter)
        @encounters << second
        drink(1, second)
        finish(second)

        expect(standing(second).consumables.to_a.first.copied_from).to eq @potions.id
        expect(PF2Consumable[@potions.id].quantity).to eq 1
      end
    end
  end
end
