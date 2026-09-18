require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Actions: what one is, whose it is, and using one - which, for an action that puts an effect on its
    # user, puts them under it.
    describe "actions", :dbtest => true do

      class ActionClient
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

        def to_s
          "ActionClient"
        end
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = ActionClient.new
        @room = Room.create(:name => "Hall#{rand(1000000)}")
        @char = Character.create(:name => "Doer#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @char, :armor_prof => { 'unarmored' => 'trained' })
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 12)
        @char.update(:combat => @combat, :hp => @hp, :pf2_level => 3, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Fighter' },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12) }

        allow_any_instance_of(Room).to receive(:emit)
      end

      after(:each) do
        ActiveEffects.on(Character[@char.id]).each(&:delete)
        (@abilities + [ @hp, @combat, @char, @room ]).each { |one| one&.delete }
      end

      def reread
        Character[@char.id]
      end

      def run(cmd_class, text)
        cmd_class.new(@client, Command.new(text), reread).on_command
      end

      def barbarian!
        @char.update(:pf2_base_info => { 'charclass' => 'Barbarian' },
                     :pf2_features => { 'charclass_features' => [ 'Rage' ], 'archetype_features' => [] })
      end

      describe "the catalogue" do
        it "should have their actions and the feats that are actions" do
          expect(Actions.catalogue.size).to be > 1000
        end

        it "should say what an action puts on whoever uses it" do
          expect(Actions.info('Rage')['self_effect']).to eq 'Effect: Rage'
        end

        it "should say what it costs" do
          expect(Actions.cost('Rage')).to eq 'one action'
        end
      end

      describe "whose it is" do
        it "should be everyone's for a basic action" do
          expect(Actions.usable(reread, 'Take Cover').ok?).to be true
        end

        it "should not be a fighter's to Rage" do
          expect(Actions.usable(reread, 'Rage').code).to eq :not_yours
        end

        # The Rage class feature is what gives it.
        it "should be a barbarian's, who has the feature it comes from" do
          barbarian!

          expect(Actions.usable(reread, 'Rage').ok?).to be true
        end

        it "should be the owner's of a feat that is an action" do
          expect(Actions.usable(reread, 'Mountain Stance').ok?).to be false

          @char.update(:pf2_feats => { 'class' => [ 'Mountain Stance' ] })

          expect(Actions.usable(reread, 'Mountain Stance').ok?).to be true
        end
      end

      describe "using one" do
        it "should put its effect on the one who uses it" do
          barbarian!

          run(PF2ActionUseCmd, "action/use rage")

          expect(@client.failures).to eq []
          expect(ActiveEffects.on(reread).map(&:name)).to eq [ 'Effect: Rage' ]
        end

        # Rage's temporary hit points are its effect's, and come with it.
        it "should bring everything the effect does" do
          barbarian!

          run(PF2ActionUseCmd, "action/use rage")

          expect(Pf2eHP[@hp.id].temp_hp).to eq 3 + 1
        end

        it "should refuse an action the character does not have, and put nothing on them" do
          run(PF2ActionUseCmd, "action/use rage")

          expect(@client.failures.join).to include 'Rage'
          expect(ActiveEffects.on(reread)).to eq []
        end

        it "should let anyone use a basic action and take on its effect" do
          run(PF2ActionUseCmd, "action/use take cover")

          expect(ActiveEffects.on(reread).map(&:name)).to eq [ 'Effect: Cover' ]
        end

        it "should say so for an action with no effect of its own" do
          expect(Actions.use(reread, 'Stride').state).to eq('action' => 'Stride', 'effect' => nil)
        end
      end

      describe "the display" do
        def shown(name)
          PF2ActionViewTemplate.new(reread, name).render
        end

        it "should offer the command that takes the effect on" do
          barbarian!

          expect(shown('Rage')).to include 'action/use Rage', 'Effect: Rage'
        end

        it "should not offer it to someone who does not have the action" do
          expect(shown('Rage')).to_not include 'action/use'
          expect(shown('Rage')).to include 'You do not have this action'
        end

        it "should show a feat's own text for a feat that is an action" do
          expect(shown('Mountain Stance')).to include 'implacable mountain', 'Stance: Mountain Stance'
        end

        it "should say how often it can be used" do
          often = Actions.catalogue.find { |_name, info| info['frequency'] && info['frequency']['per'] == 'day' }.first

          expect(shown(often)).to include 'once per day'
        end
      end
    end
  end
end
