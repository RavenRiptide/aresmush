require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Witch feats that give the familiar an activity of its own: Shed Spirit, Stitching Strike and Patron's
    # Claim, each a basic save against the master's spell DC.
    describe "a familiar's activities" do

      describe "the dice" do
        def damage(spec, level)
          Familiar::Activities.damage(spec, level)
        end

        let(:scaling) { { 'base' => '6d6', 'from' => 9, 'every' => 2, 'add' => 2 } }

        it "should be the base before the first step" do
          expect(damage(scaling, 8)).to eq '6d6'
        end

        it "should add dice at the first step and every step after" do
          expect(damage(scaling, 9)).to eq '8d6'
          expect(damage(scaling, 10)).to eq '8d6'
          expect(damage(scaling, 11)).to eq '10d6'
          expect(damage(scaling, 20)).to eq '18d6'
        end

        it "should keep a fixed formula" do
          expect(damage('10d10', 18)).to eq '10d10'
        end
      end

      # A resistance's value reads the effect it comes from: Phase Familiar's is 2 x its rank + 3. It read an
      # empty item before, so every such value counted the item's level as 0.
      describe "a resistance read from its effect" do
        it "should count the effect's level" do
          source = Effects.source('Spell Effect: Phase Familiar',
                                  [ { 'key' => 'Resistance', 'type' => 'all-damage', 'value' => '2*(@item.level)+3' } ],
                                  'item' => { 'level' => 4 })

          expect(Rules.declarations([ source ], [], 'Resistance').map { |one| one['value'] }).to eq [ 11 ]
        end
      end

      describe "the shipped data" do
        before(:all) do
          @feats = YAML.load_file("game/config/pf2e_feat_class.yml")['pf2e_feats']
        end

        it "should give each feat its familiar's activity" do
          given = { 'Spirit Familiar (Witch)' => 'Shed Spirit', 'Stitched Familiar' => 'Stitching Strike',
                    "Patron's Claim" => "Patron's Claim" }

          given.each_pair do |feat, activity|
            action = @feats[feat]['familiar_action']

            expect(action['name']).to eq(activity), feat
            expect(action['cost']).to eq(2), feat
            expect(MonsterAbilities.row(activity)).to eq(MonsterAbilities::FAMILIAR_ACTIVITY), feat
          end
        end
      end

      describe "in an encounter", :dbtest => true do

        class FamiliarActivityClient
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

        def dc
          25
        end

        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @client = FamiliarActivityClient.new
          @room = Room.create(:name => "Field#{rand(1000000)}")
          @scene = Scene.create(:room => @room, :temp_room => true)
          @room.update(:scene => @scene)
          @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
          @made = []

          # Every die shows 10, so a d20 save is 10 plus the save, and each damage die is 10.
          allow(Pf2e).to receive(:roll_dice) { |amount = 1, _sides = 20| [ 10 ] * amount.to_i }
          allow(Familiar::Activities).to receive(:spell_dc).and_return(25)
          allow(Pf2emagic).to receive(:focus_pool_max).and_return(2)
          @witch = witch("Morwen#{rand(1000000)}", [ 'Spirit Familiar (Witch)', 'Stitched Familiar', "Patron's Claim",
                                                       "Patron's Presence" ])
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

        def witch(name, feats, level = 8)
          char = Character.create(:name => name, :room => @room)
          combat = Pf2eCombat.create(:character => char, :key_abil => 'Intelligence', :perception => 'trained',
                                     :armor_prof => { 'unarmored' => 'trained' },
                                     :saves => { 'Fortitude' => 'trained', 'Reflex' => 'trained', 'Will' => 'expert' })
          hp = Pf2eHP.create(:character => char, :ancestry_hp => 6, :charclass_hp => 6)
          magic = PF2Magic.create(:character => char)
          char.update(:combat => combat, :hp => hp, :magic => magic, :pf2_level => level, :pf2_conditions => {}, :pf2_traits => [],
                      :pf2_derived => {}, :pf2_feats => { 'charclass' => feats }, :pf2_daily_choices => {},
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

        # A creature whose every save is `save`, so a save is 10 + `save` against DC 25.
        def brute(name, save, hp = 500)
          described = { 'name' => name, 'level' => 1, 'hp' => hp, 'ac' => 15, 'perception' => 5, 'traits' => [ 'humanoid' ],
                        'saves' => { 'fortitude' => save, 'reflex' => save, 'will' => save } }
          Combatants.add_npc(encounter, :described => described, :name => name, :initiative => 1).state['npc']
        end

        # Joined, with Smudge, on Morwen's turn, and Smudge Commanded.
        def fight
          joined = Combatants.join(encounter, @witch.name, 15, :holder => Character[@witch.id])
          Character[@witch.id].encounters.add encounter
          encounter.characters.add Character[@witch.id]
          @master_row = joined
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
          @ref = "##{familiar_row['id']}"
          run(PF2EncounterNextCmd, 'encounter/next', @gm) until ActiveEffects.current_turn(encounter) == @witch.name
          run(PF2EncounterActCmd, "encounter/act command a minion=#{@ref}", @witch)
        end

        def as_familiar(text)
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act #{text}", @witch)
        end

        def taken(npc)
          500 - Pf2eNpc[npc.id].hp_left.to_i
        end

        describe "its stat block" do
          it "should carry each activity with its master's spell DC and the dice at their level" do
            fight

            shed = familiar.stat_block['actions'].find { |one| one['name'] == 'Shed Spirit' }

            expect(shed['text']).to start_with("(6d6) spirit, DC #{dc} basic Will")
            expect(shed['text']).to include("Smudge's spirit")
            expect(shed.keys).not_to include('damage', 'summary')
          end

          it "should have none without the feats" do
            Character[@witch.id].update(:pf2_feats => { 'charclass' => [] })
            fight

            names = familiar.stat_block['actions'].map { |one| one['name'] }
            expect(names).not_to include('Shed Spirit', 'Stitching Strike', "Patron's Claim")
          end
        end

        describe "Shed Spirit" do
          # A failed save (20 against 25) takes the full 60; the friend regains half.
          it "should heal the ally half of what landed on the enemy" do
            fight
            enemy = brute('Brute', 10)
            friend = brute('Friend', 10)
            Harm.damage(Pf2eNpc[friend.id], 100)

            as_familiar('shed spirit=Brute,Friend')

            expect(@client.failures).to eq []
            expect(taken(enemy)).to eq 60
            expect(taken(friend)).to eq 70
          end

          it "should say nobody is healed without an ally" do
            fight
            brute('Brute', 10)

            as_familiar('shed spirit=Brute')

            expect(@client.said.join).to include(t('pf2e.familiar_shed_spirit_no_ally', :name => 'Smudge'))
          end

          # 35 against 25 is a critical success: no damage, so nobody is healed.
          it "should heal nobody when no damage landed" do
            fight
            brute('Brute', 25)
            friend = brute('Friend', 10)
            Harm.damage(Pf2eNpc[friend.id], 100)

            as_familiar('shed spirit=Brute,Friend')

            expect(taken(friend)).to eq 100
          end

          it "should refuse a third target" do
            fight
            %w{Brute Friend Other}.each { |name| brute(name, 10) }

            as_familiar('shed spirit=Brute,Friend,Other')

            expect(@client.failures.join).to include(t('pf2e.familiar_activity_targets', :action => 'Shed Spirit', :most => 2))
          end

          it "should be refused to the player once it is used" do
            fight
            brute('Brute', 10)
            as_familiar('shed spirit=Brute')

            expect(Familiar::Minion.action_refusal(familiar, 'Smudge', 'shed spirit').code).to eq :familiar_spent
          end
        end

        describe "Stitching Strike" do
          it "should immobilize a target that fails, escaped from at the same DC" do
            fight
            enemy = brute('Brute', 10)

            as_familiar('stitching strike=Brute')

            held = Pf2eNpc[enemy.id].pf2_conditions['Immobilized']
            expect(taken(enemy)).to eq 60
            expect(held['escape_dc']).to eq dc
            expect(held['expires']).not_to be_nil
            expect(Acting.escape_dc(Pf2eNpc[enemy.id])).to eq dc
          end

          it "should leave a target that succeeds free" do
            fight
            enemy = brute('Brute', 15)

            as_familiar('stitching strike=Brute')

            expect(taken(enemy)).to eq 30
            expect(Pf2eNpc[enemy.id].pf2_conditions).not_to have_key('Immobilized')
          end
        end

        describe "Patron's Claim" do
          before(:each) do
            fight
            master.update(:focus_current => 0)
          end

          it "should drain a target that fails and give its master a Focus Point" do
            enemy = brute('Brute', 10)

            as_familiar("patron's claim=Brute")

            expect(Pf2eNpc[enemy.id].pf2_conditions['Drained']['value']).to eq 2
            expect(master.focus_current).to eq 1
          end

          it "should drain 4 on a critical failure" do
            enemy = brute('Brute', 0)

            as_familiar("patron's claim=Brute")

            expect(Pf2eNpc[enemy.id].pf2_conditions['Drained']['value']).to eq 4
          end

          it "should do neither on a success" do
            enemy = brute('Brute', 15)

            as_familiar("patron's claim=Brute")

            expect(Pf2eNpc[enemy.id].pf2_conditions).not_to have_key('Drained')
            expect(master.focus_current).to eq 0
          end
        end

        describe "Patron's Presence" do
          def presence
            Familiar::Presence
          end

          def enter(name)
            run(PF2EncounterAsCmd, "encounter/as #{@ref}=enter patron's presence=#{name}", @witch)
          end

          def stupefied(npc)
            Pf2eNpc[npc.id].pf2_conditions['Stupefied']
          end

          def inside?(npc)
            ActiveEffects.on(Pf2eNpc[npc.id]).any? { |one| one.name == presence::INSIDE }
          end

          before(:each) do
            fight
            as_familiar("patron's presence")
          end

          it "should put the sustained aura on the familiar" do
            aura = ActiveEffects.on(familiar).find { |one| one.name == presence::AURA }

            expect(@client.failures).to eq []
            expect(aura).not_to be_nil
            expect(aura.sustained).to be_truthy
            expect(@client.said.join).to include("enter patron's presence=<enemy>,<enemy>")
          end

          it "should stupefy an enemy that enters and fails, while it remains inside" do
            enemy = brute('Brute', 10)

            enter('Brute')

            expect(@client.failures).to eq []
            expect(inside?(enemy)).to be true
            expect(stupefied(enemy)['value']).to eq 2
            expect(stupefied(enemy)['aura_of']).to end_with(":#{presence::SLUG}")
          end

          it "should stupefy 3 on a critical failure" do
            enemy = brute('Brute', 0)

            enter('Brute')

            expect(stupefied(enemy)['value']).to eq 3
          end

          it "should end the stupefied condition when the enemy leaves" do
            enemy = brute('Brute', 10)
            enter('Brute')

            run(PF2EncounterAsCmd, "encounter/as #{@ref}=leave patron's presence=Brute", @witch)

            expect(stupefied(enemy)).to be_nil
            expect(inside?(enemy)).to be false
          end

          it "should end the stupefied condition when the aura ends" do
            enemy = brute('Brute', 10)
            enter('Brute')

            ActiveEffects.on(familiar).select { |one| one.name == presence::AURA }.each { |one| ActiveEffects.remove(familiar, one) }

            expect(stupefied(enemy)).to be_nil
            expect(inside?(enemy)).to be false
          end

          # 25 against 25 saves; a 1 at the start of its turn is a critical failure.
          it "should have an enemy still inside save again as its turn starts" do
            enemy = brute('Brute', 15)
            enter('Brute')
            expect(stupefied(enemy)).to be_nil

            allow(Pf2e).to receive(:roll_dice) { |amount = 1, _sides = 20| [ 1 ] * amount.to_i }
            lines = presence.turn_started(Pf2eNpc[enemy.id])

            expect(lines).not_to be_empty
            expect(stupefied(enemy)['value']).to eq 3
          end

          it "should not have an enemy the aura already stupefied save again" do
            enemy = brute('Brute', 10)
            enter('Brute')

            expect(presence.turn_started(Pf2eNpc[enemy.id])).to eq []
          end
        end

        # The master is 8th level, so the hex is rank 4: resistance 11.
        describe "Phase Familiar" do
          def phase
            Familiar::Phase
          end

          def hp_left
            Pf2eNpc[familiar.id].hp_left.to_i
          end

          def hit(rows)
            whom = Combatants.find(encounter, 'Smudge').state
            out = Acting.report
            Acting.deal(Acting::Scene.new(encounter, nil, whom, @gm, true), whom, rows, out)
            @client.said << Telling.lines(out['lines']).join("
")
          end

          def master_scene
            Acting::Scene.new(encounter, Combatants.find(encounter, @witch.name).state, nil, @witch, true)
          end

          def cast
            out = Acting.cast(master_scene, phase::SPELL, [], []).state
            @client.said << Telling.lines(out['lines']).join("
")
          end

          before(:each) do
            allow(phase).to receive(:knows?).and_return(true)
            fight
            @full = hp_left
          end

          it "should offer the hex when the familiar takes damage" do
            hit([ { 'amount' => 20, 'type' => 'bludgeoning' } ])

            expect(@client.said.join).to include(t('pf2e.familiar_phase_offer', :master => @witch.name, :name => 'Smudge'))
            expect(TurnState.of(familiar)[phase::KEY]).not_to be_nil
          end

          it "should deal the hit again with the spell's resistance, and leave nothing on the familiar" do
            hit([ { 'amount' => 20, 'type' => 'bludgeoning' } ])
            expect(hp_left).to eq @full - 20

            cast

            expect(hp_left).to eq @full - 9
            expect(@client.said.last).to include(t('pf2e.familiar_phase_taken', :name => 'Smudge', :resistance => 11))
            expect(@client.said.last).not_to include(t('pf2e.familiar_phase_offer', :master => @witch.name, :name => 'Smudge'))
            expect(ActiveEffects.on(Pf2eNpc[familiar.id]).map(&:name)).not_to include(phase::EFFECT)
            expect(TurnState.of(familiar)[phase::KEY]).to be_nil
          end

          it "should make the familiar immune to the hit's precision damage" do
            hit([ { 'amount' => 14, 'type' => 'piercing' }, { 'amount' => 6, 'type' => 'piercing', 'category' => 'precision' } ])

            cast

            expect(hp_left).to eq @full - 3
          end

          it "should refuse with no hit to answer" do
            expect(phase.refusal(master_scene, phase::SPELL).key).to eq 'pf2e.familiar_phase_no_hit'
          end

          it "should refuse once the familiar's hit points have moved" do
            hit([ { 'amount' => 20, 'type' => 'bludgeoning' } ])
            Harm.damage(Pf2eNpc[familiar.id], 1)

            expect(phase.refusal(master_scene, phase::SPELL).key).to eq 'pf2e.answer_too_late'
          end

          it "should not offer it to a master who doesn't know the hex" do
            allow(phase).to receive(:knows?).and_return(false)

            hit([ { 'amount' => 20, 'type' => 'bludgeoning' } ])

            expect(@client.said.join).not_to include('Phase Familiar')
          end
        end

        describe "its master" do
          it "should be refused the activity as their own, and pointed to e/as" do
            fight
            brute('Brute', 10)

            run(PF2EncounterActCmd, 'encounter/act shed spirit=Brute', @witch)

            expect(@client.failures.join).to include(t('pf2e.familiar_activity_own', :action => 'Shed Spirit'))
          end

          it "should be told by e/how to name the enemy and then the ally" do
            found = HowTo.answers('shed spirit', HowTo.known(Character[@witch.id], Character[@witch.id]))

            expect(found.state.map(&:first)).to include('+e/as <familiar>=act shed spirit=<enemy>,<ally>')
          end

          it "should see each activity on the familiar's sheet" do
            lines = Familiar::Activities.sheet_lines(Character[@witch.id], 'Smudge')

            expect(lines.first).to eq "Shed Spirit: 2 actions, once per 10 minutes. 6d6 spirit damage to an enemy (DC #{dc} basic Will " \
                                      'save); the ally you specify regains half the damage dealt.'
            expect(lines.size).to eq 4
          end
        end
      end
    end
  end
end
