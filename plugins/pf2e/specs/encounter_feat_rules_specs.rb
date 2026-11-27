require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Feats whose rules reach something the encounter engine works out: when dying is death, a Will DC
    # against Intimidation, a Speed, how often an action may be used, a healing spell's dice, and who goes
    # first on a tied initiative.
    describe "feats in the encounter engine", :dbtest => true do

      class FeatRulesClient
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

        @client = FeatRulesClient.new
        @room = Room.create(:name => "Arena#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Aria#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @hero, :armor_prof => { 'unarmored' => 'trained' },
                                    :weapon_prof => { 'unarmed' => 'trained' },
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

      def run(cmd_class, text, who = @gm)
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
        @encounter = PF2Encounter[@encounter.id]
      end

      def join_hero(init = 30)
        Combatants.join(@encounter, @hero.name, init, :holder => hero)
        @encounter = PF2Encounter[@encounter.id]
      end

      describe "Diehard" do
        it "should leave death at dying 4 without it" do
          expect(Pf2eHP.fatal_at(hero)).to eq 4
        end

        it "should make death dying 5, and Doomed still lowers it" do
          with_feats('Diehard')

          expect(Pf2eHP.fatal_at(hero)).to eq 5

          Pf2e.set_condition(hero, 'Doomed', 1)
          expect(Pf2eHP.fatal_at(hero)).to eq 4
        end
      end

      describe "Stone Face" do
        it "should add 2 to the Will DC against Intimidation, and nothing against anything else" do
          base = Resolve.defence(hero, 'will')['dc']
          with_feats('Stone Face')

          expect(Resolve.defence(hero, 'will', :options => [ 'check:statistic:intimidation' ])['dc']).to eq base + 2
          expect(Resolve.defence(hero, 'will', :options => [ 'check:statistic:deception' ])['dc']).to eq base
        end

        it "should leave the Will save itself alone" do
          base = Check.of(hero, 'save', 'will', [ 'check:statistic:intimidation' ]).total
          with_feats('Stone Face')

          expect(Check.of(hero, 'save', 'will', [ 'check:statistic:intimidation' ]).total).to eq base
        end

        it "should be asked with the skill a creature Demoralizes with" do
          join_hero
          run(PF2EncounterAddCmd, 'e/add goblin warrior')
          asked = []
          allow(Resolve).to receive(:defence).and_wrap_original do |original, holder, against, **opts|
            asked << Array(opts[:options]) if against.to_s.casecmp?('will')
            original.call(holder, against, **opts)
          end

          run(PF2EncounterAsCmd, "e/as #2=act demoralize=#{@hero.name}")

          expect(asked.flatten).to include 'check:statistic:intimidation'
        end
      end

      describe "Rapid Response" do
        it "should add 10 feet to their Speed while switched on" do
          with_feats('Rapid Response')
          expect(Movement.for(hero)['land']).to eq 25

          RollOptions.set(hero, 'rapid-response', true)

          expect(Movement.for(hero)['land']).to eq 35
        end
      end

      describe "how often an action may be used" do
        it "should count Oruch Ferocity by the day, and by the hour with Incredible Ferocity" do
          with_feats('Oruch Ferocity')
          expect(Actions.frequency(hero, 'Oruch Ferocity')['per']).to eq 'day'

          with_feats('Oruch Ferocity', 'Incredible Ferocity')
          expect(Actions.frequency(hero, 'Oruch Ferocity')['per']).to eq 'PT1H'
        end

        it "should count Eat Fortune by the hour with Jinx Glutton" do
          with_feats('Eat Fortune', 'Jinx Glutton')

          expect(Actions.frequency(hero, 'Eat Fortune')['per']).to eq 'PT1H'
        end

        it "should say the altered frequency once it is reached" do
          with_feats('Oruch Ferocity', 'Incredible Ferocity')
          join_hero

          2.times { run(PF2EncounterActCmd, 'e/act oruch ferocity', @hero) }

          expect(@client.said.join("\n")).to include 'PT1H'
        end
      end

      describe "a healing spell's dice" do
        HEAL = [ [ '2d8', 'vitality', nil, [ 'healing' ] ] ].freeze

        it "should roll heal's d8s as d10s with Healing Hands, and leave other spells alone" do
          with_feats('Healing Hands')

          expect(SpellRolls.dice(hero, 'Heal', HEAL).first.first).to eq '2d10'
          expect(SpellRolls.dice(hero, 'Soothe', HEAL).first.first).to eq '2d8'
        end

        it "should roll harm's d8s as d10s with Harming Hands" do
          with_feats('Harming Hands')

          expect(SpellRolls.dice(hero, 'Harm', [ [ '3d8', 'void', nil, [ 'damage' ] ] ]).first.first).to eq '3d10'
        end

        it "should leave heal alone without the feat" do
          expect(SpellRolls.dice(hero, 'Heal', HEAL)).to eq HEAL
        end

        it "should show Communal Healing's note on a heal of one or two actions, and not three" do
          with_feats('Communal Healing')

          expect(SpellRolls.notes(hero, 'Heal', HEAL, 2)).not_to be_empty
          expect(SpellRolls.notes(hero, 'Heal', HEAL, 3)).to be_empty
        end
      end

      describe "Pilgrim's Token" do
        def symbol!
          Pf2egear.create_item(hero, 'gear', 'Religious Symbol (Wooden)', 1, Global.read_config('pf2e_gear', 'Religious Symbol (Wooden)'))
        end

        def init_of(name)
          PF2Encounter[@encounter.id].participants.find { |row| row['name'] == name }['init']
        end

        it "should put a creature first on a tie without it" do
          join_hero(15)
          run(PF2EncounterAddCmd, 'e/add goblin warrior')
          Combatants.reroll(@encounter, 2, 15)

          expect(init_of('Goblin Warrior #2')).to be > init_of(@hero.name)
        end

        it "should put them first on a tie while they carry a religious symbol" do
          with_feats("Pilgrim's Token")
          symbol!
          join_hero(15)
          run(PF2EncounterAddCmd, 'e/add goblin warrior')
          Combatants.reroll(@encounter, 2, 15)

          expect(init_of(@hero.name)).to be > init_of('Goblin Warrior #2')
        end

        it "should not put them first without a symbol or the token" do
          with_feats("Pilgrim's Token")
          join_hero(15)
          run(PF2EncounterAddCmd, 'e/add goblin warrior')
          Combatants.reroll(@encounter, 2, 15)

          expect(init_of('Goblin Warrior #2')).to be > init_of(@hero.name)
        end
      end
    end
  end
end
