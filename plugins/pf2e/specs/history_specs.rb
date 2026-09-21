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

      it "should be frozen once the encounter ends" do
        hurt(3)
        encounter.update(:is_active => false)

        expect(History.undo(encounter).code).to eq :frozen
        expect(standing.damage).to eq 3
      end
    end
  end
end
