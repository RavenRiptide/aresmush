require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Encounters

      # An encounter notice - its start, end, round or turn - in its scene carries which notice it is and its
      # details, so the live scene page lays it out as the encounter's own page does.
      describe Announce, :dbtest => true do

        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @room = Room.create(:name => "Field#{rand(1000000)}")
          @scene = Scene.create(:room => @room, :temp_room => true)
          @viewer = Character.create(:name => "Viewer#{rand(1000000)}")

          allow(Global).to receive(:dispatcher).and_return(double(:spawn => nil))
          allow(Scenes).to receive(:create_new_pose_notification)
        end

        after(:each) do
          @scene.scene_poses.each(&:delete)
          [ @viewer, @scene, @room ].each(&:delete)
        end

        def last_pose
          Scene[@scene.id].scene_poses.to_a.max_by(&:order)
        end

        it "should keep a turn's notice and its details on its scene pose, and send them to the page" do
          details = { 'round' => 2, 'label' => 'Initiative advances!', 'init' => 17, 'current' => 'Aria', 'next' => 'Goblin' }
          Announce.log(@scene, 'Aria is up', :notice => 'turn', :notice_details => details)

          data = Scenes.build_scene_pose_web_data(last_pose, @viewer)

          expect(data[:encounter_notice]).to eq 'turn'
          expect(data[:encounter_notice_details]).to eq details
          expect(data[:is_ooc]).to be true
          expect(data[:is_system_pose]).to be true
        end

        it "should give an end, which has no details, an empty set of them" do
          Announce.log(@scene, '*** END OF ENCOUNTER 3 ***', :notice => 'end')

          expect(last_pose.encounter_notice).to eq 'end'
          expect(last_pose.encounter_notice_details).to eq({})
        end

        it "should leave a line that is no notice as the scene's own" do
          Announce.log(@scene, 'Aria strikes the goblin.', :story => true)

          expect(Scenes.build_scene_pose_web_data(last_pose, @viewer)[:encounter_notice]).to be_nil
        end

        # The roll prefix: what the scene keeps is marked at the game's level, and each viewer reads it
        # marked at their own.
        describe "marked with the roll prefix" do
          before(:each) do
            allow(Global).to receive(:read_config).and_call_original
            allow(Global).to receive(:read_config).with('pf2e', 'system_prefix').and_return('[PF]')
            allow(Global).to receive(:read_config).with('pf2e', 'system_prefix_level').and_return('actions')
          end

          it "should keep a story line marked at the game's level, and the line as told" do
            Announce.log(@scene, 'Aria strikes the goblin.%r  Damage to Goblin: 6.', :story => true)

            expect(last_pose.pose).to eq '[PF] Aria strikes the goblin.%r  Damage to Goblin: 6.'
            expect(last_pose.system_line).to eq 'action'
            expect(last_pose.system_text).to eq 'Aria strikes the goblin.%r  Damage to Goblin: 6.'
            expect(last_pose.is_ooc).to be_falsey
          end

          it "should show each viewer the line at their own level" do
            Announce.log(@scene, 'Aria joins encounter 3.')

            expect(Scenes.build_scene_pose_web_data(last_pose, @viewer)[:pose]).to_not include('[PF]')

            @viewer.update(:pf2_roll_prefix => 'all')
            expect(Scenes.build_scene_pose_web_data(last_pose, Character[@viewer.id])[:pose]).to include('[PF] Aria joins encounter 3.')
          end
        end
      end
    end
  end
end
