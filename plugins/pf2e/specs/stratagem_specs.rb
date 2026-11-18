require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Devise a Stratagem through the real encounter: the d20 rolled ahead, the creature it marks, and the
    # Strike that uses the roll with Intelligence and Strategic Strike's precision damage.
    #
    # Dice are loaded: `@dice` is what every die shows, as a fraction of its faces.
    describe "devising a stratagem", :dbtest => true do

      class StratagemClient
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

        @client = StratagemClient.new
        @room = Room.create(:name => "Study#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Sleuth#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @hero, :armor_prof => { 'unarmored' => 'trained' }, :class_dc => 'trained',
                                    :weapon_prof => { 'simple' => 'trained', 'martial' => 'trained', 'unarmed' => 'trained' },
                                    :unarmed_attacks => {})
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 8)
        @hero.update(:combat => @combat, :hp => @hp, :pf2_level => 5, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_roll_options => {}, :pf2_daily_choices => {},
                     :pf2_base_info => { 'charclass' => 'Investigator', 'specialize' => 'Forensic Medicine Methodology' },
                     :pf2_features => { 'charclass_features' => [ 'Devise a Stratagem', 'Strategic Strike' ],
                                        'archetype_features' => [] })
        # Intelligence 18 (+4) over Strength and Dexterity 14 (+2): a stratagem's Strike is 2 better.
        @abilities = Pf2e::ABILITIES.map do |name|
          Pf2eAbilities.create(:character => @hero, :name => name, :base_val => name == 'Intelligence' ? 18 : 14)
        end
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => @gm.name, :round => 1, :is_active => true)
        @hero.encounters.add @encounter
        @encounter.characters.add @hero
        Combatants.join(@encounter, @hero.name, 30, :holder => @hero)

        @dagger = Pf2egear.create_item(state, 'weapons', 'Dagger', 1, Global.read_config('pf2e_weapons', 'Dagger'))
        @dagger.update(:equipped => true)
        @longsword = Pf2egear.create_item(state, 'weapons', 'Longsword', 1, Global.read_config('pf2e_weapons', 'Longsword'))
        @longsword.update(:equipped => true)

        @dice = 0.5
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * @dice).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow(Scenes).to receive(:add_to_scene)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Login).to receive(:notify)
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)

        @rolls = []
        allow(Resolve).to receive(:roll).and_wrap_original do |original, *args, **kwargs|
          original.call(*args, **kwargs).tap { |rolled| @rolls << rolled }
        end

        run(PF2EncounterAddCmd, 'e/add 1 goblin warrior')
      end

      after(:each) do
        encounter = PF2Encounter[@encounter.id]
        encounter&.npcs&.each(&:delete)
        (@abilities + [ @encounter, @hp, @combat, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def run(cmd_class, text, who = @gm)
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
        @encounter = PF2Encounter[@encounter.id]
      end

      def state
        CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id])
      end

      def stratagem
        ActiveEffects.named_on(state, Stratagem::EFFECT).first
      end

      def goblin
        Combatants.find(PF2Encounter[@encounter.id], '#2').state
      end

      def attack(name)
        Actors.of(state).attacks.find { |names, _attack| names.include?(name) }&.last
      end

      # The attack bonus with the weapon as it stands, with no stratagem in play.
      def plain_bonus(name)
        Check.of(state, 'attack', attack(name), []).total.to_i
      end

      def devise(roll = 0.7)
        @dice = roll
        run(PF2EncounterActCmd, 'e/act devise a stratagem=#2', @hero)
        @dice = 0.5
      end

      describe "the action" do
        it "should roll the d20 ahead and keep it, marking the creature" do
          devise(0.7)

          expect(@client.failures).to eq []
          expect(stratagem.badge).to eq 14
          expect(stratagem.mark).to eq('label' => goblin.label, 'slug' => Stratagem::SLUG)
          expect(stratagem.answers).to eq [ 'attack' ]
          expect(@client.said.join).to include t('pf2e.stratagem_rolled', :actor => @hero.name, :target => goblin.label,
                                                                          :roll => 14, :cost => Actions.cost(Stratagem::NAME))
        end

        it "should spend an action" do
          devise

          expect(TurnState.turn(state)['actions'].to_i).to eq 1
        end

        it "should need a creature to devise one against" do
          run(PF2EncounterActCmd, 'e/act devise a stratagem', @hero)

          expect(@client.failures).to eq [ t('pf2e.stratagem_none', :actor => @hero.name) ]
        end
      end

      describe "an attack stratagem" do
        it "should use the roll in place of the d20, with Intelligence, on a finesse weapon" do
          bonus = plain_bonus('Dagger')
          devise(0.7)
          run(PF2EncounterStrikeCmd, 'e/strike dagger=#2', @hero)

          rolled = @rolls.last
          expect(rolled['substitution']['slug']).to eq Stratagem::SLUG
          expect(rolled['modifier']).to eq bonus + 2
          expect(rolled['total']).to eq 14 + bonus + 2
        end

        it "should be spent on the first Strike against the creature" do
          devise(0.7)
          run(PF2EncounterStrikeCmd, 'e/strike dagger=#2', @hero)
          run(PF2EncounterStrikeCmd, 'e/strike dagger=#2', @hero)

          expect(stratagem).to be_nil
          expect(@rolls.last['substitution']).to be_nil
        end

        it "should add Strategic Strike's precision dice to the hit" do
          options = []
          allow(Damage).to receive(:of).and_wrap_original do |original, char, struck, given = []|
            options = given
            original.call(char, struck, given)
          end

          devise(0.95)
          run(PF2EncounterStrikeCmd, 'e/strike dagger=#2', @hero)

          expect(options).to include "check:substitution:#{Stratagem::SLUG}"
          rows = Actors.of(state).strike_damage(attack('Dagger'), Struct.new(:options).new(options), false)
          expect(rows.any? { |row| row['category'].to_s == 'precision' }).to be true
        end

        it "should roll as usual with a weapon that can't use it, and be lost" do
          bonus = plain_bonus('Longsword')
          devise(0.7)
          run(PF2EncounterStrikeCmd, 'e/strike longsword=#2', @hero)

          expect(@rolls.last['substitution']).to be_nil
          expect(@rolls.last['modifier']).to eq bonus
          expect(stratagem).to be_nil
          expect(@client.said.join).to include t('pf2e.stratagem_lost', :actor => @hero.name, :weapon => 'Longsword')
        end

        it "should not use Intelligence for someone who isn't an investigator" do
          @hero.update(:pf2_base_info => { 'charclass' => 'Rogue', 'specialize' => 'Thief' },
                       :pf2_actions => { 'actions' => [ Stratagem::NAME ], 'reactions' => [] })
          bonus = plain_bonus('Dagger')
          devise(0.7)
          run(PF2EncounterStrikeCmd, 'e/strike dagger=#2', @hero)

          expect(@rolls.last['substitution']['slug']).to eq Stratagem::SLUG
          expect(@rolls.last['modifier']).to eq bonus
        end
      end

      describe "choosing another stratagem" do
        it "should switch to a skill stratagem without spending an action" do
          devise
          run(PF2EncounterActCmd, 'e/act devise a stratagem/skill', @hero)

          expect(@client.failures).to eq []
          expect(stratagem.answers).to eq [ 'skill' ]
          expect(TurnState.turn(state)['actions'].to_i).to eq 1
        end

        it "should refuse a Strike at the creature with a skill stratagem" do
          devise
          run(PF2EncounterActCmd, 'e/act devise a stratagem/skill', @hero)
          run(PF2EncounterStrikeCmd, 'e/strike dagger=#2', @hero)

          expect(@client.failures).to eq [ t('pf2e.stratagem_no_strike', :actor => @hero.name, :target => goblin.label,
                                                                         :kind => 'skill') ]
        end

        it "should refuse a defensive stratagem without the feat" do
          devise
          run(PF2EncounterActCmd, 'e/act devise a stratagem/defensive', @hero)

          expect(@client.failures).to eq [ t('pf2e.stratagem_no_defensive', :actor => @hero.name) ]
          expect(stratagem.answers).to eq [ 'attack' ]
        end

        it "should ask which, given none" do
          devise
          run(PF2EncounterActCmd, 'e/act devise a stratagem', @hero)

          expect(@client.failures).to eq [ t('pf2e.stratagem_which', :kinds => 'attack, skill') ]
        end

        it "should give a defensive stratagem's bonus to AC against the marked creature" do
          @hero.update(:pf2_feats => { 'charclass' => [ 'Defensive Stratagem' ] })
          devise
          run(PF2EncounterActCmd, 'e/act devise a stratagem/defensive', @hero)

          plain = Resolve.defence(state, 'ac')['dc']
          marked = Resolve.defence(state, 'ac', :options => Marks.seen(state, goblin, 'origin'))['dc']

          expect(@client.failures).to eq []
          expect(marked).to eq plain + 1
        end
      end
    end
  end
end
