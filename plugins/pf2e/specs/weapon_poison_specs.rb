require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An injury poison on a weapon: applied with encounter/poison, it waits for the first Strike with the
    # weapon. A hit dealing piercing or slashing damage exposes the target, a miss keeps it for the next try,
    # and a critical miss wastes it.
    #
    # Dice are loaded: `@dice` is what every die shows, as a fraction of its faces.
    describe "poison on a weapon", :dbtest => true do

      class PoisonClient
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

        @client = PoisonClient.new
        @room = Room.create(:name => "Alley#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Vex#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @hero, :armor_prof => { 'unarmored' => 'trained' },
                                    :weapon_prof => { 'simple' => 'trained', 'unarmed' => 'trained' }, :unarmed_attacks => {})
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 8)
        @hero.update(:combat => @combat, :hp => @hp, :pf2_level => 4, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Rogue' },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => @gm.name, :round => 1, :is_active => true)
        @hero.encounters.add @encounter
        @encounter.characters.add @hero
        Combatants.join(@encounter, @hero.name, 30, :holder => @hero)

        @dagger = Pf2egear.create_item(state, 'weapons', 'Dagger', 1, Global.read_config('pf2e_weapons', 'Dagger'))
        @dagger.update(:equipped => true)
        @venom = Pf2egear.create_item(state, 'consumables', 'Giant Centipede Venom', 1,
                                      Global.read_config('pf2e_consumables', 'Giant Centipede Venom'))

        @dice = 0.5
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * @dice).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow(Scenes).to receive(:add_to_scene)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Login).to receive(:notify)
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)

        @exposed = []
        allow(Afflictions).to receive(:catch) { |_scene, target, affliction, _out| @exposed << [ target.label, affliction['name'], affliction['dc'] ] }

        run(PF2EncounterAddCmd, 'e/add goblin warrior')
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

      def dagger
        PF2Weapon[@dagger.id]
      end

      def poison(text = 'e/poison dagger=centipede')
        run(PF2EncounterPoisonCmd, text, @hero)
      end

      def strike
        run(PF2EncounterStrikeCmd, 'e/strike dagger=#2', @hero)
      end

      describe "applying one" do
        it "should put the poison on the weapon and use the dose up" do
          poison

          expect(@client.failures).to eq []
          expect(dagger.poison['name']).to eq 'Giant Centipede Venom'
          expect(PF2Consumable[@venom.id]).to be_nil
        end

        it "should take the poison's own actions, or one with Poison Weapon" do
          info = Global.read_config('pf2e_consumables', 'Giant Centipede Venom')

          expect(WeaponPoison.cost(state, info)).to eq 2

          @hero.update(:pf2_feats => { 'charclass' => [ 'Poison Weapon' ] })

          expect(WeaponPoison.cost(state, info)).to eq 1
        end

        it "should refuse a weapon already poisoned, one not wielded, and a poison not carried" do
          poison
          Pf2egear.create_item(state, 'consumables', 'Black Adder Venom', 1, Global.read_config('pf2e_consumables', 'Black Adder Venom'))
          poison('e/poison dagger=black adder')

          expect(@client.failures.last).to eq t('pf2e.poison_already', :weapon => 'Dagger', :poison => 'Giant Centipede Venom')

          dagger.update(:equipped => false, :poison => {})
          poison('e/poison dagger=black adder')

          expect(@client.failures.last).to eq t('pf2e.poison_no_weapon', :weapon => 'dagger')

          dagger.update(:equipped => true)
          poison('e/poison dagger=wyvern')

          expect(@client.failures.last).to eq t('pf2e.poison_none', :poison => 'wyvern')
        end
      end

      describe "the Strike it waits for" do
        before(:each) { poison }

        it "should expose the target to it on a hit" do
          @dice = 0.95
          strike

          expect(@exposed).to eq [ [ 'Goblin Warrior #2', 'Giant Centipede Venom', 17 ] ]
          expect(dagger.poison).to eq({})
        end

        it "should stay on the weapon after a miss" do
          @dice = 0.2
          strike

          expect(@exposed).to eq []
          expect(dagger.poison['name']).to eq 'Giant Centipede Venom'
        end

        it "should be wasted by a critical miss" do
          @dice = 0.01
          strike

          expect(@exposed).to eq []
          expect(dagger.poison).to eq({})
        end

        it "should be wasted by a hit that deals neither piercing nor slashing damage" do
          club = Pf2egear.create_item(state, 'weapons', 'Club', 1, Global.read_config('pf2e_weapons', 'Club'))
          club.update(:equipped => true, :poison => { 'name' => 'Giant Centipede Venom', 'dc' => 0 })
          @dice = 0.95
          run(PF2EncounterStrikeCmd, 'e/strike club=#2', @hero)

          expect(@exposed).to eq []
          expect(PF2Weapon[club.id].poison).to eq({})
        end
      end

      # Every injury poison the vendor sells reads as an affliction: a DC, a save, and stages.
      it "should read every stocked injury poison as an affliction" do
        unread = Global.read_config('pf2e_consumables').select { |_name, info|
          WeaponPoison.injury?(info) && info['poison_damage'].nil?
        }.reject { |name, info|
          read = Afflictions.read(name, info['affliction'], info['traits'])
          read && read['dc'].positive? && read['save'] == 'fortitude' && read['stages'].any?
        }.keys

        expect(unread).to eq []
      end

      # Powerful Alchemy: a poison an alchemist made carries their class DC, saved against where higher.
      it "should be saved against at its maker's DC where that is higher" do
        poison
        dagger.update(:poison => dagger.poison.merge('dc' => 24))
        @dice = 0.95
        strike

        expect(@exposed.first.last).to eq 24
      end

      describe "Poison Weapon" do
        before(:each) { @hero.update(:pf2_feats => { 'charclass' => [ 'Poison Weapon' ] }) }

        it "should give a rogue as many simple injury poisons as their level at a rest" do
          Pf2e.rest(state)

          simple = state.consumables.to_a.find { |one| one.name == WeaponPoison::SIMPLE }

          expect([ simple.quantity, simple.expires ]).to eq [ 4, 'rest' ]
        end

        it "should deal a simple injury poison's damage on a hit, with no save" do
          Pf2e.rest(state)
          poison('e/poison dagger=simple')
          before = npc_hp
          @dice = 0.95
          strike

          expect(@exposed).to eq []
          expect(@client.said.join).to include t('pf2e.poison_exposed', :target => 'Goblin Warrior #2', :poison => WeaponPoison::SIMPLE)
          expect(npc_hp).to be < before
        end

        def npc_hp
          Harm.hit_points(Combatants.find(PF2Encounter[@encounter.id], '#2').state.holder)
        end
      end
    end
  end
end
