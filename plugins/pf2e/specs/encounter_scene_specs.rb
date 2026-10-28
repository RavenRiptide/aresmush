require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A scene's encounters: ended with it when it stops, as if their GM had ended them, and deleted with it.
    describe "an encounter's scene", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @hero = Character.create(:name => "Hero#{rand(1000000)}", :pf2_level => 3)
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 10)
        @hero.update(:hp => @hp)
        @scene = Scene.create
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => 'GM', :round => 1, :is_active => true,
                                         :trusted => [ @hero.name ], :cover => { '1' => 'standard' })
        Combatants.join(@encounter, @hero.name, 10, :holder => Character[@hero.id])

        allow(Global).to receive(:client_monitor).and_return(double(:notify_web_clients => nil))
        allow(Scenes).to receive(:create_log)
        allow(Scenes).to receive(:add_to_scene)
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete
        Scene[@scene.id]&.delete
        @hp.delete
        @hero.delete
      end

      def standing
        CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id])
      end

      it "should end its encounter when it stops, as the encounter's own end does" do
        ActiveEffects.apply(standing, 'Effect: Adamantine Body', :encounter => PF2Encounter[@encounter.id])

        Scenes.stop_scene(Scene[@scene.id], Character[@hero.id])

        ended = PF2Encounter[@encounter.id]
        expect(ended.is_active).to be false
        expect(ended.trusted).to eq []
        expect(ended.cover).to eq({})
        expect(ActiveEffects.on(standing)).to eq []
      end

      it "should take its encounters with it when it is deleted" do
        state = standing

        Scene[@scene.id].delete

        expect(PF2Encounter[@encounter.id]).to be_nil
        expect(Pf2eCombatantState[state.id]).to be_nil
      end

      describe "pose nudges" do
        before(:each) { @room = Room.create(:scene => @scene) }
        after(:each) { @room.delete }

        it "should not nudge anyone while the scene has a fight on" do
          expect(Scenes).not_to receive(:next_pose_chars)

          Scenes.notify_next_person(Room[@room.id])
        end

        it "should nudge as usual while the scene is only exploring" do
          PF2Encounter[@encounter.id].update(:mode => Exploration::MODE)
          expect(Scenes).to receive(:next_pose_chars).and_return([])

          Scenes.notify_next_person(Room[@room.id])
        end

        it "should nudge as usual once the fight is over" do
          PF2Encounter[@encounter.id].update(:is_active => false)
          expect(Scenes).to receive(:next_pose_chars).and_return([])

          Scenes.notify_next_person(Room[@room.id])
        end
      end
    end
  end
end
