require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What an alchemist's research field does, through the real encounter: their vials, their bombs, and
    # what their field adds to them at 5th, 11th and 13th level.
    #
    # Dice are loaded: `@dice` is what every die shows, as a fraction of its faces.
    describe "research fields", :dbtest => true do

      class FieldClient
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

        @client = FieldClient.new
        @room = Room.create(:name => "Lab#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Fizz#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @hero, :armor_prof => { 'unarmored' => 'trained' }, :class_dc => 'expert',
                                    :weapon_prof => { 'simple' => 'trained', 'martial' => 'trained', 'bomb' => 'expert', 'unarmed' => 'trained' },
                                    :unarmed_attacks => {})
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 8)
        @hero.update(:combat => @combat, :hp => @hp, :pf2_level => 13, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_roll_options => {}, :pf2_daily_choices => {},
                     :pf2_base_info => { 'charclass' => 'Alchemist', 'specialize' => 'Bomber' },
                     :pf2_features => { 'charclass_features' => [ 'Advanced Alchemy', 'Versatile Vials', 'Field Discovery',
                                                                  'Advanced Vials', 'Greater Field Discovery' ],
                                        'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map do |name|
          Pf2eAbilities.create(:character => @hero, :name => name, :base_val => name == 'Intelligence' ? 18 : 14)
        end
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

      def vial
        Actors.of(state).attacks.find { |names, _attack| names.include?('Versatile Vial (Greater)') }&.last
      end

      describe "a Bomber" do
        it "should throw vials Foundry's rules know by their slug" do
          expect(vial['slug']).to eq 'versatile-vial'
          expect(Pf2eCombat.attack_options(vial, state)).to include 'item:slug:versatile-vial'
        end

        it "should splash for their Intelligence modifier with Field Discovery, where that is higher" do
          expect(vial['splash']).to eq 4
        end

        it "should deal the damage type their field vials are set to" do
          expect(vial['damage_type']).to eq 'acid'

          RollOptions.set(Character[@hero.id], 'bomber-field-vials', 'fire')

          expect(vial['damage_type']).to eq 'fire'
        end

        it "should make the day's vials of the material they chose, with Advanced Vials" do
          run(PF2PrepareDailyCmd, 'prepare/vialmaterial cold iron', @hero)

          expect(@client.failures).to eq []
          expect(vial['materials']).to include 'Cold Iron'
        end

        it "should not offer the material to an alchemist of another field" do
          @hero.update(:pf2_base_info => { 'charclass' => 'Alchemist', 'specialize' => 'Chirurgeon' })

          expect(DailyChoices.for_switch(Character[@hero.id], 'vialmaterial')).to be_nil
        end
      end

      describe "a Toxicologist" do
        before(:each) do
          @hero.update(:pf2_base_info => { 'charclass' => 'Alchemist', 'specialize' => 'Toxicologist' })
          @dagger = Pf2egear.create_item(state, 'weapons', 'Dagger', 1, Global.read_config('pf2e_weapons', 'Dagger'))
          @dagger.update(:equipped => true)
          run(PF2EncounterAddCmd, 'e/add 2 goblin warrior')
        end

        def dagger
          PF2Weapon[@dagger.id]
        end

        it "should resist poison by half their level, with Field Discovery" do
          resisted = Array(IWR.for(state)['resistance']).find { |one| Array(one['type']).include?('poison') }

          expect(resisted['value']).to eq 6
        end

        it "should apply a versatile vial to a weapon in one action, with its splash as persistent poison" do
          applied = WeaponPoison.apply!(state, 'dagger', 'versatile vial')

          expect(applied.state['cost']).to eq 1
          expect(dagger.poison).to include('damage' => '3d6 poison', 'persistent' => 3, 'lasts' => 'turn_end')
        end

        it "should let a field vial on a weapon go inert at the end of their turn" do
          WeaponPoison.apply!(state, 'dagger', 'versatile vial')
          Turns.turn_ended(PF2Encounter[@encounter.id], @hero.name, 1)

          expect(dagger.poison).to eq({})
        end

        it "should add a field vial's damage to the Strike that hits" do
          WeaponPoison.apply!(state, 'dagger', 'versatile vial')
          @dice = 0.95
          run(PF2EncounterStrikeCmd, 'e/strike #2=dagger', @hero)

          expect(@client.said.join).to include t('pf2e.poison_exposed', :target => 'Goblin Warrior #2', :poison => 'Versatile Vial (Greater)')
        end

        it "should turn their poison's damage to acid for a creature immune to poison" do
          info = Global.read_config('pf2e_consumables', 'Giant Centipede Venom')
          acid = WeaponPoison.as_acid(Afflictions.read('Giant Centipede Venom', info['affliction'], info['traits']))

          expect(acid['traits']).to_not include 'poison'
          expect(acid['stages'].flat_map { |stage| stage['damage'].map(&:last) }.uniq).to eq [ 'acid' ]
        end

        # Greater Field Discovery: the attacker names who the spray reaches, since the game can't see who
        # stands next to whom.
        describe "spraying the poison" do
          before(:each) do
            @caught = []
            allow(Afflictions).to receive(:catch) do |_scene, target, affliction, _out|
              @caught << target.label
              Afflictions.keep(target.holder, affliction.merge('stage' => 1))
            end

            venom = Pf2egear.create_item(state, 'consumables', 'Giant Centipede Venom', 1,
                                         Global.read_config('pf2e_consumables', 'Giant Centipede Venom'))
            venom.update(:granted_by => Alchemy::QUICK)
            WeaponPoison.apply!(state, 'dagger', 'giant centipede venom')
            @dice = 0.95
            run(PF2EncounterStrikeCmd, 'e/strike #2=dagger', @hero)
          end

          it "should offer the spray when the target fails its first save" do
            expect(@client.said.join).to include 'encounter/spray'
          end

          it "should expose the creature named to the same poison, once" do
            run(PF2EncounterSprayCmd, 'e/spray #3', @hero)
            run(PF2EncounterSprayCmd, 'e/spray #3', @hero)

            expect(@caught).to eq [ 'Goblin Warrior #2', 'Goblin Warrior #3' ]
            expect(@client.failures).to eq [ t('pf2e.spray_none') ]
          end
        end
      end

      describe "a Chirurgeon" do
        before(:each) do
          @hero.update(:pf2_base_info => { 'charclass' => 'Alchemist', 'specialize' => 'Chirurgeon' })
          @skills = [ Pf2eSkills.create(:character => @hero, :name => 'Medicine', :prof_level => 'untrained'),
                      Pf2eSkills.create(:character => @hero, :name => 'Crafting', :prof_level => 'master') ]
        end

        after(:each) { @skills.each(&:delete) }

        def number_of(item_name)
          Pf2egear::Inventory.held(state, 'consumables').index { |one| one.name == item_name }
        end

        def use(item_name)
          run(Pf2egear::PF2EncounterUseCmd, "e/use consumables=#{number_of(item_name)}", @hero)
        end

        def current_hp
          Pf2eHP.get_current_hp(state)
        end

        it "should use their Crafting for Medicine, in checks and prerequisites" do
          expect(ResearchField.rolling_prof(state, 'Medicine')).to eq 'master'
          expect(Pf2eSkills.get_skill_bonus(state, 'Medicine')).to eq Pf2eSkills.get_skill_bonus(state, 'Crafting')
          expect(DraftSheet.of(Character[@hero.id]).skill_prof('Medicine')).to eq 'master'
        end

        it "should heal by a versatile vial's initial damage when they drink one" do
          Pf2eHP.modify_damage(state, 20, false, true)
          before = current_hp

          use('Versatile Vial (Greater)')

          expect(@client.failures).to eq []
          expect(current_hp).to eq before + 9
        end

        it "should not heal again within 10 minutes, the vial being coagulant" do
          Pf2eHP.modify_damage(state, 20, false, true)
          use('Versatile Vial (Greater)')
          before = current_hp

          use('Versatile Vial (Greater)')

          expect(current_hp).to eq before
          expect(@client.said.join).to include t('pf2e.coagulant_blocked', :target => state.name, :item => 'Versatile Vial (Greater)')
        end

        it "should heal someone at half their Hit Points or fewer regardless, with Advanced Vials" do
          use('Versatile Vial (Greater)')
          Pf2eHP.modify_damage(state, Pf2eHP.get_max_hp(state) - 5, false, true)
          before = current_hp

          use('Versatile Vial (Greater)')

          expect(current_hp).to eq before + 9
        end

        def quick_elixir
          item = Pf2egear.create_item(state, 'consumables', 'Elixir of Life (Minor)', 1,
                                      Global.read_config('pf2e_consumables', 'Elixir of Life (Minor)'))
          item.update(:granted_by => Alchemy::QUICK, :expires => 'turn')
        end

        it "should give temporary Hit Points with the healing elixirs they make, with Field Discovery" do
          quick_elixir
          use('Elixir of Life (Minor)')

          expect(state.hp.temp_hp).to eq 4
        end

        it "should heal the most an elixir of life can from Quick Alchemy, with Greater Field Discovery" do
          Pf2eHP.modify_damage(state, 20, false, true)
          quick_elixir
          before = current_hp

          use('Elixir of Life (Minor)')

          expect(current_hp).to eq before + 6
        end
      end

      # Who else a bomb's splash reaches, named by the thrower, since the game has no positions.
      describe "naming who the splash reaches" do
        before(:each) { run(PF2EncounterAddCmd, 'e/add 2 goblin warrior') }

        def hp(ref)
          Combatants.find(PF2Encounter[@encounter.id], ref).state.holder.hp_left.to_i
        end

        it "should splash each creature named, on a hit" do
          before = hp('#3')
          @dice = 0.95
          run(PF2EncounterStrikeCmd, 'e/strike #2=versatile vial/splash #3', @hero)

          expect(@client.failures).to eq []
          expect(hp('#3')).to eq before - 4
        end

        # A natural 1 is a miss for this bomber, whose bonus is too high to miss critically.
        it "should splash those named on a miss too" do
          before = hp('#3')
          @dice = 0.01
          run(PF2EncounterStrikeCmd, 'e/strike #2=versatile vial/splash #3', @hero)

          expect(hp('#3')).to eq before - 4
        end

        it "should say so when nobody by that name is there" do
          @dice = 0.95
          run(PF2EncounterStrikeCmd, 'e/strike #2=versatile vial/splash nobody', @hero)

          expect(@client.said.join).to include t('pf2e.splash_not_found', :name => 'nobody')
        end
      end
    end
  end
end
