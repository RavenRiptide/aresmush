require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A night's rest, as it reaches what the turn counts.
    #
    # An action limited to once a day or once an hour is counted in the `rest` period, which only a
    # rest starts over. Nothing started it over, so the first use of a once-a-day action was the last.
    describe "a night's rest", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Rester#{rand(1000000)}")
        @combat = Pf2eCombat.create(:character => @char, :armor_prof => { 'unarmored' => 'trained' })
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
        @char.update(:combat => @combat, :hp => @hp, :pf2_level => 3, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Fighter' },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12) }

        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
      end

      after(:each) do
        (@abilities + [ @hp, @combat, @char ]).each { |one| one&.delete }
      end

      def char
        Character[@char.id]
      end

      it "should make a once-a-day action usable again" do
        TurnState.spend(char, 'Once A Day', :frequency => { 'max' => 1, 'per' => 'day' })
        expect(TurnState.used(char, 'Once A Day')).to eq 1

        expect(Pf2e.do_daily_prep(char)).to be_nil

        expect(TurnState.used(char, 'Once A Day')).to eq 0
      end

      it "should leave what is limited per encounter to the encounter" do
        TurnState.spend(char, 'Once A Fight', :frequency => { 'max' => 1, 'per' => 'PT1M' })

        Pf2e.do_daily_prep(char)

        expect(TurnState.used(char, 'Once A Fight')).to eq 1
      end
    end
  end
end
