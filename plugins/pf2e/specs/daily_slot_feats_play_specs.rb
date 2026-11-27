require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Feats from the daily preparation and spell slot part of the feat audit that play out in an
    # encounter or on the sheet: Vivacious Conduit's ten-minute rest, and Eternal Wings' fly Speed.
    describe "daily preparation and slot feats in play", :dbtest => true do

      class SlotFeatClient
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
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = SlotFeatClient.new
        @room = Room.create(:name => "Glade#{rand(1000000)}")
        @scene = Scene.create(:room => @room, :temp_room => true)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @made = [ @room, @scene, @gm ]

        allow(Scenes).to receive(:add_to_scene)
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow_any_instance_of(Room).to receive(:emit_ooc)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Login).to receive(:notify)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow_any_instance_of(Character).to receive(:is_admin?) { |char| char.id == @gm.id }
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * 0.5).ceil, 1 ].max ] * amount.to_i }
      end

      after(:each) do
        @scene.encounters.each(&:delete) if Scene[@scene.id]
        @made.reverse.each { |one| one.class[one.id]&.delete }
      end

      # A 9th-level gnome with Constitution 16, so Vivacious Conduit heals 3 × 4.
      def gnome(feats)
        char = Character.create(:name => "Pip#{rand(1000000)}", :room => @room, :pf2_level => 9,
                                :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {},
                                :pf2_feats => { 'ancestry' => feats },
                                :pf2_movement => { 'base_speed' => 25 },
                                :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Gnome' },
                                :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        combat = Pf2eCombat.create(:character => char, :armor_prof => { 'unarmored' => 'trained' },
                                   :weapon_prof => { 'unarmed' => 'trained' }, :perception => 'trained')
        hp = Pf2eHP.create(:character => char, :ancestry_hp => 8, :charclass_hp => 10)
        char.update(:combat => combat, :hp => hp)
        abilities = Pf2e::ABILITIES.map do |one|
          Pf2eAbilities.create(:character => char, :name => one, :base_val => one == 'Constitution' ? 16 : 12)
        end
        @made += [ char, combat, hp ] + abilities
        Scene[@scene.id].participants.add char
        Character[char.id]
      end

      def run(text, who = @gm)
        command = Command.new(text)
        Pf2e.get_cmd_handler(nil, command, nil).new(@client, command, Character[who.id]).on_command
      end

      def active
        PF2Encounter.scene_active_encounter(Scene[@scene.id])
      end

      def state_of(char)
        CombatantStates.of(PF2Encounter[active.id], Character[char.id])
      end

      describe "Vivacious Conduit" do
        before(:each) do
          @pip = gnome([ 'Vivacious Conduit' ])
        end

        it "should heal Constitution modifier times half level after a ten-minute rest while exploring" do
          run('e/explore')
          run('e/join', @pip)
          Pf2eHP.get_hp_obj(state_of(@pip)).update(:damage => 20)
          run('e/act vivacious conduit', @pip)

          expect(@client.failures).to eq []
          expect(Pf2eHP.get_hp_obj(state_of(@pip)).damage).to eq 8
        end

        it "should be refused in a fight" do
          run('e/start')
          run('e/join', @pip)
          run('e/act vivacious conduit', @pip)

          expect(@client.failures.join).to include(t('pf2e.explore_only', :action => 'Vivacious Conduit'))
        end
      end

      describe "Eternal Wings" do
        it "should give a fly Speed equal to the character's Speed" do
          pip = gnome([ 'Divine Wings', 'Eternal Wings' ])

          fly = Movement.for(pip)['special'].find { |one| one['type'] == 'fly' }

          expect(fly).to include('speed' => 25, 'source' => 'Eternal Wings')
        end

        it "should give none without it" do
          pip = gnome([ 'Divine Wings' ])

          expect(Movement.for(pip)['special'].map { |one| one['type'] }).to_not include('fly')
        end
      end
    end
  end
end
