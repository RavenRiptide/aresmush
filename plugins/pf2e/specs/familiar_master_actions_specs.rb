require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Familiar Focus and Restorative Familiar: a familiar in an encounter spends 2 actions to give its master
    # a Focus Point or Hit Points, once a day, counted on the master. The master is a level 6 witch with an
    # approved familiar, Smudge, and a focus pool of 2.
    describe "a familiar's master actions", :dbtest => true do

      class FamiliarActionClient
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

        @client = FamiliarActionClient.new
        @room = Room.create(:name => "Field#{rand(1000000)}")
        @scene = Scene.create(:room => @room, :temp_room => true)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @made = []

        allow(Pf2emagic).to receive(:focus_pool_max).and_return(2)
        @witch = witch("Morwen#{rand(1000000)}")
        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :round => 0)

        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow(Scenes).to receive(:add_to_scene)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
        allow(Login).to receive(:notify)
        allow(Login).to receive(:emit_ooc_if_logged_in)
      end

      after(:each) do
        PF2Encounter.find(:scene_id => @scene.id).each do |one|
          one.npcs.each(&:delete)
          one.states.each(&:delete)
          one.delete
        end
        (@made + [ @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def witch(name)
        char = Character.create(:name => name, :room => @room)
        combat = Pf2eCombat.create(:character => char, :key_abil => 'Intelligence', :perception => 'trained',
                                   :armor_prof => { 'unarmored' => 'trained' },
                                   :saves => { 'Fortitude' => 'trained', 'Reflex' => 'trained', 'Will' => 'expert' })
        hp = Pf2eHP.create(:character => char, :ancestry_hp => 6, :charclass_hp => 6)
        magic = PF2Magic.create(:character => char)
        char.update(:combat => combat, :hp => hp, :magic => magic, :pf2_level => 6, :pf2_conditions => {}, :pf2_traits => [],
                    :pf2_derived => {}, :pf2_feats => {}, :pf2_daily_choices => {},
                    :pf2_base_info => { 'charclass' => 'Witch', 'specialize' => 'Night' },
                    :pf2_features => { 'charclass_features' => [ 'Familiar' ] })
        @made += [ combat, hp, magic ] + Pf2e::ABILITIES.map do |ability|
          Pf2eAbilities.create(:character => char, :name => ability, :base_val => ability == 'Intelligence' ? 18 : 12)
        end
        Paths.apply_all!(Character[char.id])

        record = { 'name' => 'Smudge', 'species' => 'black cat', 'form' => 'land', 'source' => 'Familiar' }
        Character[char.id].update(:pf2_familiar => { 'approved' => record })
        @scene.participants.add char
        @made << char
        Character[char.id]
      end

      def encounter
        PF2Encounter[@encounter.id]
      end

      def join(char, init = 15)
        row = Combatants.join(encounter, char.name, init, :holder => Character[char.id])
        Character[char.id].encounters.add encounter
        encounter.characters.add Character[char.id]
        row
      end

      def run(cmd_class, text, who)
        @client.failures.clear
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
      end

      def familiar_row
        Combatants.rows(encounter).find { |row| row['master'] }
      end

      def familiar
        Pf2eNpc[familiar_row['npc']]
      end

      def master
        Pf2eCombatantState[@master_row['state']]
      end

      def pick(text)
        expect(DailyChoices.pick!(Character[@witch.id], 'familiar', text).ok?).to be true
      end

      # Joined, with its familiar, and on Morwen's turn.
      def fight
        Combatants.join(encounter, 'Goblin', 20)
        @master_row = join(@witch, 15)
        run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
        @ref = "##{familiar_row['id']}"
        2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
      end

      def as_familiar(action)
        run(PF2EncounterAsCmd, "encounter/as #{@ref}=act #{action}", @witch)
      end

      def command
        run(PF2EncounterActCmd, 'encounter/act command a minion=Smudge', @witch)
      end

      describe "its stat block" do
        it "should list the actions its master has today, at 2 actions each" do
          pick('Familiar Focus, Restorative Familiar')
          fight

          listed = familiar.stat_block['actions'].map { |one| [ one['name'], one['cost'], one['traits'] ] }
          expect(listed).to include([ 'Familiar Focus', 2, [ 'concentrate' ] ], [ 'Restorative Familiar', 2, [ 'concentrate' ] ])
        end

        it "should list neither without them" do
          pick('Darkvision')
          fight

          expect(familiar.stat_block['actions'].map { |one| one['name'] }).not_to include('Familiar Focus', 'Restorative Familiar')
        end
      end

      describe "Familiar Focus" do
        before(:each) do
          pick('Familiar Focus')
          fight
          master.update(:focus_current => 0)
        end

        it "should give its master a Focus Point, once a day" do
          command
          as_familiar('familiar focus')

          expect(@client.failures).to eq []
          expect(master.focus_current).to eq 1
          expect(@client.said.join).to include(t('pf2e.familiar_focus_restored', :master => @witch.name, :current => 1, :max => 2))
          expect(TurnState.used(master, 'Familiar Focus')).to eq 1
          expect((Character[@witch.id].pf2_turn_state || {}).dig('uses', 'Familiar Focus')).to be_nil

          # Its actions back, as on a later turn, so only the day's use stands in the way.
          TurnState.write(familiar, 'turn' => TurnState.turn(familiar).merge('actions' => 0))
          as_familiar('familiar focus')

          expect(@client.failures.join).to include(t('pf2e.familiar_action_used', :name => 'Smudge', :action => 'Familiar Focus'))
          expect(master.focus_current).to eq 1
        end

        it "should be refused when the pool is full" do
          master.update(:focus_current => 2)
          command
          as_familiar('familiar focus')

          expect(@client.failures.join).to include(t('pf2e.familiar_focus_full', :master => @witch.name, :max => 2))
          expect(TurnState.used(master, 'Familiar Focus')).to eq 0
        end

        it "should carry the day's use into an encounter carried on from this one" do
          command
          as_familiar('familiar focus')

          later = PF2Encounter.create(:scene => @scene, :owner => @gm, :round => 0, :carries_on_from => @encounter.id)
          carried = CombatantStates.for_join(later, Character[@witch.id])

          expect(TurnState.used(carried, 'Familiar Focus')).to eq 1
        end

        it "should start over in a fresh encounter" do
          command
          as_familiar('familiar focus')

          later = PF2Encounter.create(:scene => @scene, :owner => @gm, :round => 0)
          rested = CombatantStates.for_join(later, Character[@witch.id])

          expect(TurnState.used(rested, 'Familiar Focus')).to eq 0
        end
      end

      describe "Restorative Familiar" do
        it "should heal its master (half their level)d8" do
          pick('Restorative Familiar')
          fight
          Harm.damage(master, 25)
          before = Pf2eHP.get_current_hp(master)
          allow(Pf2e).to receive(:thrown_formula).and_call_original
          allow(Pf2e).to receive(:thrown_formula).with('3d8').and_return('total' => 11, 'shown' => '3d8: 11')

          command
          as_familiar('restorative familiar')

          expect(@client.failures).to eq []
          expect(Pf2eHP.get_current_hp(master)).to eq before + 11
          expect(TurnState.used(master, 'Restorative Familiar')).to eq 1
        end
      end

      describe "while exploring" do
        it "should act without its master's turn or a command" do
          pick('Familiar Focus')
          encounter.update(:mode => Exploration::MODE)
          @master_row = join(@witch, 15)
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
          @ref = "##{familiar_row['id']}"
          master.update(:focus_current => 0)

          as_familiar('familiar focus')

          expect(@client.failures).to eq []
          expect(master.focus_current).to eq 1
        end

        it "should still refuse an attack" do
          encounter.update(:mode => Exploration::MODE)
          @master_row = join(@witch, 15)
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
          @ref = "##{familiar_row['id']}"

          as_familiar('trip')

          expect(@client.failures.join).to include(t('pf2e.familiar_no_attacks', :name => 'Smudge', :action => 'Trip'))
        end
      end
    end
  end
end
