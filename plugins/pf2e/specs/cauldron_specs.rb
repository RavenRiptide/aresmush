require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A witch's cauldron: a daily choice of one oil or potion they know, brewed as a batch each day, more
    # copies as their spell DC rises and twice over with Double, Double.
    describe "a witch's cauldron", :dbtest => true do

      class CauldronClient
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
      end

      let(:minor) { 'Healing Potion (Minor)' }
      let(:potency) { 'Oil of Potency' }

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = CauldronClient.new
        @char = Character.create(:name => "Brew#{rand(1000000)}", :pf2_level => 2, :pf2_conditions => {},
                                 :pf2_traits => [], :pf2_faith => {}, :pf2_features => {}, :pf2_level_tracker => {},
                                 :pf2_roll_options => {}, :pf2_derived => {}, :pf2_daily_choices => {},
                                 :pf2_base_info => { 'charclass' => 'Witch' },
                                 :pf2_feats => { 'charclass' => [ 'Cauldron' ] },
                                 :pf2_formula_book => { 'consumables' => [ minor, potency, 'Healing Potion (Lesser)',
                                                                           "Alchemist's Fire (Lesser)" ] })
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 6)
        @char.update(:hp => @hp)
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14) }

        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow(Login).to receive(:emit_ooc_if_logged_in)
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete if @encounter
        (@abilities + [ @hp, @char ]).each(&:delete)
      end

      def char
        Character[@char.id]
      end

      def run(cmd_class, text)
        cmd_class.new(@client, Command.new(text), char).on_command
      end

      def join
        @encounter = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
        char.encounters.add @encounter
        Combatants.join(@encounter, @char.name, 10, :holder => char)
      end

      def state
        CombatantStates.of(PF2Encounter[@encounter.id], char)
      end

      def brewed
        state.consumables.to_a.select { |one| one.granted_by == DailyChoices.brewed_by('cauldron') }
                         .map { |one| [ one.name, one.quantity.to_i, one.expires ] }
      end

      it "should offer the oils and potions they know, no higher than their level" do
        expect(DailyChoices.options(char, DailyChoices.for_switch(char, 'cauldron'))).to eq [ minor, potency ]
      end

      it "should route prepare/cauldron to the daily choice" do
        expect(Pf2emagic.get_cmd_handler(@client, Command.new('prepare/cauldron Oil of Potency'), char)).to eq PF2PrepareDailyCmd
      end

      describe "the batch" do
        def size
          DailyChoices.batch_size(char, 'cauldron', DailyChoices.for_switch(char, 'cauldron'))
        end

        it "should be one copy, two at master spell DC, and three at legendary" do
          { 'trained' => 1, 'expert' => 1, 'master' => 2, 'legendary' => 3 }.each do |rank, many|
            allow(DailyChoices).to receive(:spell_dc_rank).and_return(rank)

            expect(size).to eq many
          end
        end

        it "should be twice that with Double, Double" do
          @char.update(:pf2_feats => { 'charclass' => [ 'Cauldron', 'Double, Double' ] })
          allow(DailyChoices).to receive(:spell_dc_rank).and_return('legendary')

          expect(size).to eq 6
        end
      end

      it "should brew the batch when they join an encounter, to last until their next rest" do
        run(PF2PrepareDailyCmd, 'prepare/cauldron oil of potency')
        join

        expect(@client.failures).to eq []
        expect(brewed).to eq [ [ potency, 1, 'rest' ] ]
      end

      it "should brew a fresh batch at each rest, keeping the pick" do
        run(PF2PrepareDailyCmd, "prepare/cauldron #{minor}")
        join
        Consumables.spend!(state, state.consumables.to_a.find { |one| one.name == minor }.id)

        expect(brewed).to eq []

        Pf2e.rest(state)

        expect(brewed).to eq [ [ minor, 1, 'rest' ] ]
        expect(char.pf2_daily_choices['cauldron']['pick']).to eq minor
      end

      it "should brew at once when they pick in an encounter, and a new pick replaces the batch" do
        join
        Pf2e.rest(state)
        run(PF2PrepareDailyCmd, "prepare/cauldron #{minor}")

        expect(brewed).to eq [ [ minor, 1, 'rest' ] ]
        expect(@client.said.last).to eq t('pf2e.daily_brewed', :name => @char.name, :items => "1 #{minor}", :source => 'Cauldron')

        Pf2e.rest(state)
        run(PF2PrepareDailyCmd, 'prepare/cauldron Oil of Potency')

        expect(brewed).to eq [ [ potency, 1, 'rest' ] ]
      end

      it "should take the batch away with the pick, and brew the one it puts back" do
        run(PF2PrepareDailyCmd, "prepare/cauldron #{minor}")
        join
        Pf2e.rest(state)
        run(PF2PrepareDailyCmd, 'prepare/cauldron Oil of Potency')
        run(PF2UnprepareDailyCmd, 'unprepare/cauldron')

        expect(@client.failures).to eq []
        expect(brewed).to eq [ [ minor, 1, 'rest' ] ]
      end

      it "should brew nothing from a formula that isn't an oil or a potion" do
        run(PF2PrepareDailyCmd, "prepare/cauldron Alchemist's Fire (Lesser)")

        expect(@client.failures.first).to start_with t('pf2e.daily_not_offered', :source => 'Cauldron',
                                                       :pick => "Alchemist's Fire (Lesser)", :options => "#{minor}, #{potency}")
      end
    end
  end
end
