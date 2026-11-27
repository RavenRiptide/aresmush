require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Feats that change what the encounter engine already does on its own: how a condition lands and
    # eases, what an aura carries, the multiple attack penalty, the concealment flat check, and what
    # happens when an action, a hit or a drop fires a feat.
    describe "feats triggered in an encounter", :dbtest => true do

      class FeatTriggersClient
        attr_reader :failures, :said

        def initialize
          @failures = []
          @said = []
        end

        def logged_in?
          true
        end

        def emit_failure(msg)
          @failures << msg.to_s
        end

        %w{emit_success emit emit_ooc}.each { |name| define_method(name) { |msg| @said << msg.to_s } }
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = FeatTriggersClient.new
        @room = Room.create(:name => "Arena#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Aria#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @hero, :armor_prof => { 'unarmored' => 'trained' },
                                    :weapon_prof => { 'unarmed' => 'trained', 'martial' => 'trained' },
                                    :unarmed_attacks => { 'Fist' => { 'damage' => 'd4', 'damage_type' => 'B',
                                                                      'traits' => %w{agile finesse nonlethal unarmed} } },
                                    :saves => { 'Fortitude' => 'trained', 'Reflex' => 'trained', 'Will' => 'trained' })
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 10)
        @hero.update(:combat => @combat, :hp => @hp, :pf2_level => 1, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Fighter' },
                     :pf2_movement => { 'base_speed' => 25 },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => @gm.name, :round => 1, :is_active => true)
        @hero.encounters.add @encounter
        @encounter.characters.add @hero

        @dice = 0.5
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * @dice).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow(Scenes).to receive(:add_to_scene)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Login).to receive(:notify)
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow_any_instance_of(Character).to receive(:has_permission?).and_call_original
        allow_any_instance_of(Character).to receive(:has_permission?).with('kill_pc') { |char, _| char.name == @gm.name }
      end

      after(:each) do
        encounter = PF2Encounter[@encounter.id]
        encounter&.npcs&.each(&:delete)
        Character[@hero.id].gear.each(&:delete)
        (@abilities + [ @encounter, @hp, @combat, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def hero
        Character[@hero.id]
      end

      def with_feats(*names)
        @hero.update(:pf2_feats => { 'general' => names })
        Paths.apply_all!(hero)
      end

      def frightened(holder)
        Pf2e.condition_level(holder, 'Frightened')
      end

      # ------------------------------------------------------------------------------
      # Conditions

      describe "Khazadi Doughtiness" do
        it "should ease Frightened by 1 at the end of a turn without it" do
          Pf2e.set_condition(hero, 'Frightened', 3)
          Turns.less_frightened(hero)

          expect(frightened(hero)).to eq 2
        end

        it "should ease Frightened by 2" do
          with_feats('Khazadi Doughtiness')
          Pf2e.set_condition(hero, 'Frightened', 3)
          Turns.less_frightened(hero)

          expect(frightened(hero)).to eq 1
        end

        it "should end Frightened 1 outright" do
          with_feats('Khazadi Doughtiness')
          Pf2e.set_condition(hero, 'Frightened', 1)
          told = Turns.less_frightened(hero)

          expect(hero.pf2_conditions).not_to have_key('Frightened')
          expect(told.first['key']).to eq 'pf2e.condition_ended'
        end
      end

      describe "Aura of Courage, for the champion" do
        before(:each) { with_feats('Aura of Courage') }

        it "should land Frightened 1 lower" do
          result = Pf2e.set_condition(hero, 'Frightened', 2)

          expect(result.ok?).to be true
          expect(frightened(hero)).to eq 1
        end

        it "should keep Frightened 1 from landing at all, and say why" do
          result = Pf2e.set_condition(hero, 'Frightened', 1)

          expect(result.err?).to be true
          expect(result.code).to eq :condition_eased
          expect(hero.pf2_conditions).not_to have_key('Frightened')
        end

        it "should leave a worsening that the reduction cancels where it was" do
          Pf2e.set_condition(hero, 'Frightened', 1)
          hero.update(:pf2_conditions => { 'Frightened' => { 'value' => 1, 'status' => true } })
          Pf2e.set_condition(hero, 'Frightened', 2)

          expect(frightened(hero)).to eq 1
        end

        it "should not touch Frightened as it eases" do
          hero.update(:pf2_conditions => { 'Frightened' => { 'value' => 3, 'status' => true } })
          Turns.less_frightened(hero)

          expect(frightened(hero)).to eq 2
        end

        it "should tell the room the value it really landed at" do
          Combatants.join(@encounter, @hero.name, 20, :holder => hero)
          @encounter = PF2Encounter[@encounter.id]
          whom = Combatants.find(@encounter, @hero.name).state
          scene = Acting::Scene.new(@encounter, whom, whom, @gm, true)
          out = Acting.report

          Acting.condition_consequence(scene, whom, { 'condition' => 'Frightened', 'value' => 3 }, out)

          expect(Telling.lines(out['lines']).join(' ')).to include('Frightened 2')
          expect(frightened(whom.holder)).to eq 2
        end
      end

      describe "Vigorous Health" do
        it "should land Drained without a check for anyone else" do
          @dice = 1.0
          Pf2e.set_condition(hero, 'Drained', 1)

          expect(Pf2e.condition_level(hero, 'Drained')).to eq 1
        end

        it "should keep Drained off on a DC 17 flat check" do
          with_feats('Vigorous Health')
          @dice = 1.0
          result = Pf2e.set_condition(hero, 'Drained', 1)

          expect(result.code).to eq :condition_resisted
          expect(result.args['die']).to eq 20
          expect(result.args['dc']).to eq 17
          expect(hero.pf2_conditions).not_to have_key('Drained')
        end

        it "should let Drained land when the flat check fails" do
          with_feats('Vigorous Health')
          result = Pf2e.set_condition(hero, 'Drained', 1)

          expect(result.ok?).to be true
          expect(Pf2e.condition_level(hero, 'Drained')).to eq 1
        end

        it "should roll again when Drained would worsen, and not when it eases" do
          with_feats('Vigorous Health')
          hero.update(:pf2_conditions => { 'Drained' => { 'value' => 2, 'status' => true } })
          @dice = 1.0

          expect(Pf2e.set_condition(hero, 'Drained', 3).code).to eq :condition_resisted
          expect(Pf2e.set_condition(hero, 'Drained', 1).ok?).to be true
          expect(Pf2e.condition_level(hero, 'Drained')).to eq 1
        end
      end

      describe "Stubborn Persistence" do
        it "should keep Fatigued off on a DC 17 flat check" do
          with_feats('Stubborn Persistence')
          @dice = 1.0

          expect(Pf2e.set_condition(hero, 'Fatigued').code).to eq :condition_resisted
          expect(hero.pf2_conditions).not_to have_key('Fatigued')
        end

        it "should not roll for Fatigued already held" do
          with_feats('Stubborn Persistence')
          hero.update(:pf2_conditions => { 'Fatigued' => { 'status' => true } })
          @dice = 1.0

          expect(Pf2e.set_condition(hero, 'Fatigued').ok?).to be true
          expect(hero.pf2_conditions).to have_key('Fatigued')
        end
      end

      # ------------------------------------------------------------------------------
      # Auras a character projects from their feats and class features

      describe "a character's auras" do
        before(:each) do
          @others = []
          @ally = person('Ally')
          @foe = person('Foe')
        end

        after(:each) do
          @others.each { |one| one&.delete }
        end

        # Someone else in the fight, with saves to roll.
        def person(name)
          char = Character.create(:name => "#{name}#{rand(1000000)}", :room => @room)
          combat = Pf2eCombat.create(:character => char, :saves => { 'Fortitude' => 'trained', 'Reflex' => 'trained', 'Will' => 'trained' })
          hp = Pf2eHP.create(:character => char, :ancestry_hp => 8, :charclass_hp => 8)
          char.update(:combat => combat, :hp => hp, :pf2_level => 1, :pf2_conditions => {}, :pf2_traits => [],
                      :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Fighter' },
                      :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
          abilities = Pf2e::ABILITIES.map { |one| Pf2eAbilities.create(:character => char, :name => one, :base_val => 10) }
          @others.concat(abilities + [ combat, hp, char ])
          char
        end

        def reread(char)
          Character[char.id]
        end

        def champion(*feats)
          @hero.update(:pf2_level => 4, :pf2_base_info => { 'charclass' => 'Champion' },
                       :pf2_features => { 'charclass_features' => [ "Champion's Aura" ], 'archetype_features' => [] })
          with_feats(*feats)
        end

        def aura(slug)
          Auras.of(hero).select { |one| one['slug'] == slug }
        end

        it "should project a champion's aura from the class feature" do
          champion

          expect(aura('champions-aura').size).to eq 1
          expect(aura('champions-aura').first['radius']).to eq 15
          expect(aura('champions-aura').first['effects']).to eq []
        end

        it "should gather what each feat adds to the same aura into one" do
          champion('Aura of Courage', 'Aura of Faith')

          expect(aura('champions-aura').size).to eq 1
          expect(aura('champions-aura').first['effects'].map { |one| one['name'] })
            .to contain_exactly('Effect: Aura of Courage', 'Effect: Aura of Faith')
        end

        describe "Aura of Courage, for allies" do
          before(:each) { champion('Aura of Courage') }

          it "should mark an ally inside, and not the champion" do
            Auras.enter(hero, reread(@ally), 'champions-aura', 'ally')
            Auras.enter(hero, hero, 'champions-aura', 'ally')

            expect(ActiveEffects.on(reread(@ally)).map(&:name)).to eq [ 'Effect: Aura of Courage' ]
            expect(ActiveEffects.on(hero).map(&:name)).to eq []
          end

          it "should ease an ally's Frightened by 1 as the champion's turn ends" do
            Auras.enter(hero, reread(@ally), 'champions-aura', 'ally')
            Pf2e.set_condition(reread(@ally), 'Frightened', 2)

            told = Turns.holder_ending(@encounter, @hero.name, hero, 1)

            expect(frightened(reread(@ally))).to eq 1
            expect(told.map { |one| one['key'] }).to include('pf2e.aura_eased')
          end

          it "should leave an ally outside the aura alone" do
            Pf2e.set_condition(reread(@ally), 'Frightened', 2)
            Turns.holder_ending(@encounter, @hero.name, hero, 1)

            expect(frightened(reread(@ally))).to eq 2
          end

          it "should stop easing once the ally leaves" do
            Auras.enter(hero, reread(@ally), 'champions-aura', 'ally')
            Auras.leave(hero, reread(@ally), 'champions-aura')
            Pf2e.set_condition(reread(@ally), 'Frightened', 2)
            Turns.holder_ending(@encounter, @hero.name, hero, 1)

            expect(frightened(reread(@ally))).to eq 2
          end
        end

        describe "Eternal Bane" do
          before(:each) do
            magic = PF2Magic.create(:character => @hero, :tradition => { 'Cleric' => [ 'divine', 'expert' ] },
                                    :spell_abil => { 'Cleric' => 'Wisdom' })
            @others << magic
            @hero.update(:magic => magic, :pf2_level => 16, :pf2_base_info => { 'charclass' => 'Cleric' })
            with_feats('Eternal Bane')
          end

          it "should surround the cleric with bane, 15 feet, against enemies" do
            bane = aura('eternal-bane').first

            expect(bane['radius']).to eq 15
            expect(bane['effects'].map { |one| [ one['name'], one['affects'] ] }).to eq [ [ 'Spell Effect: Bane', 'enemies' ] ]
          end

          it "should put bane on an enemy who fails their Will save" do
            @dice = 0.05
            done = Auras.enter(hero, reread(@foe), 'eternal-bane', 'enemy')

            expect(ActiveEffects.on(reread(@foe)).map(&:name)).to eq [ 'Spell Effect: Bane' ]
            expect(done.messages.map { |one| one['key'] }).to include('pf2e.aura_save')
          end

          it "should spare an enemy who succeeds" do
            @dice = 1.0
            reread(@foe).update(:pf2_level => 16)
            done = Auras.enter(hero, reread(@foe), 'eternal-bane', 'enemy')

            expect(ActiveEffects.on(reread(@foe))).to eq []
            expect(done.messages.map { |one| one['key'] }).to include('pf2e.aura_save')
          end

          it "should not touch an ally" do
            @dice = 0.05
            Auras.enter(hero, reread(@ally), 'eternal-bane', 'ally')

            expect(ActiveEffects.on(reread(@ally))).to eq []
          end
        end
      end

      # ------------------------------------------------------------------------------
      # In a fight with a goblin warrior, #2

      describe "in a fight" do
        before(:each) do
          Combatants.join(@encounter, @hero.name, 30, :holder => hero)
          run(PF2EncounterAddCmd, 'e/add goblin warrior')
          TurnState.started(standing, 1)
          @skills = []
        end

        after(:each) do
          state = CombatantStates.of(PF2Encounter[@encounter.id], hero)
          ActiveEffects.on(state).each(&:delete) if state
          @skills.each(&:delete)
        end

        def run(cmd_class, text, who = @gm)
          cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
          @encounter = PF2Encounter[@encounter.id]
        end

        def said
          @client.said.join("\n")
        end

        def standing
          CombatantStates.of(PF2Encounter[@encounter.id], hero)
        end

        def goblin
          PF2Encounter[@encounter.id].npcs.to_a.find { |one| one.number == 2 }
        end

        def skill(name, rank)
          @skills << Pf2eSkills.create(:name => name, :character => @hero, :prof_level => rank)
        end

        def attacks_made(*names)
          names.each { |name| TurnState.spend(standing, name, :attack => true) }
        end

        # The multiple attack penalty on a check made for this action.
        def penalty(action, statistic = 'Athletics', options = [])
          check = Check.of(standing, 'skill', statistic, [ "action:#{action}" ] + options)
          Acting.attack_penalty(standing, check, action).sum { |one| one['value'] }
        end

        # Their carried gear changed: the encounter's copy is taken again.
        def rejoin
          run(PF2EncounterResyncCmd, "e/resync #{@hero.name}")
          TurnState.started(standing, 1)
        end

        describe "Agile Maneuvers" do
          it "should leave a maneuver at -5 and -10 without it" do
            attacks_made('Strike')
            expect(penalty('trip')).to eq(-5)

            attacks_made('Strike')
            expect(penalty('trip')).to eq(-10)
          end

          it "should make Disarm, Grapple, Reposition, Shove and Trip -4 and -8" do
            with_feats('Agile Maneuvers')
            attacks_made('Strike')

            %w{disarm grapple reposition shove trip}.each { |action| expect(penalty(action)).to eq(-4) }

            attacks_made('Strike')
            expect(penalty('shove')).to eq(-8)
          end

          it "should leave Escape alone" do
            with_feats('Agile Maneuvers')
            attacks_made('Strike')

            expect(penalty('escape')).to eq(-5)
          end

          it "should make it -3 and -6 with panache and an agile attack" do
            with_feats('Agile Maneuvers')
            ActiveEffects.apply(standing, 'Effect: Panache', :applied_by => @gm.name, :encounter => @encounter)
            attacks_made('Strike')

            expect(penalty('trip', 'Athletics', [ 'item:trait:agile' ])).to eq(-3)
            expect(penalty('trip')).to eq(-4)
          end
        end

        describe "what a maneuver is made with" do
          it "should be unarmed, which is agile, when no weapon in hand has the maneuver's trait" do
            expect(Acting.maneuver_options(standing, { 'weapon_traits' => [ 'trip' ] })).to eq [ 'item:trait:agile' ]
          end

          it "should be the weapon with the maneuver's trait, agile or not" do
            PF2Weapon.create(:name => 'Guisarme', :character => @hero, :equipped => true, :hands => 2, :category => 'martial',
                             :traits => %w{reach trip}, :wp_damage => 'd10', :wp_type => 'melee', :group => 'polearm')
            rejoin

            expect(Acting.maneuver_options(standing, { 'weapon_traits' => [ 'trip' ] })).to eq []
          end
        end

        describe "Slippery Prey" do
          it "should leave Escape at -5 without it" do
            skill('Athletics', 'trained')
            attacks_made('Strike')

            expect(penalty('escape')).to eq(-5)
          end

          it "should make Escape -4 and -8 when trained in the skill rolled" do
            with_feats('Slippery Prey')
            skill('Athletics', 'trained')
            attacks_made('Escape')
            expect(penalty('escape')).to eq(-4)

            attacks_made('Escape')
            expect(penalty('escape')).to eq(-8)
          end

          it "should make it -3 at master, and only in the skill they are master in" do
            with_feats('Slippery Prey')
            skill('Athletics', 'master')
            skill('Acrobatics', 'trained')
            attacks_made('Escape')

            expect(penalty('escape')).to eq(-3)
            expect(penalty('escape', 'Acrobatics')).to eq(-4)
          end

          it "should not count earlier Escapes at legendary" do
            with_feats('Slippery Prey')
            skill('Athletics', 'legendary')
            attacks_made('Escape', 'Escape')

            expect(penalty('escape')).to eq 0
          end

          it "should still count other attacks at legendary" do
            with_feats('Slippery Prey')
            skill('Athletics', 'legendary')
            attacks_made('Strike', 'Escape')

            expect(penalty('escape')).to eq(-3)
          end
        end

        describe "Furious Focus" do
          def swing(words = '')
            @client.failures.clear
            run(PF2EncounterActCmd, "e/act vicious swing=#2#{words}", @hero)
            expect(@client.failures).to eq []
            TurnState.turn(standing)['attacks'].to_i
          end

          def greatsword
            PF2Weapon.create(:name => 'Greatsword', :character => @hero, :equipped => true, :hands => 2, :category => 'martial',
                             :traits => %w{versatile-p}, :wp_damage => 'd12', :wp_damage_type => 'S', :wp_type => 'melee',
                             :group => 'sword')
            rejoin
          end

          it "should count Vicious Swing as two attacks" do
            with_feats('Vicious Swing')

            expect(swing('/fist')).to eq 2
          end

          it "should count it as one in two hands" do
            with_feats('Vicious Swing', 'Furious Focus')
            greatsword

            expect(swing('/greatsword')).to eq 1
          end

          it "should still count it as two in one hand" do
            with_feats('Vicious Swing', 'Furious Focus')

            expect(swing('/fist')).to eq 2
          end
        end

        describe "the concealment flat check" do
          def goblin_is(concealment)
            @encounter.update(:concealment => { '2' => concealment })
          end

          def strike
            @client.said.clear
            @client.failures.clear
            run(PF2EncounterStrikeCmd, 'e/strike fist=#2', @hero)
            expect(@client.failures).to eq []
            said
          end

          # The d20 lands on this face.
          def die(face)
            @dice = face / 20.0
          end

          def rage
            ActiveEffects.apply(standing, 'Effect: Rage', :applied_by => @hero.name, :encounter => @encounter)
          end

          it "should miss a concealed target on a failed DC 5 check without a feat" do
            goblin_is('concealed')
            die(4)

            expect(strike).to include('flat check 4 vs DC 5')
          end

          describe "Blind-Fight" do
            before(:each) { with_feats('Blind-Fight') }

            it "should need no flat check against a concealed target" do
              goblin_is('concealed')
              die(1)

              expect(strike).not_to match(/flat check/i)
            end

            it "should need only DC 5 against a hidden one" do
              goblin_is('hidden')
              die(5)

              expect(strike).to include('vs AC')
              expect(FlatChecks.dc(standing, 'hidden')).to eq 5
            end

            it "should leave an undetected target at DC 11" do
              goblin_is('undetected')
              die(5)

              expect(strike).to include('flat check 5 vs DC 11')
            end

            it "should keep the holder from being off-guard to a hidden attacker, but not an undetected one" do
              hero_at = Combatants.find(@encounter, @hero.name).state
              goblin_at = Combatants.find(@encounter, '#2').state
              scene = Acting::Scene.new(@encounter, goblin_at, hero_at, @gm, true)

              @encounter.update(:concealment => { goblin_at.number.to_s => 'hidden' })
              expect(Acting.unseen_attacker?(scene)).to be false

              @encounter.update(:concealment => { goblin_at.number.to_s => 'undetected' })
              expect(Acting.unseen_attacker?(scene)).to be true
            end
          end

          describe "Supernatural Senses" do
            before(:each) { with_feats('Supernatural Senses') }

            it "should make a concealed target DC 3 while raging" do
              goblin_is('concealed')
              rage
              die(3)

              expect(strike).to include('vs AC')
              expect(FlatChecks.dc(standing, 'concealed')).to eq 3
            end

            it "should make a hidden target DC 9 while raging" do
              goblin_is('hidden')
              rage
              die(9)

              expect(strike).to include('vs AC')
              expect(FlatChecks.dc(standing, 'hidden')).to eq 9
            end

            it "should do nothing without a rage" do
              goblin_is('concealed')
              die(3)

              expect(strike).to include('flat check 3 vs DC 5')
            end
          end
        end

        describe "what fires a feat" do
          def act(text)
            @client.said.clear
            @client.failures.clear
            run(PF2EncounterActCmd, "e/act #{text}", @hero)
            expect(@client.failures).to eq []
            said
          end

          def with_features(*names)
            @hero.update(:pf2_features => { 'charclass_features' => names, 'archetype_features' => [] })
          end

          def goblin_hp
            Actors.of(goblin).hit_point_counts.first.to_i
          end

          def goblin_conditions
            goblin.pf2_conditions || {}
          end

          def effects_on_hero
            ActiveEffects.on(standing).map(&:name)
          end

          describe "Inviolable" do
            def goblin_strikes
              @client.failures.clear
              run(PF2EncounterAsCmd, "e/as #2=strike #{@hero.name}")
              expect(@client.failures).to eq []
            end

            it "should deal 3d6 spirit damage to whoever hits the cleric" do
              with_feats('Inviolable')
              @dice = 0.95
              before = goblin_hp
              goblin_strikes

              expect(goblin_hp).to be < before
              expect(said).to include('Inviolable')
            end

            it "should do nothing on a miss, or without the feat" do
              @dice = 0.95
              before = goblin_hp
              goblin_strikes
              expect(goblin_hp).to eq before

              with_feats('Inviolable')
              @dice = 0.05
              goblin_strikes
              expect(goblin_hp).to eq before
            end
          end

          describe "Disorienting Opening" do
            it "should leave a creature hit by a Reactive Strike off-guard until the start of the holder's next turn" do
              with_feats('Reactive Strike', 'Disorienting Opening')
              @dice = 0.95
              act('reactive strike=#2/fist')

              expect(goblin_conditions).to have_key('Off-Guard')
              expect(goblin_conditions['Off-Guard']['expires']).to include('event' => 'turn-start')
            end

            it "should not on a miss, or on another Strike" do
              with_feats('Reactive Strike', 'Disorienting Opening')
              @dice = 0.05
              act('reactive strike=#2/fist')
              expect(goblin_conditions).not_to have_key('Off-Guard')

              @dice = 0.95
              run(PF2EncounterStrikeCmd, 'e/strike fist=#2', @hero)
              expect(goblin_conditions).not_to have_key('Off-Guard')
            end
          end

          describe "Brilliant Flash" do
            it "should leave the attacker off-guard after Flash of Grandeur" do
              with_features('Flash of Grandeur')
              with_feats('Brilliant Flash')
              act('flash of grandeur=#2')

              expect(goblin_conditions).to have_key('Off-Guard')
            end

            it "should do nothing without the feat" do
              with_features('Flash of Grandeur')
              act('flash of grandeur=#2')

              expect(goblin_conditions).not_to have_key('Off-Guard')
            end
          end

          describe "Swift Retribution" do
            it "should quicken the champion until the end of their next turn after their champion's reaction" do
              with_features('Retributive Strike')
              with_feats('Swift Retribution')
              act('retributive strike=#2')

              held = standing.pf2_conditions['Quickened']
              expect(held).not_to be_nil
              expect(held['expires']).to include('event' => 'turn-end')
            end

            it "should not after any other reaction" do
              with_feats('Swift Retribution', 'Reactive Strike')
              act('reactive strike=#2/fist')

              expect(standing.pf2_conditions || {}).not_to have_key('Quickened')
            end
          end

          describe "Finishing Follow-Through" do
            it "should give panache when a finisher drops its target" do
              with_features('Basic Finisher')
              with_feats('Finishing Follow-Through')
              @dice = 0.95
              act('basic finisher=#2/fist')

              expect(goblin_hp).to be <= 0
              expect(effects_on_hero).to include('Effect: Panache')
            end

            it "should not when the target is left standing" do
              with_features('Basic Finisher')
              with_feats('Finishing Follow-Through')
              @dice = 0.05
              act('basic finisher=#2/fist')

              expect(effects_on_hero).not_to include('Effect: Panache')
            end
          end

          describe "Immortal Techniques" do
            it "should give 20 temporary Hit Points for the first monk stance each round, and only the first" do
              with_feats('Immortal Techniques', 'Mountain Stance', 'Crane Stance')
              act('mountain stance')

              expect(effects_on_hero).to include('Effect: Immortal Techniques')
              expect(Acting.temp_hp_of(standing)).to eq 20

              ActiveEffects.named_on(standing, 'Effect: Immortal Techniques').each { |one| ActiveEffects.remove(standing, one) }
              act('crane stance')

              expect(effects_on_hero).not_to include('Effect: Immortal Techniques')
            end
          end

          describe "Rage's temporary Hit Points, and Second Wind" do
            before(:each) { with_features('Rage') }

            def rage(words = '')
              act("rage#{words}")
            end

            def end_rage
              ActiveEffects.named_on(standing, 'Effect: Rage').each { |one| ActiveEffects.remove(standing, one) }
            end

            def temp_hp
              Acting.temp_hp_of(standing)
            end

            it "should leave a barbarian unable to gain them again for a minute once a rage ends" do
              rage
              expect(temp_hp).to be > 0
              end_rage

              expect(effects_on_hero).to include('Effect: Rage Temporary Hit Points Immunity')

              rage
              expect(temp_hp).to eq 0
            end

            it "should let Second Wind gain them anyway, and leave them fatigued once that rage ends" do
              with_feats('Second Wind')
              rage
              end_rage
              rage('/second-wind')

              expect(temp_hp).to be > 0
              expect(effects_on_hero).not_to include('Effect: Rage Temporary Hit Points Immunity')

              end_rage
              expect(standing.pf2_conditions || {}).to have_key('Fatigued')
            end

            it "should not without the word" do
              with_feats('Second Wind')
              rage
              end_rage
              rage

              expect(temp_hp).to eq 0
            end
          end
        end

        describe "a frequency of an hour" do
          it "should start over as the encounter ends" do
            expect(TurnState.period('PT1H')).to eq 'encounter'
            expect(TurnState.period('day')).to eq 'rest'
          end
        end
      end
    end
  end
end
