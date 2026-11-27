require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Feats whose rule changes the other creature in an attack, for that attack only: Foundry's
    # `EphemeralEffect`. The feat holder's target is off-guard, or its cover counts for less; or, when the
    # holder is attacked, the attacker must pass a flat check, or a miss gives the holder panache.
    describe "ephemeral effects", :dbtest => true do

      class EphemeralClient
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

        @client = EphemeralClient.new
        @room = Room.create(:name => "Arena#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Aria#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @hero, :armor_prof => { 'unarmored' => 'trained' },
                                    :weapon_prof => { 'unarmed' => 'trained' },
                                    :unarmed_attacks => { 'Fist' => { 'damage' => 'd4', 'damage_type' => 'B',
                                                                      'traits' => %w{agile finesse nonlethal unarmed} } })
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 10)
        @hero.update(:combat => @combat, :hp => @hp, :pf2_level => 1, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Fighter' },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => @gm.name, :round => 1, :is_active => true)
        @hero.encounters.add @encounter
        @encounter.characters.add @hero
        Combatants.join(@encounter, @hero.name, 30, :holder => @hero)

        @dice = 0.5
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * @dice).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow(Scenes).to receive(:add_to_scene)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Login).to receive(:notify)
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow_any_instance_of(Character).to receive(:has_permission?).and_call_original
        allow_any_instance_of(Character).to receive(:has_permission?).with('kill_pc') { |char, _| char.name == @gm.name }

        run(PF2EncounterAddCmd, 'e/add goblin warrior')
      end

      after(:each) do
        encounter = PF2Encounter[@encounter.id]
        encounter&.npcs&.each(&:delete)
        state = CombatantStates.of(encounter, Character[@hero.id]) if encounter
        ActiveEffects.on(state).each(&:delete) if state
        (@abilities + [ @encounter, @hp, @combat, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def run(cmd_class, text, who = @gm)
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
        @encounter = PF2Encounter[@encounter.id]
      end

      def said
        @client.said.join("\n")
      end

      def goblin
        @encounter.npcs.to_a.find { |one| one.number == 2 }
      end

      def standing
        CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id])
      end

      def with_feats(*names)
        @hero.update(:pf2_feats => { 'charclass' => names })
      end

      # The AC the hero's Fist Strike at the goblin was against, as the room was told it.
      def struck_ac(words = '')
        @client.said.clear
        @client.failures.clear
        run(PF2EncounterStrikeCmd, words.empty? ? "e/strike fist=#2" : "e/strike fist=#2/#{words}", @hero)
        said[/vs AC (\d+)/, 1]&.to_i
      end

      # The goblin's Strike at the hero, which must not be refused: its first, a melee one, or the weapon named.
      def goblin_strikes(weapon = nil)
        @client.failures.clear
        run(PF2EncounterAsCmd, weapon ? "e/as #2=strike #{weapon}=#{@hero.name}" : "e/as #2=strike #{@hero.name}")
        expect(@client.failures).to eq []
      end

      def put_on(name, holder = standing)
        ActiveEffects.apply(holder, name, :applied_by => @gm.name, :encounter => @encounter)
      end

      describe "Dread Striker" do
        it "should make a frightened target off-guard to the holder's Strikes" do
          Pf2e.set_condition(goblin, 'Frightened', 1)
          frightened = struck_ac

          with_feats('Dread Striker')

          expect(struck_ac).to eq frightened - 2
        end

        it "should leave a target that is not frightened alone" do
          plain = struck_ac
          with_feats('Dread Striker')

          expect(struck_ac).to eq plain
        end
      end

      describe "Tumble Behind" do
        it "should make the target off-guard when the holder says so" do
          plain = struck_ac
          with_feats('Tumble Behind (Rogue)')

          expect(struck_ac('tumble-behind')).to eq plain - 2
        end

        it "should refuse the word from someone without the feat" do
          struck_ac('tumble-behind')

          expect(@client.failures.join).to include(I18n.t('pf2e.ephemeral_word_not_yours', :word => 'tumble-behind',
                                                           :actor => @hero.name))
        end
      end

      describe "Callow May" do
        it "should make the target off-guard in the first round only" do
          plain = struck_ac
          with_feats('Callow May')

          expect(struck_ac('callow-may')).to eq plain - 2

          @encounter.update(:round => 2)
          expect(struck_ac('callow-may')).to eq plain
        end
      end

      describe "cover and concealment the holder's attack ignores" do
        def scene_for
          Acting::Scene.new(@encounter, Combatants.find(@encounter, @hero.name).state, Combatants.find(@encounter, '#2').state, @hero, true)
        end

        BOW = %w{ranged-attack-roll ranged-strike-attack-roll strike-attack-roll}.freeze
        BOMB = %w{alchemical-bomb-base-attack-roll ranged-attack-roll strike-attack-roll}.freeze
        AIMED = { 'options' => [ 'hunters-aim', 'target:mark:hunted-prey' ], 'words' => [] }.freeze

        # Cover's bonus to AC as the attack faces it, or nil for none.
        def cover(said, domains, level)
          Ephemeral.cover(scene_for, said, domains, Resolve.cover_modifier(level))&.fetch('value')
        end

        it "should ignore lesser cover and concealment on Hunter's Aim at hunted prey, and nothing more" do
          with_feats("Hunter's Aim")

          expect(cover(AIMED, BOW, 'lesser')).to be_nil
          expect(cover(AIMED, BOW, 'standard')).to eq 2
          expect(Ephemeral.concealment(scene_for, AIMED, BOW, 'concealed')).to be_nil
          expect(Ephemeral.concealment(scene_for, AIMED, BOW, 'hidden')).to eq 'hidden'
        end

        it "should leave cover alone on a Strike that isn't Hunter's Aim" do
          with_feats("Hunter's Aim")

          expect(cover({ 'options' => [], 'words' => [] }, BOW, 'lesser')).to eq 1
        end

        it "should take 1 from cover's bonus against an Uncanny Bombs bomb, and ignore concealment" do
          with_feats('Uncanny Bombs')
          none = { 'options' => [], 'words' => [] }

          expect(cover(none, BOMB, 'greater')).to eq 3
          expect(cover(none, BOMB, 'standard')).to eq 1
          expect(cover(none, BOMB, 'lesser')).to be_nil
          expect(Ephemeral.concealment(scene_for, none, BOMB, 'concealed')).to be_nil
          expect(cover(none, BOW, 'standard')).to eq 2
        end
      end

      describe "Spirits' Interference" do
        it "should make a ranged attack at the raging holder miss on a failed DC 5 flat check" do
          with_feats("Spirits' Interference")
          put_on('Effect: Rage')
          @dice = 0.1

          goblin_strikes('shortbow')

          expect(said).to include(I18n.t('pf2e.ephemeral_flat_miss', :actor => 'Goblin Warrior #2', :target => @hero.name,
                                         :effect => "Spirits' Interference", :die => 2, :dc => 5))
        end

        it "should ask nothing of a melee Strike, or while they aren't raging" do
          with_feats("Spirits' Interference")
          @dice = 0.1

          goblin_strikes('shortbow')
          put_on('Effect: Rage')
          goblin_strikes

          expect(said).not_to include("Spirits' Interference")
        end
      end

      describe "Flashy Dodge" do
        it "should give +2 AC against the next attack, and panache when it misses" do
          with_feats('Flashy Dodge')
          @dice = 0.25

          run(PF2EncounterActCmd, 'e/act flashy dodge', @hero)
          expect(ActiveEffects.named_on(standing, 'Effect: Flashy Dodge')).not_to be_empty

          goblin_strikes

          expect(ActiveEffects.named_on(standing, 'Effect: Flashy Dodge')).to be_empty
          expect(ActiveEffects.named_on(standing, 'Effect: Panache (Temporary)')).not_to be_empty
        end

        it "should give no panache when the attack hits" do
          with_feats('Flashy Dodge')
          run(PF2EncounterActCmd, 'e/act flashy dodge', @hero)
          @dice = 0.9

          goblin_strikes

          expect(ActiveEffects.named_on(standing, 'Effect: Flashy Dodge')).to be_empty
          expect(ActiveEffects.named_on(standing, 'Effect: Panache (Temporary)')).to be_empty
        end
      end

      describe "Elegant Buckler" do
        before(:each) do
          with_feats('Elegant Buckler')
          RollOptions.set(Character[@hero.id], 'elegant-buckler', true)
          put_on('Effect: Raise a Shield')
        end

        it "should give panache on a critical miss while the buckler is raised" do
          @dice = 0.05

          goblin_strikes

          expect(ActiveEffects.named_on(standing, 'Effect: Panache (Temporary)')).not_to be_empty
        end

        it "should give none on a plain miss" do
          @dice = 0.3

          goblin_strikes

          expect(said).to match(/miss|failure/i)
          expect(ActiveEffects.named_on(standing, 'Effect: Panache (Temporary)')).to be_empty
        end
      end
    end
  end
end
