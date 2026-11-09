require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What lasts until the next daily preparations ends, or comes back, at a rest: Hunt Prey's designation
    # and a Shield Paragon's destroyed shield.
    describe "until the next daily preparations", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Prep#{rand(1000000)}", :pf2_level => 20, :pf2_conditions => {},
                                 :pf2_traits => [], :pf2_derived => {}, :pf2_roll_options => {}, :pf2_daily_choices => {},
                                 :pf2_base_info => { 'charclass' => 'Champion' }, :pf2_feats => {},
                                 :pf2_features => { 'charclass_features' => [] })
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
        @char.update(:hp => @hp)
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14) }
        @shield = PF2Shield.create(:character => @char, :name => 'Steel Shield', :hp => 20, :hardness => 5,
                                   :damage => 0, :equipped => true)
        @encounter = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
        @char.encounters.add @encounter
        Combatants.join(@encounter, @char.name, 10, :holder => char)

        allow(Login).to receive(:emit_ooc_if_logged_in)
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete
        (@abilities + [ @shield, @hp, @char ]).each(&:delete)
      end

      def char
        Character[@char.id]
      end

      def state
        CombatantStates.of(PF2Encounter[@encounter.id], char)
      end

      def shield
        Actors.of(state).shield
      end

      describe "effects kept by hand" do
        it "should each name an effect in the catalogue, a unit effects have, and rules it has" do
          kept = Global.read_config('pf2e_effect_overrides')

          kept.each do |name, over|
            expect(ActiveEffects.catalogue).to have_key name
            expect(ActiveEffects::UNITS).to have_key over['duration']['unit'] if over['duration']
            expect(Array(ActiveEffects.catalogue[name]['rules']).size).to be >= Array(over['rules']).size
          end
        end

        it "should lay kept rule fields over the imported rules by position" do
          rules = ActiveEffects.info('Effect: Root Magic')['rules']

          expect(rules.first['removeAfterRoll']).to eq 'if-enabled'
          expect(rules.first['key']).to eq 'FlatModifier'
        end

        it "should lay the kept unit over the imported duration, and keep the rest of it" do
          imported = ActiveEffects.catalogue['Effect: Hunt Prey']['duration']

          expect(imported['unit']).to eq 'unlimited'
          expect(ActiveEffects.info('Effect: Hunt Prey')['duration']).to eq imported.merge('unit' => 'days', 'value' => 1)
        end
      end

      it "should end Hunt Prey's designation at a rest" do
        ActiveEffects.apply(state, 'Effect: Hunt Prey', :encounter => PF2Encounter[@encounter.id])

        expect(ActiveEffects.named_on(state, 'Effect: Hunt Prey').size).to eq 1

        Pf2e.rest(state)

        expect(ActiveEffects.named_on(state, 'Effect: Hunt Prey')).to eq []
      end

      describe "Shield Paragon" do
        it "should mend a destroyed shield at a rest" do
          @char.update(:pf2_feats => { 'charclass' => [ 'Shield Paragon' ] })
          shield.update(:damage => 20)

          Pf2e.rest(state)

          expect(shield.damage).to eq 0
        end

        it "should leave a shield that is only broken" do
          @char.update(:pf2_feats => { 'charclass' => [ 'Shield Paragon' ] })
          shield.update(:damage => 12)

          Pf2e.rest(state)

          expect(shield.damage).to eq 12
        end

        it "should mend nothing without the feat" do
          shield.update(:damage => 20)

          Pf2e.rest(state)

          expect(shield.damage).to eq 20
        end
      end
    end
  end
end
