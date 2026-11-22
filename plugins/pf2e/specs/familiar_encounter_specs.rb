require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A familiar in an encounter: it joins when its player says it is there, is targeted like anyone, takes
    # no turn of its own, and leaves with its master. The master is a level 6 witch with an approved
    # familiar, Smudge.
    describe "a familiar in an encounter", :dbtest => true do

      class FamiliarFightClient
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

        @client = FamiliarFightClient.new
        @room = Room.create(:name => "Field#{rand(1000000)}")
        @scene = Scene.create(:room => @room, :temp_room => true)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @made = []
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

      def witch(name, approved: true)
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
        Character[char.id].update(:pf2_familiar => approved ? { 'approved' => record } : { 'pending' => record })
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

      describe "joining" do
        before(:each) do
          Combatants.join(encounter, 'Goblin', 20)
          @master_row = join(@witch)
        end

        it "should join under its name, naming its master's row" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)

          expect(@client.failures).to eq []
          expect(familiar_row['name']).to eq 'Smudge'
          expect(familiar_row['master']).to eq @master_row['id']
          expect(familiar.master.character.id).to eq @witch.id
          expect(@client.said.join).to include("Smudge, #{@witch.name}'s familiar, joins encounter #{@encounter.id} as ##{familiar_row['id']}")
        end

        it "should be targeted by its id or its name" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)

          expect(Combatants.find(encounter, "##{familiar_row['id']}").state.holder).to eq familiar
          expect(Combatants.find(encounter, 'smudge').state.holder).to eq familiar
        end

        it "should be on the characters' side" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)

          expect(Actors.of(familiar)).to be_a(FamiliarActor)
          expect(Actors.of(familiar).side).to eq 'characters'
        end

        it "should have the master's level and its own hit points" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)

          expect(familiar.pf2_level).to eq 6
          expect(familiar.max_hp).to eq 30
          expect(familiar.hp_left).to eq 30
        end

        it "should keep its AC and saves when its master is frightened in the fight" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
          state = Pf2eCombatantState[@master_row['state']]
          before = [ Npcs.stat(familiar, 'ac')['total'], Npcs.stat(familiar, 'save', 'Will')['total'] ]

          state.update(:pf2_conditions => { 'Frightened' => { 'value' => 2, 'status' => true } })

          expect(Stat.total(Pf2eCombatantState[state.id], 'ac')).to eq before.first - 2
          expect([ Npcs.stat(familiar, 'ac')['total'], Npcs.stat(familiar, 'save', 'Will')['total'] ]).to eq before
        end

        it "should take its own conditions" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
          before = Npcs.stat(familiar, 'ac')['total']

          familiar.update(:pf2_conditions => { 'Frightened' => { 'value' => 1, 'status' => true } })

          expect(Npcs.stat(familiar, 'ac')['total']).to eq before - 1
        end

        it "should read its other skills at its level" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)

          expect(Npcs.stat(familiar, 'skill', 'Athletics')['total']).to eq 6
          expect(Npcs.stat(familiar, 'skill', 'Stealth')['total']).to eq 10
        end

        it "should be refused a second time" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)

          expect(@client.failures.join).to include('Smudge is already in this encounter')
          expect(Combatants.rows(encounter).count { |row| row['master'] }).to eq 1
        end

        it "should be refused when another combatant has its name" do
          Combatants.join(encounter, 'smudge', 5)

          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)

          expect(@client.failures.join).to include('already called Smudge')
          expect(familiar_row).to be_nil
        end

        it "should let the GM bring in someone's familiar, and nobody else" do
          other = witch("Hazel#{rand(1000000)}")

          run(PF2EncounterFamiliarCmd, "encounter/familiar #{@witch.name}", other)
          expect(@client.failures.join).to include(t('pf2e.not_organizer'))

          run(PF2EncounterFamiliarCmd, "encounter/familiar #{@witch.name}", @gm)
          expect(@client.failures).to eq []
          expect(familiar.master.character.id).to eq @witch.id
        end

        it "should be taken back by undo" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
          npc = familiar

          run(PF2EncounterUndoCmd, 'encounter/undo', @gm)

          expect(@client.failures).to eq []
          expect(familiar_row).to be_nil
          expect(Pf2eNpc[npc.id]).to be_nil
        end
      end

      describe "refused" do
        it "when its master isn't in the encounter" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)

          expect(@client.failures.join).to include("isn't in this encounter")
        end

        it "when staff haven't approved it" do
          waiting = witch("Wren#{rand(1000000)}", :approved => false)
          join(waiting)

          run(PF2EncounterFamiliarCmd, 'encounter/familiar', waiting)

          expect(@client.failures.join).to include("isn't approved yet")
          expect(familiar_row).to be_nil
        end
      end

      describe "the turn order" do
        before(:each) do
          Combatants.join(encounter, 'Goblin', 20)
          @master_row = join(@witch, 15)
          Combatants.join(encounter, 'Orc', 10)
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
        end

        it "should pass over the familiar" do
          turns = 4.times.map do
            run(PF2EncounterNextCmd, 'encounter/next', @gm)
            ActiveEffects.current_turn(encounter)
          end

          expect(turns).to eq [ 'Goblin', @witch.name, 'Orc', 'Goblin' ]
          expect(encounter.round).to eq 2
        end

        it "should keep the turn where it was when the familiar joins mid-round" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar/leave', @witch)
          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }

          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)

          expect(ActiveEffects.current_turn(encounter)).to eq @witch.name
          run(PF2EncounterNextCmd, 'encounter/next', @gm)
          expect(ActiveEffects.current_turn(encounter)).to eq 'Orc'
        end

        it "should count the familiar's turn as its master's" do
          run(PF2EncounterNextCmd, 'encounter/next', @gm)

          expect(Combatants.turn_name(encounter, 'Smudge')).to eq @witch.name
          expect(Turns.upcoming_round(encounter, 'Smudge')).to eq Turns.upcoming_round(encounter, @witch.name)
          expect(Turns.expiry_for('its-next-turn-end', encounter, 'Goblin', 'Smudge')['of']).to eq @witch.name
        end

        it "should leave the familiar out of the encounter's difficulty" do
          with = Difficulty.of_encounter(encounter)
          run(PF2EncounterFamiliarCmd, 'encounter/familiar/leave', @witch)

          expect(Difficulty.of_encounter(encounter)).to eq with
        end
      end

      describe "leaving" do
        before(:each) do
          @master_row = join(@witch)
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
          @npc = familiar
        end

        it "should go when its player says" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar/leave', @witch)

          expect(@client.failures).to eq []
          expect(familiar_row).to be_nil
          expect(Pf2eNpc[@npc.id]).to be_nil
          expect(@client.said.join).to include("Smudge, #{@witch.name}'s familiar, leaves encounter")
        end

        it "should go with its master" do
          Combatants.leave(encounter, @master_row['id'])

          expect(Combatants.rows(encounter)).to eq []
          expect(Pf2eNpc[@npc.id]).to be_nil
        end

        it "should be refused when it isn't there" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar/leave', @witch)
          run(PF2EncounterFamiliarCmd, 'encounter/familiar/leave', @witch)

          expect(@client.failures.join).to include("familiar isn't in this encounter")
        end
      end

      it "should take its id into its name when a character of that name joins after it" do
        join(@witch)
        run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
        id = familiar_row['id']
        namesake = Character.create(:name => 'Smudge', :room => @room)
        @made << namesake

        join(namesake, 5)

        expect(familiar_row['name']).to eq "Smudge ##{id}"
        expect(familiar.name).to eq "Smudge ##{id}"
        expect(Combatants.find(encounter, 'Smudge').state.holder.character.id).to eq namesake.id
      end

      # Commanded, it acts in its master's turn with 2 actions; a player is refused what the rules don't let
      # it do, and the GM isn't.
      describe "acting" do
        before(:each) do
          Combatants.join(encounter, 'Goblin', 20)
          @master_row = join(@witch, 15)
          Combatants.join(encounter, 'Orc', 10)
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
          @ref = "##{familiar_row['id']}"
          # The Goblin's turn, then Morwen's.
          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
        end

        def used
          TurnState.turn(familiar)['actions'].to_i
        end

        it "should have no actions until Commanded" do
          expect(TurnState.actions(familiar)).to eq 0

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @witch)

          expect(@client.failures.join).to include('Smudge has no actions left this turn')
          expect(used).to eq 0
        end

        it "should have 2 actions once Commanded, and act with them" do
          run(PF2EncounterActCmd, 'encounter/act command a minion=Smudge', @witch)
          expect(@client.failures).to eq []
          expect(@client.said.join).to include('Smudge gains 2 actions this turn')
          expect(TurnState.turn(Pf2eCombatantState[@master_row['state']])['actions']).to eq 1

          2.times { run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @witch) }
          expect(@client.failures).to eq []
          expect(used).to eq 2

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @witch)
          expect(@client.failures.join).to include('no actions left')
        end

        it "should be Commanded only by its master, and only itself" do
          other = witch("Hazel#{rand(1000000)}")
          join(other, 5)

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", other)
          expect(@client.failures.join).to include(t('pf2e.not_organizer'))

          run(PF2EncounterActCmd, 'encounter/act command a minion=Goblin', @witch)
          expect(@client.failures.join).to include("Goblin isn't your familiar")
        end

        it "should act only on its master's turn" do
          run(PF2EncounterActCmd, 'encounter/act command a minion=Smudge', @witch)
          run(PF2EncounterNextCmd, 'encounter/next', @gm)

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @witch)

          expect(@client.failures.join).to include("Smudge acts only on #{@witch.name}'s turn")
        end

        it "should lose the command when its master's next turn starts" do
          run(PF2EncounterActCmd, 'encounter/act command a minion=Smudge', @witch)
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @witch)

          3.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }

          expect(ActiveEffects.current_turn(encounter)).to eq @witch.name
          expect(Familiar::Minion.commanded?(familiar)).to be false
          expect(used).to eq 0
        end

        it "should have 1 action uncommanded with Independent, and 2 when Commanded" do
          allow(Familiar::Daily).to receive(:abilities_today).and_return([ { 'name' => 'Independent' } ])

          expect(TurnState.actions(familiar)).to eq 1
          run(PF2EncounterActCmd, 'encounter/act command a minion=Smudge', @witch)
          expect(TurnState.actions(familiar)).to eq 2
        end

        it "should refuse attacks but Escape and Force Open" do
          run(PF2EncounterActCmd, 'encounter/act command a minion=Smudge', @witch)

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act trip=Goblin", @witch)
          expect(@client.failures.join).to include("Smudge can't make attacks except to Escape or Force Open")

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act force open", @witch)
          expect(@client.failures).to eq []
        end

        it "should refuse Strikes and spells" do
          run(PF2EncounterActCmd, 'encounter/act command a minion=Smudge', @witch)

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=strike jaws=Goblin", @witch)

          expect(@client.failures.join).to include('Smudge can only take actions')
        end

        it "should refuse manipulate actions without Manual Dexterity, and allow them with it" do
          run(PF2EncounterActCmd, 'encounter/act command a minion=Smudge', @witch)

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act interact", @witch)
          expect(@client.failures.join).to include("without the Manual Dexterity ability")

          allow(Familiar::Daily).to receive(:abilities_today).and_return([ { 'name' => 'Manual Dexterity' } ])
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act interact", @witch)
          expect(@client.failures).to eq []
        end

        it "should let the GM have it do anything" do
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act interact", @gm)

          expect(@client.failures).to eq []
        end

        it "should have no reactions" do
          expect(Actors.of(familiar).reactions?).to be false
        end

        it "should ease its own Frightened at the end of its master's turn" do
          familiar.update(:pf2_conditions => { 'Frightened' => { 'value' => 1, 'status' => true } })

          run(PF2EncounterNextCmd, 'encounter/next', @gm)

          expect(Pf2e.condition_level(familiar, 'Frightened')).to eq 0
        end

        it "should gain no item bonus of its own" do
          before = Npcs.stat(familiar, 'save', 'Reflex')['total']

          ActiveEffects.apply(familiar, 'Effect: Elysian Dew', :encounter => encounter)

          expect(Npcs.stat(Pf2eNpc[familiar.id], 'save', 'Reflex')['total']).to eq before
        end

        it "should tell its master what it took" do
          told = []
          allow(Login).to receive(:notify) { |char, _kind, message, _id| told << [ char.id, message ] }

          Actors.of(familiar).notify_damage(4, 'Goblin')

          expect(told).to eq [ [ @witch.id, "Your familiar Smudge takes 4 damage from Goblin." ] ]
        end

        it "should remind its master how to have it act" do
          reminder = Turns.reminder(Pf2eCombatantState[@master_row['state']], 1)

          expect(reminder.gsub(/%x(\d+|[a-zA-Z])/, '')).to include("Smudge acts only when you Command it: 'e/act command a minion=#{@ref}'")
        end
      end

      # A fey dragonet's Euphoric Breath, and a homunculus's Blood Link. Every die shows 10, and a d4 3.
      describe "specific familiars" do
        before(:each) do
          allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ sides.to_i == 4 ? 3 : 10 ] * amount.to_i }
          @master_row = join(@witch, 15)
        end

        def become(specific, choices = {})
          record = Character[@witch.id].pf2_familiar
          approved = record['approved'].merge('specific' => specific, 'choices' => choices)
          Character[@witch.id].update(:pf2_familiar => record.merge('approved' => approved))
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
          @ref = "##{familiar_row['id']}"
        end

        def state
          Pf2eCombatantState[@master_row['state']]
        end

        def brute(name, fortitude, immunities: [])
          described = { 'name' => name, 'level' => 1, 'hp' => 40, 'ac' => 15, 'perception' => 5, 'traits' => [ 'humanoid' ],
                        'saves' => { 'fortitude' => fortitude, 'reflex' => 5, 'will' => 5 }, 'immunities' => immunities }
          Combatants.add_npc(encounter, :described => described, :name => name, :initiative => 1).state['npc']
        end

        # Morwen's turn, and Feyfly Commanded.
        def commanded
          run(PF2EncounterNextCmd, 'encounter/next', @gm) until ActiveEffects.current_turn(encounter) == @witch.name
          run(PF2EncounterActCmd, "encounter/act command a minion=#{@ref}", @witch)
        end

        describe "Euphoric Breath" do
          before(:each) { become('Fey Dragonet', 'Speech' => 'Kamin') }

          it "should be the higher of its master's class DC and spell DC" do
            class_dc = Stat.total(state, 'class_dc').to_i
            expect(familiar.stat_block['actions'].first['text']).to include("DC #{class_dc} Fortitude")

            caster = state
            allow(caster).to receive(:magic).and_return(double('magic'))
            allow(Pf2emagic::Entries).to receive(:casting).and_return([ { 'name' => 'Witch' } ])
            allow(Pf2emagic).to receive(:get_caster_stats).and_return({})
            allow(Acting).to receive(:spell_figure).and_return(class_dc + 4)

            expect(Familiar::Block.master_dc(caster)).to eq class_dc + 4
          end

          it "should leave stupefied 2 and slowed 1 for the same 1d4 rounds on a failure" do
            dc = Familiar::Block.master_dc(state)
            target = brute('Brute', dc - 15)
            commanded

            run(PF2EncounterAsCmd, "encounter/as #{@ref}=act euphoric breath=Brute", @witch)

            expect(@client.failures).to eq []
            held = Pf2eNpc[target.id].pf2_conditions
            expect(held['Stupefied']['value']).to eq 2
            expect(held['Slowed']['value']).to eq 1
            expect(held['Stupefied']['expires']).to eq held['Slowed']['expires']
            expect(held['Slowed']['expires']['round']).to eq encounter.round + 3
            expect(@client.said.join).to include('for 3 rounds (1d4: 3)')
            expect(TurnState.turn(familiar)['actions']).to eq 2
          end

          it "should pass over a creature immune to poison" do
            target = brute('Golem', -20, :immunities => [ 'poison' ])
            commanded

            run(PF2EncounterAsCmd, "encounter/as #{@ref}=act euphoric breath=Golem", @witch)

            expect(Pf2eNpc[target.id].pf2_conditions).to eq({})
          end

          it "should be refused to the player once it is used" do
            brute('Brute', 0)
            commanded
            run(PF2EncounterAsCmd, "encounter/as #{@ref}=act euphoric breath=Brute", @witch)

            refused = Familiar::Minion.action_refusal(familiar, 'Feyfly', 'euphoric breath')

            expect(refused.code).to eq :familiar_spent
          end

          it "shouldn't act for a dying master" do
            state.update(:pf2_conditions => { 'Unconscious' => {}, 'Dying' => { 'value' => 1 } })

            expect(TurnState.actions(familiar)).to eq 0
          end
        end

        describe "Blood Link" do
          before(:each) do
            become('Homunculus', 'porter' => 'Valet')
            allow(Pf2e).to receive(:can_damage_pc?).and_return(true)
          end

          it "should hurt its master when it is destroyed" do
            before = Pf2eHP.get_hp_obj(state).damage.to_i

            run(PF2DamagePlayerCmd, "damage #{@ref}=40", @gm)

            expect(Pf2eHP.get_hp_obj(Pf2eCombatantState[state.id]).damage.to_i).to eq before + 20
            expect(@client.said.join).to include("Smudge is destroyed, and through its Blood Link #{@witch.name} takes 20 mental damage (2d10: 10, 10)")
          end

          it "should not hurt its master before it is destroyed" do
            before = Pf2eHP.get_hp_obj(state).damage.to_i

            run(PF2DamagePlayerCmd, "damage #{@ref}=5", @gm)

            expect(Pf2eHP.get_hp_obj(Pf2eCombatantState[state.id]).damage.to_i).to eq before
          end

          it "should act as if Commanded while its master is unconscious and dying" do
            expect(TurnState.actions(familiar)).to eq 0

            state.update(:pf2_conditions => { 'Unconscious' => {}, 'Dying' => { 'value' => 1 } })

            expect(TurnState.actions(familiar)).to eq 2
          end
        end
      end

      describe "encounter/sheet/familiar" do
        before(:each) do
          Combatants.join(encounter, 'Goblin', 20)
          @master_row = join(@witch, 15)
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
          @ref = "##{familiar_row['id']}"
        end

        def sheet(viewer, target = nil)
          @client.said.clear
          run(PF2EncounterFamiliarSheetCmd, "encounter/sheet/familiar #{target}".strip, viewer)
          (@client.said + @client.failures).join("\n").gsub(/%x(\d+|[a-zA-Z])/, '')
        end

        it "should open with what it has in the encounter" do
          text = sheet(@witch)

          expect(text).to include("In Encounter #{@encounter.id}")
          expect(text).to include("ID: #{@ref}")
          expect(text).to include('Actions: 0 of 0 used (not Commanded)')
          expect(text).to include('Conditions: none')
          expect(text).to include('Basic Information')
        end

        it "should show its hit points as they stand" do
          familiar.update(:damage => 6)

          expect(sheet(@witch)).to include('HP: 24 / 30')
        end

        it "should count its own conditions, but not its master's" do
          ac = Npcs.stat(familiar, 'ac')['total']
          Pf2eCombatantState[@master_row['state']].update(:pf2_conditions => { 'Frightened' => { 'value' => 2, 'status' => true } })
          expect(sheet(@witch)).to include("AC: #{ac}")

          familiar.update(:pf2_conditions => { 'Frightened' => { 'value' => 1, 'status' => true } })
          text = sheet(@witch)

          expect(text).to include("AC: #{ac - 1}")
          expect(text).to include('Conditions: Frightened 1')
          expect(text).to include('All other skills: +5')
        end

        it "should say when it is Commanded" do
          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
          run(PF2EncounterActCmd, 'encounter/act command a minion=Smudge', @witch)

          expect(sheet(@witch)).to include('Actions: 0 of 2 used (Commanded)')
        end

        it "should be open to anyone, by the familiar's id or its master's name" do
          other = witch("Hazel#{rand(1000000)}")
          join(other, 5)

          expect(sheet(other, @ref)).to include("Smudge (#{@witch.name}'s familiar)")
          expect(sheet(other, @witch.name)).to include("In Encounter #{@encounter.id}")
        end

        it "should refuse a familiar that hasn't joined, and a creature" do
          run(PF2EncounterFamiliarCmd, 'encounter/familiar/leave', @witch)
          expect(sheet(@witch)).to include("familiar isn't in this encounter. To see its sheet outside the fight, use 'sheet/familiar'.")

          expect(sheet(@witch, 'Goblin')).to include("Goblin isn't a familiar or a character with one")
        end
      end

      describe "encounter/view" do
        before(:each) do
          Combatants.join(encounter, 'Goblin', 20)
          join(@witch)
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
        end

        def view(viewer)
          PF2EncounterViewTemplate.new(encounter, @client, Character[viewer.id]).combatant_list.map do |line|
            line.gsub(/%x(\d+|[a-zA-Z])/, '').gsub('%b', ' ')
          end
        end

        it "should show the familiar after its master, with no initiative and its stats, to a player" do
          lines = view(@witch)
          at = lines.index { |line| line.include?('Smudge') }
          row_before = lines[0...at].reverse.find { |line| !line.start_with?(' ') }

          expect(row_before).to include(@witch.name)
          expect(lines[at]).to match(/\A##{familiar_row['id']}\s+--\s+Smudge\s+Familiar 6\s/)
          expect(lines[at]).to include('30')
          expect(lines[at]).not_to include('?')
          expect(lines[at + 1]).to include("#{@witch.name}'s familiar")
        end
      end
    end
  end
end
