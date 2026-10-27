require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Joining an encounter again after leaving its order. A character is in an encounter while its order
    # has a place for them, so whatever took them out of it - the GM's `encounter/remove`, or `encounter/undo`
    # taking the join back - lets them join again.
    describe "joining an encounter again", :dbtest => true do

      class RejoinClient
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

        def screen_reader
          false
        end
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = RejoinClient.new
        @room = Room.create(:name => "Field#{rand(1000000)}")
        @scene = Scene.create(:room => @room, :temp_room => true)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Aria#{rand(1000000)}", :room => @room)
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 10)
        @hero.update(:hp => @hp, :pf2_level => 1, :pf2_conditions => {}, :pf2_traits => [], :pf2_baseinfo_locked => true,
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Fighter' },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
        @scene.participants.add @hero

        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * 0.75).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow(Scenes).to receive(:add_to_scene)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
        allow(Login).to receive(:notify)

        run(PF2InitiateCombatCmd, 'encounter')
        join
      end

      after(:each) do
        PF2Encounter.find(:scene_id => @scene.id).each { |one| one.delete_combatants } rescue nil
        (@abilities + [ @hp, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def run(cmd_class, text, who = @gm)
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
      end

      def encounter
        PF2Encounter.scene_active_encounter(Scene[@scene.id])
      end

      def join
        run(PF2InitJoinCmd, "encounter/join #{encounter.id}", @hero)
      end

      def in_order?
        Combatants.all(encounter).map(&:label).include?(@hero.name)
      end

      it "should let a character whose join was taken back join again" do
        run(PF2EncounterUndoCmd, 'encounter/undo')
        expect(in_order?).to be false
        expect(PF2Encounter.in_active_encounter?(Character[@hero.id])).to be false

        join

        expect(@client.failures).to eq []
        expect(in_order?).to be true
      end

      it "should count a character as in it again when their join is put back" do
        run(PF2EncounterUndoCmd, 'encounter/undo')
        run(PF2EncounterUndoCmd, 'encounter/redo')

        expect(in_order?).to be true
        expect(PF2Encounter.in_active_encounter?(Character[@hero.id])).to be true
      end

      it "should let a character the GM removed join again" do
        run(PF2EncounterRemoveCmd, "encounter/remove #{encounter.id}=#{@hero.name}")
        expect(in_order?).to be false

        join

        expect(@client.failures).to eq []
        expect(in_order?).to be true
      end

      it "should say a character already in it is already in it" do
        join

        expect(@client.failures.last).to include('Already in this encounter')
      end
    end
  end
end
