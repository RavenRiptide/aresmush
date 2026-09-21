require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An encounter's history: each change, taken back and put back whole.
    describe History, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @hero = Character.create(:name => "Hero#{rand(1000000)}", :pf2_level => 3)
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 10)
        @hero.update(:hp => @hp)
        @encounter = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
        Combatants.join(@encounter, @hero.name, 10, :holder => Character[@hero.id])
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete
        @hp.delete
        @hero.delete
      end

      def encounter
        PF2Encounter[@encounter.id]
      end

      def standing
        CombatantStates.of(encounter, Character[@hero.id])
      end

      def hurt(amount)
        History.recording(encounter, "GM: damage #{amount}") { Pf2eHP.modify_damage(standing, amount) }
      end

      it "should record a change, and take it back and put it back" do
        hurt(7)

        expect(History.entries(encounter).map(&:said)).to eq [ 'GM: damage 7' ]

        expect(History.undo(encounter).ok?).to be true
        expect(standing.damage).to eq 0

        expect(History.redo(encounter).ok?).to be true
        expect(standing.damage).to eq 7
      end

      it "should step back through several, one at a time" do
        hurt(3)
        hurt(4)

        History.undo(encounter)
        expect(standing.damage).to eq 3

        History.undo(encounter)
        expect(standing.damage).to eq 0
        expect(History.undo(encounter).code).to eq :nothing_to_undo
      end

      it "should drop what could be redone once something new happens" do
        hurt(3)
        History.undo(encounter)
        hurt(5)

        expect(History.entries(encounter).map(&:said)).to eq [ 'GM: damage 5' ]
        expect(History.redo(encounter).code).to eq :nothing_to_redo
      end

      it "should record nothing for a change that changed nothing" do
        History.recording(encounter, 'GM: look') { }

        expect(History.entries(encounter)).to eq []
      end

      it "should record a change inside another as one" do
        History.recording(encounter, 'GM: as') { hurt(2) }

        expect(History.entries(encounter).map(&:said)).to eq [ 'GM: as' ]
      end

      it "should take back a creature added, and bring back one removed" do
        rat = Combatants.described('Rat', 'ac 12 hp 5 perception 2')

        History.recording(encounter, 'GM: add') { Combatants.add_npc(encounter, :described => rat, :initiative => 5) }
        npc = encounter.npcs.to_a.first

        History.recording(encounter, 'GM: remove') do
          Combatants.leave(encounter, npc.number)
          npc.delete
        end

        History.undo(encounter)
        expect(encounter.npcs.to_a.map(&:id)).to eq [ npc.id ]
        expect(Combatants.all(encounter).map(&:label)).to include(npc.name)

        History.undo(encounter)
        expect(encounter.npcs.to_a).to eq []
        expect(Combatants.all(encounter).map(&:label)).to eq [ @hero.name ]
      end

      it "should take back an effect put on someone" do
        History.recording(encounter, 'GM: effect') { ActiveEffects.apply(standing, 'Effect: Adamantine Body', :encounter => encounter) }

        History.undo(encounter)

        expect(ActiveEffects.on(standing)).to eq []
      end

      describe "what its people carry" do
        before(:each) do
          @potion = PF2Consumable.create(:name => 'Minor Healing Potion', :quantity => 2, :character => @hero)
        end

        after(:each) { PF2Consumable[@potion.id]&.delete }

        def drink
          History.recording(encounter, 'Hero: use consumable=1') do
            left = PF2Consumable[@potion.id].quantity - 1
            left.zero? ? PF2Consumable[@potion.id].delete : PF2Consumable[@potion.id].update(:quantity => left)
          end
        end

        it "should give back an item used, and take it again" do
          drink

          History.undo(encounter)
          expect(PF2Consumable[@potion.id].quantity).to eq 2

          History.redo(encounter)
          expect(PF2Consumable[@potion.id].quantity).to eq 1
        end

        it "should bring back the last of an item, used up" do
          drink
          drink
          expect(PF2Consumable[@potion.id]).to be_nil

          History.undo(encounter)

          expect(PF2Consumable[@potion.id].quantity).to eq 1
          expect(PF2Consumable[@potion.id].character).to eq Character[@hero.id]
        end

        it "should refuse to take it back once it has moved on outside the encounter" do
          drink
          PF2Consumable[@potion.id].update(:quantity => 5)

          undone = History.undo(encounter)

          expect(undone.code).to eq :moved
          expect(undone.args['what']).to eq 'Minor Healing Potion'
          expect(PF2Consumable[@potion.id].quantity).to eq 5
        end

        it "should give back money spent, through the audit" do
          start = Character[@hero.id].pf2_money
          History.recording(encounter, 'Hero: pay') { Pf2egear.pay_player(Character[@hero.id], -30, 'Hero', 'bribe') }

          History.undo(encounter)

          expect(Character[@hero.id].pf2_money).to eq start
          expect(Pf2e::Audit.consistent?(Character[@hero.id], 'money')).to be true
        end
      end

      it "should be frozen once the encounter ends" do
        hurt(3)
        encounter.update(:is_active => false)

        expect(History.undo(encounter).code).to eq :frozen
        expect(standing.damage).to eq 3
      end
    end
  end
end
