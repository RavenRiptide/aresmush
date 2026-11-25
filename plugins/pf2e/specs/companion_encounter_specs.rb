require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # An animal companion in an encounter: it joins when its player says it is there, is targeted like
    # anyone, fights with its own stats and Strikes, takes no turn of its own, leaves with its master, and
    # comes into an encounter that carries on from one it was in as it left that one. The master is a level 1
    # druid of the animal order with an approved wolf, Ash.
    describe "an animal companion in an encounter", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        allow(Jobs).to receive(:notify)
        allow(Login).to receive(:notify)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Scenes).to receive(:add_to_scene)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))

        @client = AutoBuilder::CaptureClient.new
        @room = Room.create(:name => "Field#{rand(1000000)}")
        @scene = Scene.create(:room => @room, :temp_room => true)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @made = []

        @druid = druid("Rowan#{rand(1000000)}")
        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :round => 0)

        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.emit(message) }
      end

      after(:each) do
        PF2Encounter.find(:scene_id => @scene.id).each do |one|
          one.npcs.each(&:delete)
          one.states.each(&:delete)
          one.delete
        end
        (@made + [ @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def druid(name)
        char = Character.create(:name => name)
        builder = AutoBuilder.new(char)
        builder.prefer.merge!('Animal Companion' => 'Wolf')
        builder.build_level_one('Druid', specialty: 'Animal')

        run(PF2CompanionNameCmd, 'companion/name Ash', char)
        Roles.add_role(Character[char.id], 'approved')
        Ledger.commit_chargen!(Character[char.id])
        Companion.approve_with_app!(Character[char.id])
        Character[char.id].update(:room => @room)
        @scene.participants.add Character[char.id]
        @made << char
        Character[char.id]
      end

      def encounter
        PF2Encounter[@encounter.id]
      end

      def join(char, init = 15, into = encounter)
        row = Combatants.join(into, char.name, init, :holder => Character[char.id])
        Character[char.id].encounters.add into
        into.characters.add Character[char.id]
        row
      end

      def run(klass, text, who)
        @client.clear
        klass.new(@client, Command.new(text), Character[who.id]).on_command
      end

      def failures
        @client.failures.join("\n")
      end

      def said
        (@client.successes + @client.oocs).join("\n")
      end

      def companion_row(into = encounter)
        Combatants.rows(into).find { |row| row['master'] && Pf2eNpc[row['npc']]&.companion? }
      end

      def companion(into = encounter)
        Pf2eNpc[companion_row(into)['npc']]
      end

      def stats
        char = Character[@druid.id]
        Companion.stats(char, Companion.main(char), :draft => false)
      end

      # A goblin with a stat block of its own, to be Struck.
      def goblin(hp = 20)
        npc = Pf2eNpc.create(:encounter => encounter, :name => 'Goblin', :number => encounter.last_number.to_i + 1,
                             :described => { 'name' => 'Goblin', 'level' => 1, 'hp' => hp, 'ac' => 8, 'perception' => 5,
                                             'saves' => { 'fortitude' => 5, 'reflex' => 7, 'will' => 3 } })
        Combatants.join(encounter, 'Goblin', 20, :holder => npc)
      end

      describe "joining" do
        before(:each) do
          goblin
          @master_row = join(@druid)
        end

        it "should join under its name, naming its master's row" do
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)

          expect(failures).to eq ''
          expect(companion_row['name']).to eq 'Ash'
          expect(companion_row['master']).to eq @master_row['id']
          expect(companion.master.character.id).to eq @druid.id
          expect(said).to include("Ash, #{@druid.name}'s animal companion, joins encounter #{@encounter.id} as ##{companion_row['id']}")
        end

        it "should be targeted by its id or its name, on the characters' side, with no reactions" do
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)

          expect(Combatants.find(encounter, "##{companion_row['id']}").state.holder).to eq companion
          expect(Combatants.find(encounter, 'ash').state.holder).to eq companion
          expect(Actors.of(companion)).to be_a(CompanionActor)
          expect(Actors.of(companion).side).to eq 'characters'
          expect(Actors.of(companion).reactions?).to be false
        end

        it "should fight with its own level, hit points, AC and saves" do
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)

          expect(companion.pf2_level).to eq 1
          expect(companion.max_hp).to eq stats['hp']
          expect(companion.hp_left).to eq stats['hp']
          expect(Npcs.stat(companion, 'ac')['total']).to eq stats['ac']
          expect(Npcs.stat(companion, 'save', 'Reflex')['total']).to eq stats['saves']['Reflex']
          expect(Npcs.stat(companion, 'perception')['total']).to eq stats['perception']
        end

        it "should keep its AC when its master is frightened in the fight" do
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          before = Npcs.stat(companion, 'ac')['total']

          Pf2eCombatantState[@master_row['state']].update(:pf2_conditions => { 'Frightened' => { 'value' => 2, 'status' => true } })

          expect(Npcs.stat(companion, 'ac')['total']).to eq before
        end

        it "should Strike with its own attacks" do
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          jaws = stats['attacks'].find { |one| one['name'] == 'Jaws' }

          strike = Npcs.strike(companion, 'jaws')

          expect(strike['name']).to eq 'Jaws'
          expect(strike['bonus']).to eq jaws['bonus']
          expect(strike['damage']).to eq [ [ "#{jaws['dice']}#{jaws['die']}+#{jaws['modifier']}", 'piercing', nil ] ]
        end

        it "should read a trained skill as its own, and an untrained one as its attribute" do
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)

          expect(Npcs.stat(companion, 'skill', 'Athletics')['total']).to eq stats['skills']['Athletics']['value']
          expect(Npcs.stat(companion, 'skill', 'Arcana')['total']).to eq stats['attributes']['Intelligence']
        end

        it "should be refused a second time" do
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)

          expect(failures).to include('Ash is already in this encounter')
          expect(Combatants.rows(encounter).count { |row| row['master'] }).to eq 1
        end

        it "should be refused when another combatant has its name" do
          Combatants.join(encounter, 'ash', 5)

          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)

          expect(failures).to include('already called Ash')
          expect(companion_row).to be_nil
        end

        it "should let the GM bring in someone's companion, and nobody else" do
          other = druid("Hazel#{rand(1000000)}")

          run(PF2EncounterCompanionCmd, "encounter/companion #{@druid.name}", other)
          expect(failures).to include(t('pf2e.not_organizer'))

          run(PF2EncounterCompanionCmd, "encounter/companion #{@druid.name}", @gm)
          expect(failures).to eq ''
          expect(companion.master.character.id).to eq @druid.id
        end

        it "should be taken back by undo" do
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          npc = companion

          run(PF2EncounterUndoCmd, 'encounter/undo', @gm)

          expect(failures).to eq ''
          expect(companion_row).to be_nil
          expect(Pf2eNpc[npc.id]).to be_nil
        end

        it "should join beside its master's familiar, each joining and leaving as itself" do
          char = Character[@druid.id]
          features = char.pf2_features || {}
          char.update(:pf2_features => features.merge('charclass_features' => Array(features['charclass_features']) + [ 'Familiar' ]),
                      :pf2_familiar => { 'approved' => { 'name' => 'Smudge', 'species' => 'black cat', 'form' => 'land', 'source' => 'Familiar' } })

          # The companion first: a familiar once took any creature with its master for itself.
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @druid)
          expect(failures).to eq ''
          expect(Combatants.minions_of(encounter, @master_row['id']).map { |row| row['name'] }.sort).to eq [ 'Ash', 'Smudge' ]
          expect(Actors.of(Combatants.find(encounter, 'Smudge').state.holder)).to be_a(FamiliarActor)

          run(PF2EncounterFamiliarCmd, 'encounter/familiar', @druid)
          expect(failures).to include('Smudge is already in this encounter')

          run(PF2EncounterFamiliarCmd, 'encounter/familiar/leave', @druid)
          expect(Combatants.minions_of(encounter, @master_row['id']).map { |row| row['name'] }).to eq [ 'Ash' ]

          run(PF2EncounterCompanionCmd, 'encounter/companion/leave', @druid)
          expect(Combatants.minions_of(encounter, @master_row['id'])).to eq []
        end

        it "should be left out of the encounter's difficulty" do
          without = Difficulty.of_encounter(encounter)
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)

          expect(Difficulty.of_encounter(encounter)).to eq without
        end
      end

      describe "refused" do
        it "when its master isn't in the encounter" do
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)

          expect(failures).to include("#{@druid.name} isn't in this encounter")
        end

        it "when staff haven't approved it" do
          join(@druid)
          held = Companion.record(@druid)
          held['companions'].each_value { |entry| entry.delete('approved') }
          Character[@druid.id].update(:pf2_companions => held)

          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)

          expect(failures).to include("animal companion isn't approved yet")
          expect(companion_row).to be_nil
        end

        it "when it is dead" do
          join(@druid)
          Companion.mark_dead!(Character[@druid.id], :dead => true)

          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)

          expect(failures).to include('animal companion is dead')
        end

        it "when it has no name" do
          join(@druid)
          held = Companion.record(@druid)
          held['companions'].each_value { |entry| entry['approved']['name'] = nil }
          Character[@druid.id].update(:pf2_companions => held)

          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)

          expect(failures).to include('needs a name before it can join')
        end

        it "when its master has none" do
          other = Character.create(:name => "Plain#{rand(1000000)}", :room => @room)
          @made << other
          Combatants.join(encounter, other.name, 5)

          run(PF2EncounterCompanionCmd, "encounter/companion #{other.name}", @gm)

          expect(failures).to include("#{other.name} doesn't have an animal companion")
        end
      end

      describe "leaving" do
        before(:each) do
          @master_row = join(@druid)
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          @npc = companion
        end

        it "should go when its player says" do
          run(PF2EncounterCompanionCmd, 'encounter/companion/leave', @druid)

          expect(failures).to eq ''
          expect(companion_row).to be_nil
          expect(Pf2eNpc[@npc.id]).to be_nil
          expect(said).to include("Ash, #{@druid.name}'s animal companion, leaves encounter")
        end

        it "should go with its master" do
          Combatants.leave(encounter, @master_row['id'])

          expect(Combatants.rows(encounter)).to eq []
          expect(Pf2eNpc[@npc.id]).to be_nil
        end

        it "should be refused when it isn't there" do
          run(PF2EncounterCompanionCmd, 'encounter/companion/leave', @druid)
          run(PF2EncounterCompanionCmd, 'encounter/companion/leave', @druid)

          expect(failures).to include("animal companion isn't in this encounter")
        end
      end

      # As its master does, it carries on from an earlier encounter only where the GM says this one carries
      # on from it.
      describe "carrying on" do
        before(:each) do
          join(@druid)
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          companion.update(:damage => 5, :pf2_conditions => { 'Frightened' => { 'value' => 1, 'status' => true } })
          ActiveEffects.apply(companion, 'Effect: Mounted', :encounter => encounter)
        end

        def next_encounter(carries_on)
          later = PF2Encounter.create(:scene => @scene, :owner => @gm, :round => 0,
                                      :carries_on_from => carries_on ? @encounter.id : nil)
          join(@druid, 15, later)
          later
        end

        it "should come in as it left an encounter this one carries on from" do
          later = next_encounter(true)

          outcome = Companion::Joining.join!(later, Character[@druid.id], Combatants.rows(later).find { |row| row['char'].to_s == @druid.id.to_s })

          expect(outcome.ok?).to be true
          now = companion(later)
          expect(now.damage).to eq 5
          expect(Pf2e.condition_level(now, 'Frightened')).to eq 1
          expect(now.pf2_effects.map(&:name)).to include('Effect: Mounted')
          expect(outcome.messages.first['key']).to eq 'pf2e.companion_encounter_joined_carried'
        end

        it "should come in fresh otherwise" do
          later = next_encounter(false)

          outcome = Companion::Joining.join!(later, Character[@druid.id], Combatants.rows(later).find { |row| row['char'].to_s == @druid.id.to_s })

          now = companion(later)
          expect(now.damage).to eq 0
          expect(now.pf2_conditions).to eq({})
          expect(now.pf2_effects.to_a).to eq []
          expect(outcome.messages.first['key']).to eq 'pf2e.companion_encounter_joined'
        end
      end

      # Commanded, it acts in its master's turn with 2 actions, or 3 with Companion's Cry; once mature, it has 1
      # action of its own without a Command. A player is refused what the rules don't let it do, and the GM
      # isn't.
      describe "acting" do
        before(:each) do
          goblin
          @master_row = join(@druid, 15)
          Combatants.join(encounter, 'Orc', 10)
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          @ref = "##{companion_row['id']}"
          # The Goblin's turn, then Rowan's.
          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
        end

        def used
          TurnState.turn(companion)['actions'].to_i
        end

        def master_used
          TurnState.turn(Pf2eCombatantState[@master_row['state']])['actions'].to_i
        end

        def reminder
          Turns.reminder(Pf2eCombatantState[@master_row['state']], 1).to_s.gsub(/%x(\d+|[a-zA-Z])/, '')
        end

        it "should have no actions until Commanded" do
          expect(ActiveEffects.current_turn(encounter)).to eq @druid.name
          expect(TurnState.actions(companion)).to eq 0

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @druid)

          expect(failures).to include('Ash has no actions left this turn')
          expect(failures).to include('e/act command an animal=')
        end

        it "should have 2 actions for 1 of its master's once Commanded, with no Nature check, and Strike with them" do
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)

          expect(failures).to eq ''
          expect(said).to include('Ash gains 2 actions this turn')
          expect(said).not_to match(/Nature/i)
          expect(master_used).to eq 1

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=strike jaws=Goblin", @druid)
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @druid)
          expect(failures).to eq ''
          expect(used).to eq 2

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @druid)
          expect(failures).to include('no actions left')
        end

        it "should take its own multiple attack penalty, not its master's" do
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=strike jaws=Goblin", @druid)

          expect(TurnState.turn(companion)['attacks']).to eq 1
          expect(TurnState.turn(Pf2eCombatantState[@master_row['state']])['attacks'].to_i).to eq 0
        end

        it "should be Commanded by Command a Minion too, as it is a minion" do
          run(PF2EncounterActCmd, 'encounter/act command a minion=Ash', @druid)

          expect(failures).to eq ''
          expect(TurnState.actions(companion)).to eq 2
        end

        it "should be Commanded only once a turn" do
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)

          expect(failures).to include('Ash has already been Commanded this turn')
          expect(master_used).to eq 1
        end

        it "should take 2 actions for 3 with Companion's Cry, and refuse 2 without it" do
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash/actions 2', @druid)
          expect(failures).to include("You need the Companion's Cry feat")
          expect(master_used).to eq 0

          allow(Companion::Minion).to receive(:cry?).and_return(true)
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash/actions 2', @druid)

          expect(failures).to eq ''
          expect(said).to include('Ash gains 3 actions this turn')
          expect(master_used).to eq 2
          expect(TurnState.actions(companion)).to eq 3
        end

        it "should refuse 2 actions on Command a Minion, and 3 on either" do
          allow(Companion::Minion).to receive(:cry?).and_return(true)

          run(PF2EncounterActCmd, 'encounter/act command a minion=Ash/actions 2', @druid)
          expect(failures).to include('You can spend 1 action on Command a Minion')

          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash/actions 3', @druid)
          expect(failures).to include('You can spend 1 action on Command an Animal')
        end

        it "should act only on its master's turn" do
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)
          run(PF2EncounterNextCmd, 'encounter/next', @gm)

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @druid)

          expect(failures).to include("Ash acts only on #{@druid.name}'s turn")
        end

        it "should lose the command when its master's next turn starts" do
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @druid)

          3.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }

          expect(ActiveEffects.current_turn(encounter)).to eq @druid.name
          expect(Companion::Minion.commanded?(companion)).to be false
          expect(used).to eq 0
        end

        it "should refuse spells and reactions to a player" do
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=cast heal=#{@druid.name}", @druid)
          expect(failures).to include('Ash can only take actions')

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act shield block", @druid)
          expect(failures).to include("Ash can't use reactions")
        end

        it "should let the GM have it do anything, Commanded or not" do
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=strike jaws=Goblin", @gm)

          expect(failures).to eq ''
          expect(said).to include('Jaws')
        end

        describe "once mature" do
          before(:each) do
            allow(Companion::Minion).to receive(:independent?).and_return(true)
          end

          it "should have 1 action of its own to Strike or Stride, and nothing else" do
            expect(TurnState.actions(companion)).to eq 1

            run(PF2EncounterAsCmd, "encounter/as #{@ref}=act trip=Goblin", @druid)
            expect(failures).to include('Without a Command, Ash can use its own action only to Strike or Stride')

            run(PF2EncounterAsCmd, "encounter/as #{@ref}=strike jaws=Goblin", @druid)
            expect(failures).to eq ''
            expect(used).to eq 1
          end

          it "should refuse a move it has no Speed for" do
            run(PF2EncounterAsCmd, "encounter/as #{@ref}=act fly", @druid)

            expect(failures).to include('Command it to Fly')
          end

          it "should refuse a Command once it has used its own action" do
            run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @druid)
            run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)

            expect(failures).to include('Ash used its own action this round')
            expect(master_used).to eq 0
          end

          it "should have 2 actions when Commanded, not 3" do
            run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)

            expect(TurnState.actions(companion)).to eq 2
            run(PF2EncounterAsCmd, "encounter/as #{@ref}=act trip=Goblin", @druid)
            expect(failures).not_to include('Without a Command')
          end

          it "should say in its master's reminder that it can act alone" do
            expect(reminder).to include("Ash acts when you Command it: 'e/act command an animal=#{@ref}'")
            expect(reminder).to include('it can use 1 action of its own')
          end
        end

        it "should read its independence and Companion's Cry from its master's feats" do
          expect(Companion::Minion.independent?(companion)).to be false
          expect(Companion::Minion.cry?(companion)).to be false

          allow(Companion).to receive(:held).and_return([ [ 'Mature Animal Companion (Druid)', { 'companion_independent' => 1 } ],
                                                          [ "Companion's Cry", {} ] ])

          expect(Companion::Minion.independent?(companion)).to be true
          expect(Companion::Minion.cry?(companion)).to be true
        end

        it "should remind its master how to Command it" do
          expect(reminder).to include("Ash acts only when you Command it: 'e/act command an animal=#{@ref}'")
        end

        it "should tell its master what it took" do
          told = []
          allow(Login).to receive(:notify) { |char, _kind, message, _id| told << [ char.id, message ] }

          Actors.of(companion).notify_damage(4, 'Goblin')

          expect(told).to eq [ [ @druid.id, 'Your animal companion Ash takes 4 damage from Goblin.' ] ]
        end

        it "should be no familiar to encounter/sheet/familiar" do
          run(PF2EncounterFamiliarSheetCmd, "encounter/sheet/familiar #{@ref}", @druid)

          expect(failures).to include("isn't a familiar or a character with one")
        end
      end

      # Support: its master's benefit until the start of their next turn, `support` on a Strike to use it, and
      # only basic move actions for the companion afterwards. A d20 shows 10, which hits the goblin (AC 8) without a
      # critical, and every other die 3.
      describe "Support" do
        before(:each) do
          allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ sides.to_i == 20 ? @d20 : 3 ] * amount.to_i }
          @d20 = 10
          goblin
          @master_row = join(@druid, 15)
          Combatants.join(encounter, 'Orc', 10)
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          @ref = "##{companion_row['id']}"
          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)
        end

        def master
          Pf2eCombatantState[@master_row['state']]
        end

        def gob
          Combatants.find(encounter, 'Goblin').state.holder
        end

        def as_type(type, advanced: false)
          allow(Companion::Block).to receive(:of).and_wrap_original do |original, npc|
            original.call(npc).merge('type' => type, 'advanced' => advanced)
          end
        end

        def support!
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act support", @druid)
          expect(failures).to eq ''
        end

        def strike!(words = '/support')
          run(PF2EncounterStrikeCmd, "encounter/strike fist=Goblin#{words}", @druid)
        end

        it "should give its master the effect until the start of their next turn" do
          support!

          expect(said).to include("Ash Supports #{@druid.name} until the start of their next turn")
          expect(master.pf2_effects.map(&:name)).to include(Companion::Support::EFFECT)

          3.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
          expect(ActiveEffects.current_turn(encounter)).to eq @druid.name
          expect(Pf2eCombatantState[master.id].pf2_effects.map(&:name)).not_to include(Companion::Support::EFFECT)
        end

        it "should refuse the word without a companion Supporting" do
          strike!

          expect(failures).to include("has no animal companion Supporting them, so 'support' can't be added")
        end

        it "should be refused after another action, and allow only basic move actions after it" do
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @druid)
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act support", @druid)
          expect(failures).to include('Ash has already acted this turn')

          3.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)
          support!

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=strike jaws=Goblin", @druid)
          expect(failures).to include('Ash Supported you this turn, so it can use only basic move actions')

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @druid)
          expect(failures).to eq ''
        end

        it "should leave a wolf's Speed penalty on a creature the Strike damages" do
          support!
          strike!

          expect(failures).to eq ''
          expect(gob.pf2_effects.map(&:name)).to include('Effect: Wolf Support')
          expect(said).to include('-5-foot status penalty to its Speeds')
        end

        it "should leave nothing without the word" do
          support!
          strike!('')

          expect(gob.pf2_effects.map(&:name)).not_to include('Effect: Wolf Support')
        end

        it "should give a wolf's critical hit the -10-foot penalty" do
          @d20 = 20
          support!
          strike!

          expect(gob.pf2_effects.map(&:name)).to include('Effect: Wolf Support (Critical)')
        end

        it "should have a bear deal its own 1d8 slashing, or 2d8 once nimble or savage" do
          as_type('Bear')
          support!
          before = gob.damage.to_i
          strike!

          expect(said).to include("Ash's support deals damage too")
          expect(said).to match(/3 slashing/)
          expect(gob.damage.to_i).to be > before + 3

          as_type('Bear', :advanced => true)
          strike!
          expect(said).to match(/6 slashing/)
        end

        it "should have a boar add persistent bleed, doubled on a critical hit" do
          as_type('Boar')
          support!
          strike!
          expect(PersistentDamage.held(gob).find { |one| one['type'] == 'bleed' }['formula']).to eq '1d6'

          PersistentDamage.remove(gob, 'bleed')
          @d20 = 20
          strike!
          expect(PersistentDamage.held(gob).find { |one| one['type'] == 'bleed' }['formula']).to eq '2d6'
        end

        it "should leave a bird's Dazzled until the bleed ends" do
          as_type('Bird')
          support!
          strike!

          expect(Pf2e.held_conditions(gob)).to have_key('Dazzled')
          PersistentDamage.remove(Combatants.find(encounter, 'Goblin').state.holder, 'bleed')
          expect(Pf2e.held_conditions(gob)).not_to have_key('Dazzled')
        end

        it "should leave an ape's Frightened 1 and a cat's Off-Guard" do
          as_type('Ape')
          support!
          strike!
          expect(Pf2e.condition_level(gob, 'Frightened')).to eq 1

          as_type('Cat')
          strike!
          expect(Pf2e.held_conditions(gob)).to have_key('Off-Guard')
        end

        it "should give a shark's damage only to a slashing or piercing Strike" do
          as_type('Shark')
          support!
          strike!

          expect(said).not_to include("Ash's support deals damage too")
        end

        it "should tell the room another type's benefit" do
          as_type('Snake')
          support!
          strike!

          expect(said).to include("Ash's support: #{companion.stat_block['support_text']}")
        end
      end

      # Its advanced maneuver, once nimble or savage: each type's companion is the druid's, made a savage one of
      # that type. A d20 shows 10, which hits the goblin (AC 8) without a critical, and every other die 3.
      describe "advanced maneuvers" do
        before(:each) do
          allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ sides.to_i == 20 ? @d20 : 3 ] * amount.to_i }
          @d20 = 10
          # Enough hit points to live through a savage companion's Strikes.
          goblin(200)
          @master_row = join(@druid, 15)
          Combatants.join(encounter, 'Orc', 10)
        end

        def savage(type, specialized: false)
          allow(Companion).to receive(:stats).and_wrap_original do |original, char, held, **options|
            made = held.merge('type' => type, 'size' => type == 'Horse' ? 'Large' : nil, 'mature' => true, 'path' => 'savage')
            made = made.merge('specializations' => [ { 'name' => 'Daredevil' } ]) if specialized
            original.call(char, made, **options)
          end

          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          @ref = "##{companion_row['id']}"
          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)
          expect(failures).to eq ''
        end

        def as(text)
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=#{text}", @druid)
        end

        def gob
          Combatants.find(encounter, 'Goblin').state.holder
        end

        def grab_goblin
          Pf2e.set_condition(gob, 'Grabbed')
          Holding.mark(gob, 'Grabbed', 'Ash')
        end

        it "should be on the stat block only once it is nimble or savage" do
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)

          expect(companion.stat_block['actions'].map { |one| one['name'] }).to eq [ 'Support' ]
        end

        it "should need a Command, not be its own action" do
          allow(Companion::Minion).to receive(:independent?).and_return(true)
          savage('Wolf')
          3.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }

          as('act takedown')

          expect(failures).to include('Without a Command, Ash can use its own action only to Strike or Stride')
        end

        it "should knock the target of a wolf's jaws hit prone with Takedown, and refuse it without the hit" do
          savage('Wolf')

          as('act takedown')
          expect(failures).to include('Ash can use Takedown only right after its jaws Strike hits')

          as('strike jaws=Goblin')
          as('act takedown')
          expect(failures).to eq ''
          expect(Pf2e.held_conditions(gob)).to have_key('Prone')
          expect(TurnState.turn(companion)['actions']).to eq 2
        end

        it "should Grab with a bear's second claw Strike in Bear Hug" do
          savage('Bear')

          as('strike claw=Goblin')
          as('act bear hug')

          expect(failures).to eq ''
          expect(Pf2e.held_conditions(gob)).to have_key('Grabbed')
          expect(TurnState.turn(companion)['attacks']).to eq 2
        end

        it "should deal a shark's Shred to the target of its jaws hit, 3d8 once specialized" do
          savage('Shark')
          as('strike jaws=Goblin')
          before = gob.damage.to_i

          as('act shred')

          expect(failures).to eq ''
          expect(gob.damage.to_i - before).to eq 6
        end

        it "should Constrict a creature a snake has Grabbed, at its master's class DC, and refuse with nobody Grabbed" do
          savage('Snake')

          as('act constrict')
          expect(failures).to include('Ash')

          grab_goblin
          as('act constrict')
          expect(failures).to eq ''
          expect(said).to include('Fortitude')
          expect(companion.stat_block['actions'].last['text']).to start_with('12 bludgeoning, DC ')
        end

        it "should breathe a riding drake's fire once, with a basic Reflex save" do
          savage('Riding Drake')

          as('act fire breath=Goblin')
          expect(failures).to eq ''
          expect(said).to include('Reflex')

          3.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)
          as('act fire breath=Goblin')
          expect(failures).to include('Ash has already used Fire Breath as often as it can')
        end

        it "should Demoralize with an ape's Frightening Display" do
          @d20 = 20
          savage('Ape')

          as('act frightening display=Goblin')

          expect(failures).to eq ''
          expect(Pf2e.condition_level(gob, 'Frightened')).to be >= 1
          expect(said).to include("it's off-guard to Ash")
        end

        it "should knock prone with a crocodile's Death Roll, or let go on a miss" do
          savage('Crocodile')
          grab_goblin

          expect(Acting).to receive(:strike).with(anything, 'jaws', [], hash_including(:bonus => { 'source' => 'Death Roll', 'value' => 2 }))
                                            .at_least(:once).and_call_original
          as('act death roll')
          expect(failures).to eq ''
          expect(Pf2e.held_conditions(gob)).to have_key('Prone')

          @d20 = 1
          as('act death roll')
          expect(said).to include('Ash misses and lets go of Goblin')
        end

        it "should Grab with a scorpion's pincer, then sting" do
          savage('Scorpion')

          as('act grab and sting=Goblin')

          expect(failures).to eq ''
          expect(Pf2e.held_conditions(gob)).to have_key('Grabbed')
          expect(TurnState.turn(companion)['attacks']).to eq 2
          expect(TurnState.turn(companion)['actions']).to eq 2
        end

        it "should thrash a bat's wings at up to three, moving the penalty on after all of them" do
          savage('Bat')
          kobold = Pf2eNpc.create(:encounter => encounter, :name => 'Kobold', :number => encounter.last_number.to_i + 1,
                                  :described => { 'name' => 'Kobold', 'level' => 0, 'hp' => 12, 'ac' => 8, 'perception' => 3,
                                                  'saves' => { 'fortitude' => 3, 'reflex' => 5, 'will' => 2 } })
          Combatants.join(encounter, 'Kobold', 5, :holder => kobold)

          as('act wing thrash=Goblin,Kobold')

          expect(failures).to eq ''
          expect(TurnState.turn(companion)['attacks']).to eq 2
          expect(said.scan(/Wing/).size).to be >= 2
        end

        it "should Strike after a told Stride with Cat Pounce, with the attack named" do
          savage('Cat')

          expect(Acting).to receive(:strike).with(anything, 'claw', [], anything).and_call_original
          as('act cat pounce=Goblin/claw')

          expect(failures).to eq ''
          expect(said).to include('Ash makes its Stride as part of it')
        end

        it "should give Boar Charge its +2 only with the word" do
          savage('Boar')

          expect(Acting).to receive(:strike).with(anything, 'tusk', [], hash_including(:bonus => nil)).and_call_original
          as('act boar charge=Goblin')

          expect(Acting).to receive(:strike).with(anything, 'tusk', [], hash_including(:bonus => { 'source' => 'Boar Charge', 'value' => 2 }))
                                            .and_call_original
          # Its 2 actions are spent, so the GM has it charge again.
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act boar charge=Goblin/moved", @gm)
        end

        it "should throw a sapling's rock as a Strike of its own" do
          savage('Arboreal Sapling')

          expect(companion.stat_block['strikes'].map { |one| one['name'] }).to include('Rock')
          as('act throw rock=Goblin')

          expect(failures).to eq ''
          expect(said).to include('Rock')
        end

        it "should rage a badger: more jaws damage, -1 AC, no concentrate actions but Seek, and no second rage" do
          savage('Badger')
          jaws = Npcs.strike(companion, 'jaws')['damage'].first.first
          ac = Npcs.stat(companion, 'ac')['total']

          as('act badger rage')
          expect(failures).to eq ''

          expect(Npcs.stat(companion, 'ac')['total']).to eq ac - 1
          expect(Npcs.strike(companion, 'jaws')['damage'].first.first).to eq jaws.sub(/([+-]\d+)\z/) { format('%+d', $1.to_i + 4) }

          as('act demoralize=Goblin')
          expect(failures).to include('Ash is raging, so it can\'t use Demoralize')

          as('act badger rage')
          expect(failures).to include('Ash is raging')
        end

        it "should announce a horse's Gallop for its 2 actions" do
          savage('Horse')

          as('act gallop')

          expect(failures).to eq ''
          expect(said).to include('Gallop')
          expect(TurnState.turn(companion)['actions']).to eq 2
        end
      end

      # Its sheet as it stands in the fight: what it has there first, then its figures with its own conditions
      # and effects counted.
      describe "encounter/sheet/companion" do
        before(:each) do
          goblin
          @master_row = join(@druid, 15)
          Combatants.join(encounter, 'Orc', 10)
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          @ref = "##{companion_row['id']}"
        end

        def sheet(viewer, target = nil)
          run(PF2EncounterCompanionSheetCmd, "encounter/sheet/companion #{target}".strip, viewer)
          (@client.successes + @client.failures).join("\n").gsub(/%x(\d+|[a-zA-Z])/, '')
        end

        it "should open with what it has in the encounter, and leave approval out" do
          text = sheet(@druid)

          expect(text).to include("Ash (#{@druid.name}'s companion)")
          expect(text).to include("In Encounter #{@encounter.id}")
          expect(text).to include("ID: #{@ref}")
          expect(text).to include('Actions: 0 of 0 used (not Commanded)')
          expect(text).to include('Conditions: none')
          expect(text).to include('Attacks')
          expect(text).not_to include(t('pf2e.companion_sheet_section_status'))
        end

        it "should show its hit points as they stand" do
          companion.update(:damage => 3)

          expect(sheet(@druid)).to include("HP: #{stats['hp'] - 3} / #{stats['hp']}")
        end

        it "should count its own conditions in its AC and attacks, but not its master's" do
          jaws = stats['attacks'].find { |one| one['name'] == 'Jaws' }
          Pf2eCombatantState[@master_row['state']].update(:pf2_conditions => { 'Frightened' => { 'value' => 2, 'status' => true } })
          text = sheet(@druid)
          expect(text).to include("AC: #{stats['ac']}")
          expect(text).to include("Jaws: #{Companion.signed(jaws['bonus'])}")

          companion.update(:pf2_conditions => { 'Frightened' => { 'value' => 1, 'status' => true } })
          text = sheet(@druid)

          expect(text).to include("AC: #{stats['ac'] - 1}")
          expect(text).to include("Jaws: #{Companion.signed(jaws['bonus'] - 1)}")
          expect(text).to include('Conditions: Frightened 1')
        end

        it "should say when it is Commanded, acting on its own, or Supporting" do
          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }

          allow(Companion::Minion).to receive(:independent?).and_return(true)
          expect(sheet(@druid)).to include('Actions: 0 of 1 used (its own action)')

          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)
          expect(sheet(@druid)).to include('Actions: 0 of 2 used (Commanded)')

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act support", @druid)
          expect(sheet(@druid)).to include("Ash is Supporting #{@druid.name} until the start of their next turn")
        end

        it "should be open to anyone, by the companion's id or name or its master's name" do
          other = druid("Hazel#{rand(1000000)}")
          join(other, 5)

          expect(sheet(other, @ref)).to include("Ash (#{@druid.name}'s companion)")
          expect(sheet(other, 'Ash')).to include("In Encounter #{@encounter.id}")
          expect(sheet(other, @druid.name)).to include("In Encounter #{@encounter.id}")
        end

        it "should refuse a companion that hasn't joined, a creature, and a character without one" do
          run(PF2EncounterCompanionCmd, 'encounter/companion/leave', @druid)
          expect(sheet(@druid)).to include("animal companion isn't in this encounter. To see its sheet outside the fight, use 'sheet/companion'.")

          expect(sheet(@druid, 'Goblin')).to include("Goblin isn't an animal companion or a character with one")

          plain = Character.create(:name => "Plain#{rand(1000000)}", :room => @room)
          @made << plain
          expect(sheet(@druid, plain.name)).to include("#{plain.name} doesn't have an animal companion")
        end

        it "should leave sheet/companion as it was" do
          run(PF2CompanionSheetCmd, "sheet/companion #{@druid.name}", @gm)
          text = (@client.successes + @client.failures).join("\n").gsub(/%x(\d+|[a-zA-Z])/, '')

          expect(text).not_to include('In Encounter')
          expect(text).to include("HP: #{stats['hp']}")
        end
      end

      # At 0 Hit Points it is knocked out and dying as a character is ("Knocked Out and Dying", Player Core),
      # makes its recovery checks as its master's turn starts, and dies only where Death Consent allows. The
      # spec's GM is an event runner, without it; `lethal` stands in for one with it.
      describe "at 0 Hit Points" do
        before(:each) do
          allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ sides.to_i == 20 ? @d20 : 3 ] * amount.to_i }
          @d20 = 10
          goblin
          @master_row = join(@druid, 15)
          Combatants.join(encounter, 'Orc', 10)
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          @ref = "##{companion_row['id']}"
        end

        def lethal
          allow(Gm).to receive(:lethal?).and_return(true)
        end

        def hurt(amount, critical: false, about: [])
          Harm.damage(companion, amount, 'slashing', :critical => critical, :about => about)
        end

        def most
          companion.max_hp
        end

        it "should be dying 1 and unconscious, not dead, when reduced to 0" do
          hurt(most)

          expect(Pf2e.condition_level(companion, 'Dying')).to eq 1
          expect(Pf2e.held_conditions(companion)).to have_key('Unconscious')
          expect(Pf2e.dead?(companion)).to be false
          expect(Actors.of(companion).dies_as_character?).to be true
        end

        it "should be dying 2 from a critical hit, more for its wounds, and more when hit while dying" do
          hurt(most, :critical => true)
          expect(Pf2e.condition_level(companion, 'Dying')).to eq 2

          hurt(1)
          expect(Pf2e.condition_level(companion, 'Dying')).to eq 3
        end

        it "should add its wounded value as it falls" do
          Pf2e.set_condition(companion, 'Wounded', 1)

          hurt(most)

          expect(Pf2e.condition_level(companion, 'Dying')).to eq 2
        end

        it "should be knocked out, not dying, by nonlethal damage" do
          hurt(most, :about => [ CharacterActor::NONLETHAL ])

          expect(Pf2e.condition_level(companion, 'Dying')).to eq 0
          expect(Pf2e.held_conditions(companion)).to have_key('Unconscious')
        end

        it "should die of massive damage where the GM has Death Consent, and be spared where not" do
          hurt(most * 2)
          expect(Pf2e.dead?(companion)).to be false
          expect(Pf2e.condition_level(companion, 'Wounded')).to eq 1

          lethal
          Harm.heal(companion, most)
          hurt(most * 2)
          expect(Pf2e.dead?(companion)).to be true
        end

        it "should keep Drained and Doomed off it without Death Consent, as off a character" do
          expect(Gm.spared?(companion, 'Doomed', 'Goblin')).to be true

          lethal
          expect(Gm.spared?(companion, 'Doomed', 'Goblin')).to be false
        end

        it "should make its recovery check as its master's turn starts" do
          hurt(most)
          @d20 = 20

          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }

          expect(ActiveEffects.current_turn(encounter)).to eq @druid.name
          expect(Pf2e.condition_level(companion, 'Dying')).to eq 0
          expect(Pf2e.condition_level(companion, 'Wounded')).to eq 1
          expect(said).to include('Ash')
        end

        it "should die of its recovery check with Death Consent, and its master's sheet is left to staff" do
          lethal
          hurt(most)
          Pf2e.set_condition(companion, 'Dying', 3)
          @d20 = 1

          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }

          expect(Pf2e.dead?(companion)).to be true
          expect(said.gsub(/%x(\d+|[a-zA-Z])/, '')).to include("has died. Staff record its death on #{@druid.name}'s sheet with 'companion/dead #{@druid.name}'")
          expect(Companion.dead?(Character[@druid.id])).to be false
        end

        it "should tell the room the same when a blow kills it" do
          lethal
          # Its master's turn first, so that no recovery check settles it before the blow.
          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
          hurt(most)
          Pf2e.set_condition(companion, 'Dying', 3)
          @d20 = 20

          run(PF2EncounterStrikeCmd, "encounter/strike fist=Ash", @druid)

          expect(Pf2e.dead?(companion)).to be true
          expect(said).to include("Ash, #{@druid.name}'s animal companion, has died")
        end

        it "should come out of dying when healed, wounded for it, and wake" do
          hurt(most)

          Harm.heal(companion, 5)

          expect(Pf2e.condition_level(companion, 'Dying')).to eq 0
          expect(Pf2e.condition_level(companion, 'Wounded')).to eq 1
          expect(Pf2e.held_conditions(companion)).not_to have_key('Unconscious')
          expect(companion.hp_left).to eq 5
        end

        it "should not act while unconscious" do
          hurt(most)
          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @druid)

          expect(failures).to include("Ash can't act: they have no hit points left, or are unconscious")
        end

        it "should offer its master no Hero Point to save it" do
          hurt(most)

          expect(HeroPoints.dying_hint(companion)).to be_nil
        end

        it "should stay dead in an encounter that carries on" do
          lethal
          hurt(most * 2)
          later = PF2Encounter.create(:scene => @scene, :owner => @gm, :round => 0, :carries_on_from => @encounter.id)
          join(@druid, 15, later)

          Companion::Joining.join!(later, Character[@druid.id], Combatants.rows(later).find { |row| row['char'].to_s == @druid.id.to_s })

          expect(Pf2e.dead?(companion(later))).to be true
        end
      end

      # Command an Animal at someone else's companion is the general action.
      it "should leave Command an Animal at another character's companion a Nature check" do
        goblin
        join(@druid, 15)
        other = druid("Hazel#{rand(1000000)}")
        join(other, 12)
        run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
        theirs = companion_row
        3.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
        expect(ActiveEffects.current_turn(encounter)).to eq other.name

        run(PF2EncounterActCmd, "encounter/act command an animal=##{theirs['id']}", other)

        expect(Companion::Minion.commanded?(Pf2eNpc[theirs['npc']])).to be false
        expect(said + failures).to match(/Nature/i)
      end

      describe "riding" do
        before(:each) do
          allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ sides.to_i == 20 ? @d20 : 3 ] * amount.to_i }
          @d20 = 10
          goblin
          @master_row = join(@druid, 15)
          Combatants.join(encounter, 'Orc', 10)
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          @ref = "##{companion_row['id']}"
          # The Goblin's turn, then Rowan's.
          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
        end

        def master
          Pf2eCombatantState[@master_row['state']]
        end

        # A young wolf is Small, too small for its master to ride.
        def as_mount(type: nil, size: 'Large', mount: false)
          allow(Companion::Block).to receive(:of).and_wrap_original do |original, npc|
            block = original.call(npc).merge('size' => size, 'mount' => mount)
            type ? block.merge('type' => type) : block
          end
        end

        def mount!
          run(PF2EncounterActCmd, 'encounter/act mount=Ash', @druid)
          expect(failures).to eq ''
        end

        def command!
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)
          expect(failures).to eq ''
        end

        def support!
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act support", @druid)
          expect(failures).to eq ''
        end

        def view
          PF2EncounterViewTemplate.new(encounter, @client, Character[@druid.id]).combatant_list.join("\n").gsub(/%x(\d+|[a-zA-Z])/, '')
        end

        def mounted?
          Pf2eCombatantState[master.id].pf2_effects.map(&:name).include?(Companion::Riding::EFFECT)
        end

        it "should refuse a companion not at least one size larger than its rider" do
          run(PF2EncounterActCmd, 'encounter/act mount=Ash', @druid)

          expect(failures).to include("Ash must be at least one size larger than #{@druid.name} to carry them")
          expect(companion.rider).to be_nil
        end

        it "should mount, putting Mounted on the rider, spending an action and showing it in the view" do
          as_mount
          mount!

          expect(said).to include("#{@druid.name} mounts Ash")
          expect(companion.rider.to_i).to eq @master_row['id']
          expect(mounted?).to be true
          expect(TurnState.turn(master)['actions'].to_i).to eq 1
          expect(view).to include('riding Ash')
          expect(view).to include("ridden by #{@druid.name}")
        end

        it "should dismount with Mount again" do
          as_mount
          mount!
          run(PF2EncounterActCmd, 'encounter/act mount', @druid)

          expect(failures).to eq ''
          expect(said).to include("#{@druid.name} dismounts from Ash")
          expect(companion.rider).to be_nil
          expect(mounted?).to be false
          expect(view).not_to include('riding Ash')
        end

        it "should refuse a rider's other move actions, but not the GM's" do
          as_mount
          mount!

          run(PF2EncounterActCmd, 'encounter/act stride', @druid)
          expect(failures).to include("While riding Ash, #{@druid.name}'s only move action is Mount")

          run(PF2EncounterAsCmd, "encounter/as #{@druid.name}=act stride", @gm)
          expect(failures).to eq ''
        end

        it "should refuse a second rider, and an unconscious mount" do
          as_mount
          mount!

          run(PF2EncounterAsCmd, 'encounter/as Goblin=act mount=Ash', @gm)
          expect(failures).to include("#{@druid.name} is already riding Ash")

          run(PF2EncounterActCmd, 'encounter/act mount', @druid)
          Pf2e.set_condition(companion, 'Unconscious', 1)
          run(PF2EncounterActCmd, 'encounter/act mount=Ash', @druid)
          expect(failures).to include("Ash can't carry a rider while it's unconscious or dead")
        end

        it "should keep a ridden companion to its land Speed, with no move after Support" do
          as_mount
          mount!
          command!

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act fly", @druid)
          expect(failures).to include('While carrying a rider, Ash can use only its land Speed')

          support!
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @druid)
          expect(failures).to include("can't move in the same turn it Supports")
        end

        it "should let a companion with the mount special move after Support" do
          as_mount(:mount => true)
          mount!
          command!
          support!

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @druid)
          expect(failures).to eq ''
        end

        it "should share one multiple attack penalty between rider and mount" do
          run(PF2EncounterStrikeCmd, 'encounter/strike fist=Goblin', @druid)
          expect(TurnState.map_options(companion)).to eq []

          as_mount
          mount!
          expect(TurnState.map_options(companion)).to eq [ 'map:increases:1' ]

          command!
          run(PF2EncounterAsCmd, "encounter/as #{@ref}=strike jaws=Goblin", @druid)
          expect(TurnState.map_options(master)).to eq [ 'map:increases:2' ]
        end

        it "should throw its rider when knocked out" do
          as_mount
          mount!
          Harm.damage(companion, companion.max_hp - 1, 'slashing')

          @d20 = 20
          run(PF2EncounterStrikeCmd, 'encounter/strike fist=Ash', @druid)

          # A fist is nonlethal: knocked out, not dying.
          expect(Pf2e.held_conditions(companion)).to have_key('Unconscious')
          expect(said).to include("#{@druid.name} falls off Ash and is no longer mounted")
          expect(companion.rider).to be_nil
          expect(mounted?).to be false
        end

        it "should throw its rider when it leaves" do
          as_mount
          mount!
          run(PF2EncounterCompanionCmd, 'encounter/companion/leave', @druid)

          expect(said).to include("Ash leaves the encounter, so #{@druid.name} is no longer mounted")
          expect(mounted?).to be false
        end

        it "should give Fell Rider's Aid to the first Demoralize after a ridden Support" do
          allow(Pf2e).to receive(:has_feat?).and_call_original
          allow(Pf2e).to receive(:has_feat?).with(anything, Companion::Riding::FELL_RIDER).and_return(true)
          as_mount
          mount!
          command!
          support!

          expect(said).to include("With Fell Rider, #{@druid.name} gains a +1 circumstance bonus")
          expect(TurnState.turn(master)['fell_rider']).to be true

          run(PF2EncounterActCmd, 'encounter/act demoralize=Goblin', @druid)
          expect(failures).to eq ''
          expect(Character[@druid.id].pf2_last_roll.to_s).to include('Fell Rider')
          expect(TurnState.turn(master)['fell_rider']).to be false
        end

        it "should add a horse's damage to a supported melee Strike after moving while mounted" do
          as_mount(:type => 'Horse', :mount => true)
          mount!
          command!
          support!

          run(PF2EncounterStrikeCmd, 'encounter/strike fist=Goblin/support', @druid)
          expect(said).to include("Ash's support adds damage only to a melee Strike made while riding it")

          run(PF2EncounterStrikeCmd, 'encounter/strike fist=Goblin/support/moved', @druid)
          expect(failures).to eq ''
          expect(said).to include("The Strike gains a +2 circumstance bonus to damage from Ash's support")
        end

        it "should have a riding drake deal its fire only to its rider's Strikes" do
          as_mount(:type => 'Riding Drake', :mount => true)
          command!
          support!

          run(PF2EncounterStrikeCmd, 'encounter/strike fist=Goblin/support', @druid)
          expect(said).to include("Ash's support deals damage only while you're riding it")

          mount!
          run(PF2EncounterStrikeCmd, 'encounter/strike fist=Goblin/support', @druid)
          expect(said).to include("Ash's support deals damage too")
          expect(said).to match(/3 fire/)
        end

        it "should have Heal Mount make lay on hands restore 10 per rank on its master's own companion" do
          allow(Pf2e).to receive(:has_feat?).and_call_original
          allow(Pf2e).to receive(:has_feat?).with(anything, Companion::Riding::HEAL_MOUNT).and_return(true)
          rider = Combatants.find(encounter, @druid.name).state
          ash = Combatants.find(encounter, 'Ash').state
          gob = Combatants.find(encounter, 'Goblin').state
          base = Acting.spell_mechanics('Lay on Hands').last

          healing = Acting.way_for(base, ash)
          healed = Companion::Riding.heal_mount(Acting::Scene.new(encounter, rider, ash, @druid, true), 'Lay on Hands', healing, ash)
          expect(healed['damage'].map { |one| one['formula'] }).to eq [ '10' ]
          expect(Acting.spell_damage(healed, 2).map(&:first).join(' ')).not_to include('6')

          other = Acting.way_for(base, gob)
          kept = Companion::Riding.heal_mount(Acting::Scene.new(encounter, rider, gob, @druid, true), 'Lay on Hands', other, gob)
          expect(kept).to eq other
        end
      end

      describe "hunting prey" do
        before(:each) do
          allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ sides.to_i == 20 ? @d20 : 3 ] * amount.to_i }
          @d20 = 10
          @ranger = ranger("Wren#{rand(1000000)}")
          goblin(60)
          @kobold = Pf2eNpc.create(:encounter => encounter, :name => 'Kobold', :number => encounter.last_number.to_i + 1,
                                   :described => { 'name' => 'Kobold', 'level' => 0, 'hp' => 12, 'ac' => 8, 'perception' => 3,
                                                   'saves' => { 'fortitude' => 3, 'reflex' => 5, 'will' => 2 } })
          Combatants.join(encounter, 'Kobold', 18, :holder => @kobold)
          @master_row = join(@ranger, 15)
          # The Goblin's turn, the Kobold's, then Wren's.
          3.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
        end

        # A level 1 ranger of the precision edge, with Animal Companion and an approved wolf, Ash.
        def ranger(name)
          char = Character.create(:name => name)
          builder = AutoBuilder.new(char)
          builder.prefer.merge!('charclass' => 'Animal Companion (Ranger)', 'Animal Companion (Ranger)' => 'Wolf')
          builder.build_level_one('Ranger', specialty: 'Precision')

          run(PF2CompanionNameCmd, 'companion/name Ash', char)
          Roles.add_role(Character[char.id], 'approved')
          Ledger.commit_chargen!(Character[char.id])
          Companion.approve_with_app!(Character[char.id])
          Character[char.id].update(:room => @room)
          @scene.participants.add Character[char.id]
          @made << char
          Character[char.id]
        end

        def master
          Pf2eCombatantState[@master_row['state']]
        end

        def gob
          Combatants.find(encounter, 'Goblin').state
        end

        def shared(holder)
          ActiveEffects.on(holder).select { |one| one.name.start_with?(HuntPrey::SHARE) }
        end

        def companion_in!
          run(PF2EncounterCompanionCmd, 'encounter/companion', @ranger)
          expect(failures).to eq ''
        end

        it "should be built as a precision ranger with Animal Companion" do
          expect(Character[@ranger.id].pf2_base_info['specialize']).to eq 'Precision'
          expect(Pf2e.has_feat?(Character[@ranger.id], HuntPrey::COMPANION_FEAT)).to be true
        end

        it "should need a creature to hunt in an encounter" do
          run(PF2EncounterActCmd, 'encounter/act hunt prey', @ranger)

          expect(failures).to include('Hunt Prey needs a creature to hunt')
        end

        it "should mark its prey, and move the mark to a new one" do
          run(PF2EncounterActCmd, 'encounter/act hunt prey=Goblin', @ranger)

          expect(failures).to eq ''
          expect(said).to include("uses Hunt Prey (one action) on Goblin, which is now their prey")
          expect(HuntPrey.prey(master)).to eq 'Goblin'
          expect(Marks.seen(master, gob, 'target')).to include('target:mark:hunted-prey')

          run(PF2EncounterActCmd, 'encounter/act hunt prey=Kobold', @ranger)
          expect(HuntPrey.prey(master)).to eq 'Kobold'
          expect(ActiveEffects.named_on(master, HuntPrey::EFFECT).size).to eq 1
        end

        it "should share its prey and hunter's edge with its companion, and move it with a new prey" do
          companion_in!
          run(PF2EncounterActCmd, 'encounter/act hunt prey=Goblin', @ranger)

          expect(said).to include("Ash shares the hunt on Goblin: now under Effect: Share Hunter's Edge (Precision)")
          expect(shared(companion).map(&:name)).to eq [ "Effect: Share Hunter's Edge (Precision)" ]
          expect(Marks.seen(companion, gob, 'target')).to include('target:mark:share-hunters-edge')

          run(PF2EncounterActCmd, 'encounter/act hunt prey=Kobold', @ranger)
          expect(shared(companion).size).to eq 1
          expect(shared(companion).first.mark['label']).to eq 'Kobold'
        end

        it "should share the hunt with a companion that joins after it" do
          run(PF2EncounterActCmd, 'encounter/act hunt prey=Goblin', @ranger)
          companion_in!

          expect(said).to include("Ash shares its master's hunt on Goblin")
          expect(shared(companion).first.mark['label']).to eq 'Goblin'
        end

        it "should give the Masterful version with Masterful Companion" do
          allow(Pf2e).to receive(:has_feat?).and_call_original
          allow(Pf2e).to receive(:has_feat?).with(anything, HuntPrey::MASTERFUL_FEAT).and_return(true)
          companion_in!
          run(PF2EncounterActCmd, 'encounter/act hunt prey=Goblin', @ranger)

          expect(shared(companion).map(&:name)).to eq [ HuntPrey::MASTERFUL_PRECISION ]
          expect(HuntPrey.precision_limit(companion)).to eq 2
        end

        it "should switch Precision on for the first hit on the prey each round only" do
          run(PF2EncounterActCmd, 'encounter/act hunt prey=Goblin', @ranger)

          expect(HuntPrey.precision_options(master, gob, [])).to eq [ HuntPrey::PRECISION, 'precision-hunters-edge:first-hit' ]
          expect(HuntPrey.precision_options(master, gob, [ { 'hit' => true, 'target' => 'Goblin' } ])).to eq []
          expect(HuntPrey.precision_options(master, Combatants.find(encounter, 'Kobold').state, [])).to eq []
        end

        it "should deal Precision's extra damage on the first hit on the prey, and not the second" do
          run(PF2EncounterActCmd, 'encounter/act hunt prey=Goblin', @ranger)
          @d20 = 19

          before = gob.holder.damage.to_i
          run(PF2EncounterStrikeCmd, 'encounter/strike fist=Goblin', @ranger)
          first = gob.holder.damage.to_i - before

          before = gob.holder.damage.to_i
          run(PF2EncounterStrikeCmd, 'encounter/strike fist=Goblin', @ranger)
          second = gob.holder.damage.to_i - before

          expect(failures).to eq ''
          # A critical hit each time: the precision 1d8 rolls 3, doubled.
          expect(first - second).to eq 6
        end

        it "should roll a Masterful companion's second hit with fewer precision dice" do
          allow(Pf2e).to receive(:has_feat?).and_call_original
          allow(Pf2e).to receive(:has_feat?).with(anything, HuntPrey::MASTERFUL_FEAT).and_return(true)
          companion_in!
          run(PF2EncounterActCmd, 'encounter/act hunt prey=Goblin', @ranger)

          strike = Npcs.strike(companion)
          marked = [ 'target:mark:share-hunters-edge', HuntPrey::PRECISION ]
          first = Npcs.strike_damage(companion, strike, marked + [ 'precision-hunters-edge:first-hit' ])
          second = Npcs.strike_damage(companion, strike, marked + [ 'precision-hunters-edge:second-hit' ])

          expect(first.find { |row| row['category'] == 'precision' }['formula']).to eq '2d8'
          expect(second.find { |row| row['category'] == 'precision' }['formula']).to eq '1d8'
        end
      end

      describe "spells on a companion" do
        before(:each) do
          allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ sides.to_i == 20 ? @d20 : 3 ] * amount.to_i }
          @d20 = 10
          goblin
          @master_row = join(@druid, 15)
          Combatants.join(encounter, 'Orc', 10)
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
          @ref = "##{companion_row['id']}"
          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
        end

        def one(name)
          Combatants.find(encounter, name).state
        end

        def scene
          Acting::Scene.new(encounter, one(@druid.name), nil, Character[@druid.id], false)
        end

        def instinctive!
          allow(Actions).to receive(:usable).and_call_original
          allow(Actions).to receive(:usable).with(anything, Companion::Spells::INSTINCTIVE)
                                            .and_return(Ok.new(:state => Companion::Spells::INSTINCTIVE))
        end

        def heal_ash!
          Harm.damage(companion, 5, 'slashing')
          run(PF2EncounterCastCmd, 'encounter/cast heal animal=Ash/focus', @druid)
          expect(failures).to eq ''
        end

        it "should keep a spell for your animal companion to your own" do
          expect(Companion::Spells.refusal(scene, 'Magic Hide', [ one('Goblin') ], []).code).to eq :companion_spell_not_own
          expect(Companion::Spells.refusal(scene, 'Magic Hide', [ one('Ash') ], [])).to be_nil
          expect(Companion::Spells.refusal(scene, 'Magic Hide', [], []).code).to eq :companion_spell_untargeted
          expect(Companion::Spells.refusal(scene, 'Apex Companion', [ one('Goblin') ], []).code).to eq :companion_spell_not_own
        end

        it "should let Canopy Crawler reach its caster too, and leave Heal Animal open to any animal" do
          expect(Companion::Spells.refusal(scene, 'Canopy Crawler', [], [])).to be_nil
          expect(Companion::Spells.refusal(scene, 'Canopy Crawler', [ one(@druid.name) ], [])).to be_nil
          expect(Companion::Spells.refusal(scene, 'Canopy Crawler', [ one('Goblin') ], []).code).to eq :companion_spell_not_own
          expect(Companion::Spells.refusal(scene, 'Heal Animal', [ one('Goblin') ], [])).to be_nil
        end

        it "should refuse the cast before the spell is spent" do
          run(PF2EncounterCastCmd, 'encounter/cast magic hide=Goblin', @druid)

          expect(failures).to include('Magic Hide can be cast only on your own animal companion')
        end

        it "should make the companion Large under Enlarge Companion, large enough to ride" do
          expect(MonsterAbilities.size_of(companion)).to eq Size::SIZES.index('sm')

          ActiveEffects.apply(companion, 'Spell Effect: Enlarge Companion', :options => [ 'rank 2' ])
          expect(MonsterAbilities.size_of(Pf2eNpc[companion.id])).to eq Size::SIZES.index('lg')

          run(PF2EncounterActCmd, 'encounter/act mount=Ash', @druid)
          expect(failures).to eq ''
        end

        it "should make a character Large under Enlarge in the encounter, leaving their own sheet as it was" do
          state = Pf2eCombatantState[@master_row['state']]
          expect(Size.of(state)['size']).to eq 'med'

          ActiveEffects.apply(state, 'Spell Effect: Enlarge', :options => [ 'rank 2' ], :encounter => encounter)

          expect(Size.of(Pf2eCombatantState[state.id])['size']).to eq 'lg'
          expect(MonsterAbilities.size_of(Pf2eCombatantState[state.id])).to eq Size::SIZES.index('lg')
          expect(Size.of(Character[@druid.id])['size']).to eq 'med'
        end

        it "should give 2 actions with Support first through Instinctive Support, right after the spell" do
          instinctive!
          heal_ash!
          run(PF2EncounterActCmd, 'encounter/act instinctive support', @druid)

          expect(failures).to eq ''
          expect(said).to include('Ash gains 2 actions this turn from Instinctive Support, and must Support first')
          expect(TurnState.actions(companion)).to eq 2

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act stride", @druid)
          expect(failures).to include('Ash must use Support first')

          run(PF2EncounterAsCmd, "encounter/as #{@ref}=act support", @druid)
          expect(failures).to eq ''
        end

        it "should refuse Instinctive Support without the spell, or once something else is done" do
          instinctive!
          run(PF2EncounterActCmd, 'encounter/act instinctive support', @druid)
          expect(failures).to include('Instinctive Support works only right after')

          heal_ash!
          run(PF2EncounterActCmd, 'encounter/act stride', @druid)
          run(PF2EncounterActCmd, 'encounter/act instinctive support', @druid)
          expect(failures).to include('Instinctive Support works only right after')
        end

        it "should refuse Instinctive Support for a companion already Commanded" do
          instinctive!
          run(PF2EncounterActCmd, 'encounter/act command an animal=Ash', @druid)
          heal_ash!
          run(PF2EncounterActCmd, 'encounter/act instinctive support', @druid)

          expect(failures).to include('Ash has already been Commanded this turn')
          expect(TurnState.actions(companion)).to eq 2
        end
      end

      describe "encounter/view" do
        before(:each) do
          goblin
          join(@druid)
          run(PF2EncounterCompanionCmd, 'encounter/companion', @druid)
        end

        def view(viewer)
          PF2EncounterViewTemplate.new(encounter, @client, Character[viewer.id]).combatant_list.map do |line|
            line.gsub(/%x(\d+|[a-zA-Z])/, '').gsub('%b', ' ')
          end
        end

        it "should show the companion after its master, with no initiative and its stats, to a player" do
          lines = view(@druid)
          at = lines.index { |line| line.include?('Ash') }
          row_before = lines[0...at].reverse.find { |line| !line.start_with?(' ') }

          expect(row_before).to include(@druid.name)
          expect(lines[at]).to match(/\A##{companion_row['id']}\s+--\s+Ash\s+Companion 1\s/)
          expect(lines[at]).to include(stats['hp'].to_s)
          expect(lines[at]).not_to include('?')
          expect(lines[at + 1]).to include("#{@druid.name}'s animal companion")
        end
      end
    end
  end
end
