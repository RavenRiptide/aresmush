require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The initiative order: a row per combatant, naming its holder by id.
    describe Combatants, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @hero = Character.create(:name => "Hero#{rand(1000000)}")
        @encounter = PF2Encounter.create(:organizer => 'GM', :round => 0)
      end

      after(:each) { [ @encounter, @hero ].each { |one| one&.delete } }

      def names
        Combatants.all(PF2Encounter[@encounter.id]).map(&:label)
      end

      def turn
        ActiveEffects.current_turn(PF2Encounter[@encounter.id])
      end

      it "should hold each combatant's holder by id, whatever it is called" do
        npc = Pf2eNpc.create(:encounter => @encounter, :name => @hero.name)
        Combatants.join(@encounter, @hero.name, 12, :holder => npc)
        Combatants.join(@encounter, @hero.name, 10, :holder => @hero)

        holders = Combatants.all(PF2Encounter[@encounter.id]).map(&:holder)

        expect(holders.first).to eq npc
        expect(holders.last.character).to eq @hero
        npc.delete
      end

      it "should put anyone but a character first on the same roll" do
        Combatants.join(@encounter, @hero.name, 15, :holder => @hero)
        Combatants.join(@encounter, 'Goblin', 15)

        expect(names).to eq [ 'Goblin', @hero.name ]
      end

      it "should give each combatant an id nobody else gets, even after one leaves" do
        first = Combatants.join(@encounter, 'Goblin', 15)
        Combatants.leave(@encounter, first['id'])
        second = Combatants.join(@encounter, 'Goblin', 15)

        expect(second['id']).to eq first['id'] + 1
      end

      describe "keeping the turn where it was" do
        before(:each) do
          [ [ 'A', 20 ], [ 'B', 15 ], [ 'C', 10 ] ].each { |name, init| Combatants.join(@encounter, name, init) }

          # B's turn in round 1: `next_init` is one past it.
          @encounter.update(:round => 1, :next_init => 2)
        end

        it "should keep it on B when someone joins ahead of them" do
          Combatants.join(@encounter, 'D', 30)

          expect(turn).to eq 'B'
        end

        it "should keep it on B when B's initiative changes" do
          Combatants.reroll(@encounter, Combatants.find(@encounter, 'B').state.number, 25)

          expect(names.first).to eq 'B'
          expect(turn).to eq 'B'
        end

        it "should make whoever came after B next when B leaves" do
          Combatants.leave(@encounter, Combatants.find(@encounter, 'B').state.number)

          expect(Combatants.at(@encounter, PF2Encounter[@encounter.id].next_init).label).to eq 'C'
        end
      end

      it "should read an order written as initiative and name, and keep it as rows" do
        @encounter.update(:participants => [ [ 20.0, @hero.name ], [ 10.2, 'Goblin' ] ])

        listed = Combatants.all(@encounter)

        expect(listed.map { |one| [ one.number, one.label ] }).to eq [ [ 1, @hero.name ], [ 2, 'Goblin' ] ]
        expect(listed.first.holder.character).to eq @hero
        expect(listed.last.holder).to be_nil
        expect(PF2Encounter[@encounter.id].participants.first).to include('id' => 1, 'char' => @hero.id)
      end
    end
  end
end
