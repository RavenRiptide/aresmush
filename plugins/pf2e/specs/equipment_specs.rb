require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a character carries in an encounter: a copy of their gear and money as they entered it. When it
    # ends, only the consumables they used of their own come off their own inventory.
    describe Equipment, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @hero = Character.create(:name => "Hero#{rand(1000000)}", :pf2_level => 3, :pf2_money => 900)
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 10)
        @hero.update(:hp => @hp)
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
        @hp.delete
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

      it "should keep what the encounter gave them to the encounter" do
        PF2Consumable.create(:name => 'Elixir of Life', :quantity => 1, :state => standing,
                             :granted_by => 'loot', :expires => 'encounter')

        finish

        expect(PF2Consumable.find(:character_id => @hero.id).map(&:name)).to eq [ 'Minor Healing Potion' ]
        expect(standing.consumables.to_a.map(&:name)).to include('Elixir of Life')
      end

      # What a rest or a turn makes - an alchemist's preparations, Quick Alchemy - is the encounter's too:
      # whoever joins the next one fresh joins rested, and makes the day's again.
      it "should keep to the encounter what was made to last a day or a turn" do
        PF2Consumable.create(:name => "Alchemist's Fire (Lesser)", :quantity => 2, :state => standing,
                             :granted_by => 'advanced alchemy', :expires => 'rest')
        PF2Consumable.create(:name => 'Acid Flask (Lesser)', :quantity => 1, :state => standing,
                             :granted_by => 'quick alchemy', :expires => 'turn')

        finish

        expect(PF2Consumable.find(:character_id => @hero.id).map(&:name)).to eq [ 'Minor Healing Potion' ]
      end

      it "should let what a day's preparations made lapse at the next rest" do
        PF2Consumable.create(:name => "Alchemist's Fire (Lesser)", :quantity => 2, :state => standing,
                             :granted_by => 'advanced alchemy', :expires => 'rest')

        Pf2e.rest(standing)

        expect(standing.consumables.to_a.map(&:name)).to eq [ 'Minor Healing Potion' ]
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

        def loot(text = "e/loot #{@hero.name}=healing potion (minor)/2", who = @gm)
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
          expect([ given.granted_by, given.expires ]).to eq [ 'loot', 'encounter' ]
          expect(PF2Consumable.find(:character_id => @hero.id).map(&:name)).to eq [ 'Minor Healing Potion' ]
        end

        it "should let staff give it, and it stays with the encounter when it ends" do
          allow_any_instance_of(Character).to receive(:is_admin?) { |char| char.name == @gm.name }

          loot
          finish

          expect(PF2Consumable.find(:character_id => @hero.id).map(&:name)).to eq [ 'Minor Healing Potion' ]
          expect(standing.consumables.to_a.map(&:name)).to include('Healing Potion (Minor)')
        end
      end

      # A GM's resync: what they carry here made what their sheet holds now, as they have been using it
      # here - what they drew, what they drank, what the encounter gave them - and nothing else of theirs.
      describe "a resync" do
        def resync
          Equipment.resync!(standing, Character[@hero.id])
        end

        it "should bring in what they bought since joining, and their money now" do
          falchion = PF2Weapon.create(:name => 'Falchion', :equipped => true, :character => @hero)
          @hero.update(:pf2_money => 400)

          resync

          copied = standing.weapons.to_a.find { |one| one.name == 'Falchion' }
          expect([ copied.equipped, copied.copied_from ]).to eq [ true, falchion.id ]
          expect(standing.pf2_money).to eq 400
        end

        it "should keep what they drew and used here" do
          standing.weapons.to_a.first.update(:equipped => false)
          drink(1)
          @potions.update(:quantity => 5)

          resync

          expect(standing.weapons.to_a.map { |one| [ one.name, one.equipped ] }).to eq [ [ 'Longsword', false ] ]
          expect(standing.consumables.to_a.first.quantity).to eq 4

          finish

          expect(PF2Consumable[@potions.id].quantity).to eq 4
        end

        it "should drop what their sheet no longer holds, and keep what the encounter gave them" do
          Equipment.grant!(standing, 'consumables', 'Antidote (Lesser)', 1, {}, :granted_by => 'loot', :expires => 'encounter')
          @rope.delete

          resync

          expect(standing.gear.to_a).to eq []
          expect(standing.consumables.to_a.map(&:name)).to include('Antidote (Lesser)', 'Minor Healing Potion')
        end

        # Investing and etching are the sheet's to say, for a player who forgot to invest before joining.
        it "should take whether an item is invested, and its runes, from their sheet" do
          standing.weapons.to_a.first.update(:equipped => false)
          @sword.update(:invested => true, :invest_on_refresh => true,
                        :runes => { 'fundamental' => { 'potency' => 1 }, 'property' => {} })

          resync

          copy = standing.weapons.to_a.first
          expect([ copy.invested, copy.invest_on_refresh, copy.runes.dig('fundamental', 'potency') ]).to eq [ true, true, 1 ]
          expect(copy.equipped).to be false
        end

        it "should put what they bought in the copy of its bag" do
          torch = PF2Gear.create(:name => 'Torch', :character => @hero, :bag => @bag)

          resync

          copied = standing.gear.to_a.find { |one| one.copied_from == torch.id }
          expect(copied.bag.id).to eq standing.bags.to_a.first.id
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
