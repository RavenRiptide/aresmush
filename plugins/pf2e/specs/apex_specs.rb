require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Apex items: an invested one raises an attribute modifier by 1, or to +4, while it's the one that counts.
    # Only one can be invested at a time, and only the first invested in a day counts until the GM rests them.
    # Divine Apex lends the apex trait to a worn item, only in an encounter the cleric is in too.
    describe "apex items", :dbtest => true do

      class ApexClient
        attr_reader :failures, :said

        def initialize
          @failures = []
          @said = []
        end

        def logged_in?
          true
        end

        def screen_reader
          false
        end

        def emit_failure(message)
          @failures << message.to_s
        end

        %w{emit_success emit emit_ooc}.each { |name| define_method(name) { |message| @said << message.to_s } }
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = ApexClient.new
        @room = Room.create(:name => "Shrine#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @made = []
        @hero = person('Hero', 'Fighter', [], 12)

        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow_any_instance_of(Room).to receive(:emit)
        allow(Scenes).to receive(:add_to_scene)
        allow(Login).to receive(:notify)
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete if @encounter
        PF2MagicItem.all.to_a.select { |one| @made.any? { |made| made.is_a?(Character) && one.character_id == made.id } }.each(&:delete)
        @made.reverse.each(&:delete)
        [ @scene, @room ].each(&:delete)
      end

      def person(prefix, charclass, feats, score, faith = {})
        char = Character.create(:name => "#{prefix}#{rand(1000000)}", :room => @room, :pf2_level => 18, :pf2_conditions => {},
                                :pf2_traits => [], :pf2_derived => {}, :pf2_roll_options => {}, :pf2_daily_choices => {},
                                :pf2_base_info => { 'charclass' => charclass }, :pf2_feats => { 'charclass' => feats },
                                :pf2_features => { 'charclass_features' => [] }, :pf2_faith => faith, :pf2_apex => {})
        hp = Pf2eHP.create(:character => char, :ancestry_hp => 8, :charclass_hp => 8)
        combat = Pf2eCombat.create(:character => char)
        char.update(:hp => hp, :combat => combat)
        abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => char, :name => name, :base_val => score) }

        @made += abilities + [ hp, combat, char ]
        char
      end

      def fresh(char = @hero)
        Character[char.id]
      end

      def give(name, char = @hero)
        Pf2egear.create_item(char, 'magicitem', name, 1, Global.read_config('pf2e_magicitem', name))
      end

      def invest(text, char = @hero)
        Pf2egear::PF2InvestCmd.new(@client, Command.new(text), fresh(char)).on_command
      end

      def uninvest(text, char = @hero)
        Pf2egear::PF2UninvestCmd.new(@client, Command.new(text), fresh(char)).on_command
      end

      def number(name, char = @hero)
        Pf2egear::Inventory.held(fresh(char), 'magicitem').index { |one| one.name == name }
      end

      def score(ability, char = @hero)
        Pf2eAbilities.get_score(fresh(char), ability)
      end

      it "should name a real attribute on every apex item" do
        apex = (Global.read_config('pf2e_magicitem') || {}).select { |_name, info| Array(info['traits']).include?('apex') }

        expect(apex.size).to eq 7
        apex.each { |name, info| expect([ name, Pf2e::ABILITIES.include?(info['apex']) ]).to eq [ name, true ] }
      end

      describe "the increase" do
        it "should raise the modifier to +4, or by 1 past it, while invested, and leave the stored score alone" do
          give('Bracers of Strength')
          invest("invest magicitem/#{number('Bracers of Strength')}")

          expect(@client.failures).to eq []
          expect([ score('Strength'), Pf2eAbilities.base_score(fresh, 'Strength'), score('Dexterity') ]).to eq [ 18, 12, 12 ]

          fresh.abilities.to_a.find { |one| one.name == 'Strength' }.update(:base_val => 19)
          expect(score('Strength')).to eq 20

          uninvest("uninvest magicitem/#{number('Bracers of Strength')}")
          expect(score('Strength')).to eq 19
        end

        it "should raise maximum Hit Points with Constitution, and mark the sheet" do
          give('Belt of Long Life')
          before = Pf2eHP.base_max_hp(fresh)
          invest("invest magicitem/#{number('Belt of Long Life')}")

          expect(Pf2eHP.base_max_hp(fresh)).to eq before + (3 * 18)
          expect(Apex.attribute(fresh)).to eq 'Constitution'
        end
      end

      describe "one at a time" do
        before(:each) do
          give('Bracers of Strength')
          give('Necklace of Allure')
          invest("invest magicitem/#{number('Bracers of Strength')}")
        end

        it "should refuse a second apex item while one is invested" do
          invest("invest magicitem/#{number('Necklace of Allure')}")

          expect(@client.failures).to eq [ t('pf2egear.apex_already', :item => 'Necklace of Allure', :other => 'Bracers of Strength') ]
          expect(score('Charisma')).to eq 12
        end

        it "should let a swapped one count only after a rest" do
          uninvest("uninvest magicitem/#{number('Bracers of Strength')}")
          invest("invest magicitem/#{number('Necklace of Allure')}")

          expect(@client.failures).to eq []
          expect([ score('Strength'), score('Charisma') ]).to eq [ 12, 12 ]

          Pf2e.do_daily_investiture(fresh)
          Apex.rested!(fresh)

          expect([ score('Strength'), score('Charisma') ]).to eq [ 12, 18 ]
        end
      end

      describe "an apex crown's skill and language" do
        before(:each) { give('Crown of Intellect') }

        it "should require a skill and a language the first time, and train the skill while it counts" do
          invest("invest magicitem/#{number('Crown of Intellect')}")

          expect(@client.failures.first).to include 'invest magicitem/0/<choice>/<choice>'

          invest("invest magicitem/#{number('Crown of Intellect')}/athletics/Kamin")

          expect(@client.failures.size).to eq 1
          expect(Pf2eSkills.rolling_prof(fresh, 'Athletics')).to eq 'trained'
          crown = Pf2egear::Inventory.held(fresh, 'magicitem').first
          expect(ItemChoices.describe(crown, Global.read_config('pf2e_magicitem', 'Crown of Intellect')))
            .to eq [ t('pf2egear.item_choice', :choice => 'Athletics'), t('pf2egear.item_choice', :choice => 'Kamin') ]

          uninvest("uninvest magicitem/#{number('Crown of Intellect')}")
          expect(Pf2eSkills.rolling_prof(fresh, 'Athletics')).to eq 'untrained'
        end
      end

      describe "Divine Apex" do
        before(:each) do
          deity, = Global.read_config('pf2e_deities').find { |_name, info| Array(info['divine_ability']).include?('Strength') }
          @cleric = person('Cleric', 'Cleric', [ 'Divine Apex' ], 12, 'deity' => deity)
          give('Ring of Lies')
          invest("invest magicitem/#{number('Ring of Lies')}")
        end

        def prepare(text)
          PF2PrepareDailyCmd.new(@client, Command.new(text), fresh(@cleric)).on_command
        end

        def start
          @encounter = PF2Encounter.create(:scene => @scene, :organizer => @cleric.name, :round => 1, :is_active => true)
        end

        def join(char)
          fresh(char).encounters.add @encounter
          PF2Encounter[@encounter.id].characters.add fresh(char)
          Combatants.join(PF2Encounter[@encounter.id], char.name, 10, :holder => fresh(char))
        end

        def state_score(ability)
          Pf2eAbilities.get_score(CombatantStates.of(PF2Encounter[@encounter.id], fresh), ability)
        end

        it "should take a character, a worn magic item of theirs, and a divine attribute" do
          prepare("prepare/divineapex #{@hero.name}: Ring of Lies: Strength")

          expect(@client.failures).to eq []
          expect(fresh(@cleric).pf2_daily_choices['divineapex'].slice('names', 'item', 'attribute'))
            .to eq({ 'names' => [ @hero.name ], 'item' => 'Ring of Lies', 'attribute' => 'Strength' })
        end

        # The character keeps who named them, so their attribute reads look only at those givers.
        it "should remember the cleric on the character it names, through their joining an encounter" do
          prepare("prepare/divineapex #{@hero.name}: Ring of Lies: Strength")
          expect(fresh.pf2_designated_by).to eq [ @cleric.id.to_s ]

          start
          join(@hero)
          DailyChoices.given_on_join!(CombatantStates.of(PF2Encounter[@encounter.id], fresh), fresh)

          expect(fresh.pf2_designated_by).to eq [ @cleric.id.to_s ]
        end

        it "should refuse an item they aren't wearing" do
          prepare("prepare/divineapex #{@hero.name}: Boots of Nothing: Strength")

          expect(@client.failures).to eq [ t('pf2e.daily_apex_item', :name => @hero.name, :item => 'Boots of Nothing', :source => 'Divine Apex') ]
        end

        it "should raise the attribute only in an encounter the cleric is in too" do
          prepare("prepare/divineapex #{@hero.name}: Ring of Lies: Strength")
          expect(score('Strength')).to eq 12

          start
          join(@hero)
          expect(state_score('Strength')).to eq 12

          join(@cleric)
          expect(state_score('Strength')).to eq 18
        end

        it "should give way to their own apex item" do
          give('Necklace of Allure')
          invest("invest magicitem/#{number('Necklace of Allure')}")
          prepare("prepare/divineapex #{@hero.name}: Ring of Lies: Strength")
          start
          join(@hero)
          join(@cleric)

          expect([ state_score('Strength'), state_score('Charisma') ]).to eq [ 12, 18 ]
        end

        # Every attribute read asks for the apex increase, and a command loads each holder afresh many times.
        it "should read the encounter's Divine Apex picks once in a command, until something is written" do
          prepare("prepare/divineapex #{@hero.name}: Ring of Lies: Strength")
          start
          join(@hero)
          join(@cleric)
          asked = 0
          allow(DailyChoices).to receive(:in_force).and_wrap_original do |original, char|
            asked += 1 if char.name == @cleric.name
            original.call(char)
          end

          scores = SheetReads.during do
            first = 3.times.map { state_score('Strength') }
            fresh.update(:pf2_traits => [])
            first + [ state_score('Strength') ]
          end

          expect(scores).to eq [ 18, 18, 18, 18 ]
          expect(asked).to eq 2
        end
      end

      it "should work out a character's apex item once in a command, until something is written" do
        give('Bracers of Strength')
        invest("invest magicitem/#{number('Bracers of Strength')}")
        allow(Apex).to receive(:own).and_call_original

        scores = SheetReads.during do
          first = 3.times.map { score('Strength') }
          fresh.update(:pf2_traits => [])
          first + [ score('Strength') ]
        end

        expect(scores).to eq [ 18, 18, 18, 18 ]
        expect(Apex).to have_received(:own).twice
      end
    end
  end
end
