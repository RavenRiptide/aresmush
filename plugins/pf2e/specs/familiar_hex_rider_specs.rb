require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A witch patron's familiar ability: Casting or Sustaining a hex with the familiar in the encounter readies
    # it for the rest of the turn, once for each hex, and the witch uses it as a free action. The witch is
    # level 6 with an approved familiar, Smudge; their patron is set by each example.
    describe "a witch's hex riders", :dbtest => true do

      class HexRiderClient
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

        @client = HexRiderClient.new
        @room = Room.create(:name => "Field#{rand(1000000)}")
        @scene = Scene.create(:room => @room, :temp_room => true)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @made = []
        @witch = witch("Morwen#{rand(1000000)}")
        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :organizer => @gm.name, :round => 1, :is_active => true)

        # The GM is a Plotmaster, who adds a creature of their own making.
        allow_any_instance_of(Character).to receive(:has_permission?).and_call_original
        allow_any_instance_of(Character).to receive(:has_permission?).with('kill_pc') { |char, _| char.name == @gm.name }

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
        char.update(:combat => combat, :hp => hp, :pf2_level => 6, :pf2_conditions => {}, :pf2_traits => [],
                    :pf2_derived => {}, :pf2_feats => {}, :pf2_daily_choices => {},
                    :pf2_base_info => { 'charclass' => 'Witch', 'specialize' => 'Night' },
                    :pf2_features => { 'charclass_features' => [ 'Familiar' ] })
        @made += [ combat, hp ] + Pf2e::ABILITIES.map do |ability|
          Pf2eAbilities.create(:character => char, :name => ability, :base_val => ability == 'Intelligence' ? 18 : 12)
        end
        Paths.apply_all!(Character[char.id])
        record = { 'name' => 'Smudge', 'species' => 'black cat', 'form' => 'land', 'source' => 'Familiar' }
        Character[char.id].update(:pf2_familiar => { 'approved' => record })
        @scene.participants.add char
        @made << char
        Character[char.id]
      end

      def patron(name)
        Character[@witch.id].update(:pf2_base_info => { 'charclass' => 'Witch', 'specialize' => name })
      end

      def encounter
        PF2Encounter[@encounter.id]
      end

      def run(cmd_class, text, who)
        @client.failures.clear
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
      end

      def fight(familiar: true)
        run(PF2EncounterAddCmd, 'e/add Goblin=ac 15 hp 30', @gm)
        @goblin = Combatants.rows(encounter).find { |row| row['npc'] }
        @master_row = Combatants.join(encounter, @witch.name, 15, :holder => Character[@witch.id])
        Character[@witch.id].encounters.add encounter
        encounter.characters.add Character[@witch.id]
        run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch) if familiar
      end

      def master
        Pf2eCombatantState[@master_row['state']]
      end

      def goblin
        Pf2eNpc[@goblin['npc']]
      end

      def familiar
        Pf2eNpc[Combatants.rows(encounter).find { |row| row['master'] }['npc']]
      end

      def scene
        Acting::Scene.new(encounter, Combatants.find(encounter, @witch.name).state, nil, Character[@witch.id], false)
      end

      def hex(spell = 'Evil Eye')
        out = Acting.report
        Familiar::HexRiders.hexed!(scene, spell, out)
        @client.said << Telling.lines(out['lines']).join("\n")
      end

      def ready
        TurnState.turn(master)['hex_rider']
      end

      def act(text)
        run(PF2EncounterActCmd, "encounter/act #{text}", @witch)
      end

      describe "readying" do
        it "should ready the patron's rider on a hex, and tell the command" do
          fight
          hex

          expect(ready).to eq 'Familiar of Stalking Night'
          expect(@client.said.join).to include(t('pf2e.hex_rider_ready', :name => 'Smudge', :ability => 'Familiar of Stalking Night',
                                                                        :command => 'e/act familiar of stalking night=<target>'))
        end

        it "should not ready it for a spell that isn't a hex" do
          fight
          hex('Fireball')

          expect(ready).to be_nil
        end

        it "should not ready it without the familiar here" do
          fight(familiar: false)
          hex

          expect(ready).to be_nil
        end

        it "should not ready it for a witch dedicant, who has no patron's ability" do
          Character[@witch.id].update(:pf2_base_info => { 'charclass' => 'Wizard' })
          fight
          hex

          expect(ready).to be_nil
        end

        it "should only tell a rider about the map" do
          patron('Winter')
          fight
          hex

          expect(ready).to be_nil
          expect(@client.said.join).to include("Smudge's Familiar of Freezing Rime:")
        end

        it "should ready it when a hex is cast" do
          fight
          goblin_ref = "##{@goblin['id']}"
          Acting.cast(Acting::Scene.new(encounter, Combatants.find(encounter, @witch.name).state,
                                        Combatants.find(encounter, goblin_ref).state, Character[@witch.id], false),
                      'Evil Eye', [ Combatants.find(encounter, goblin_ref).state ], [])

          expect(ready).to eq 'Familiar of Stalking Night'
        end

        it "should ready it when a hex is sustained" do
          fight
          allow(Sustaining).to receive(:act) { |_scene, _term, out| Ok.new(:state => out.merge('sustained' => 'Evil Eye')) }

          act('sustain/evil eye')

          expect(@client.failures).to eq []
          expect(ready).to eq 'Familiar of Stalking Night'
        end

        it "should lapse as the witch's next turn starts" do
          fight
          hex
          TurnState.started(master, 2)

          expect(ready).to be_nil
        end
      end

      describe "using it" do
        it "should be refused without a hex this turn, and once used" do
          fight
          act("familiar of stalking night=##{@goblin['id']}")
          expect(@client.failures.join).to include(t('pf2e.hex_rider_no_hex', :ability => 'Familiar of Stalking Night'))

          hex
          act("familiar of stalking night=##{@goblin['id']}")
          expect(@client.failures).to eq []

          act("familiar of stalking night=##{@goblin['id']}")
          expect(@client.failures.join).to include(t('pf2e.hex_rider_no_hex', :ability => 'Familiar of Stalking Night'))
        end

        it "should refuse another patron's rider" do
          fight
          hex
          act("familiar of restored spirit=#{@witch.name}")

          expect(@client.failures.join).to include(t('pf2e.hex_rider_not_yours', :ability => 'Familiar of Restored Spirit'))
        end

        it "should make an enemy Frightened 1 with Stalking Night" do
          fight
          hex
          act("familiar of stalking night=##{@goblin['id']}")

          expect(Pf2e.condition_level(goblin, 'Frightened')).to eq 1
        end

        it "should give temporary Hit Points with Restored Spirit" do
          patron('Fervor')
          fight
          hex
          act("familiar of restored spirit=#{@witch.name}")

          expect(@client.failures).to eq []
          expect(ActiveEffects.named_on(master, 'Effect: Familiar of Restored Spirit')).not_to be_empty
          expect(master.hp.temp_hp.to_i).to eq 5
        end

        it "should give +1 or -1 to AC with Balanced Luck" do
          patron('Fate')
          fight
          act("familiar of balanced luck=##{@goblin['id']}/+1")
          expect(@client.failures.join).to include(t('pf2e.hex_rider_no_hex', :ability => 'Familiar of Balanced Luck'))

          hex
          act("familiar of balanced luck=##{@goblin['id']}")
          expect(@client.failures.join).to include(t('pf2e.hex_rider_luck'))

          act("familiar of balanced luck=##{@goblin['id']}/-1")
          expect(@client.failures).to eq []
          expect(ActiveEffects.named_on(goblin, 'Effect: Familiar of Balanced Luck')).not_to be_empty
        end

        it "should give the familiar a sense with Keen Senses" do
          patron('Wild')
          fight
          hex
          act('familiar of keen senses/tremorsense')

          expect(@client.failures).to eq []
          expect(ActiveEffects.named_on(familiar, 'Effect: Familiar of Keen Senses')).not_to be_empty
          expect(@client.said.join).to include(t('pf2e.hex_rider_point_out', :name => 'Smudge'))
        end

        describe "Ongoing Misery" do
          before(:each) do
            patron('Curse')
            fight
            held = { 'Slowed' => { 'value' => 1, 'expires' => { 'event' => 'turn-end', 'of' => 'Goblin', 'round' => 2 } },
                     'Frightened' => { 'value' => 2 } }
            goblin.update(:pf2_conditions => held)
          end

          it "should make a timed condition last a round longer, once" do
            hex
            act("familiar of ongoing misery=##{@goblin['id']}/slowed")

            expect(@client.failures).to eq []
            expect(goblin.pf2_conditions['Slowed']['expires']['round']).to eq 3

            hex
            act("familiar of ongoing misery=##{@goblin['id']}/slowed")
            expect(@client.failures.join).to include(t('pf2e.hex_rider_prolonged', :condition => 'Slowed'))
            expect(goblin.pf2_conditions['Slowed']['expires']['round']).to eq 3
          end

          it "should refuse a condition with no timed duration" do
            hex
            act("familiar of ongoing misery=##{@goblin['id']}/frightened")

            expect(@client.failures.join).to include(t('pf2e.hex_rider_untimed', :condition => 'Frightened'))
          end
        end
      end
    end
  end
end
