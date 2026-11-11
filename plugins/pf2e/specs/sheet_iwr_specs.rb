require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What the sheets say someone resists, is immune to and is weak to, under their saves. `sheet` shows
    # what is theirs for good - a feat, a class feature. `csheet` adds their gear and anything they are
    # under outside a fight, and `e/sheet` and `e/csheet` show them as they stand in the encounter.
    describe "resistances on the sheets", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Resists#{rand(1000000)}", :pf2_level => 5, :pf2_conditions => {},
                                 :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => {},
                                 :pf2_features => {}, :pf2_level_tracker => {})
        @combat = Pf2eCombat.create(:character => @char, :armor_prof => { 'unarmored' => 'trained' })
        @char.update(:combat => @combat)
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12) }
        @states = []
      end

      after(:each) do
        reread.pf2_effects.each(&:delete)
        @states.each { |state| state.pf2_effects.each(&:delete); state.delete }
        (@abilities + [ @combat, @char ]).each(&:delete)
      end

      def reread
        Character[@char.id]
      end

      # The feat, and the energy chosen with it, as `advance/feat` records them.
      def take_nephilim_resistance(energy)
        @char.update(:pf2_feats => { 'ancestry' => [ 'Nephilim Resistance' ] },
                     :pf2_level_tracker => { '5' => { 'feat_choices' => { 'Nephilim Resistance' => [ energy ] } } })
      end

      def sheet(holder = reread)
        template = Pf2eSheetTemplate.allocate
        template.instance_variable_set(:@char, holder)
        template
      end

      def csheet(holder = reread)
        template = PF2CombatSheetTemplate.allocate
        template.instance_variable_set(:@char, holder)
        template
      end

      def shown(template)
        SheetReads.holding(template.char) { template.resistances }.join("\n").gsub(/%x(?:\d{1,3}|[a-z])/i, '')
      end

      describe "what is theirs for good" do
        it "should show a feat's resistance on the sheet and the combat sheet" do
          take_nephilim_resistance('fire')

          expect(shown(sheet)).to eq 'Resistances: fire 5'
          expect(shown(csheet)).to eq 'Resistances: fire 5'
        end

        it "should say None. for someone who resists nothing" do
          expect(shown(sheet)).to eq 'Resistances: None.'
          expect(shown(csheet)).to eq 'Resistances: None.'
        end

        # Every living thing is untouched by void or vitality, which is not worth a line of anyone's sheet.
        it "should not list the immunity everyone living shares" do
          @char.update(:pf2_traits => [ 'humanoid' ])

          expect(shown(csheet)).to_not include('Immunities')
        end
      end

      # A heritage's resistance is half their level, and never less than 1.
      describe "a heritage's resistance" do
        before(:each) do
          @char.update(:pf2_base_info => { 'ancestry' => 'Goblin', 'heritage' => 'Snow' })
        end

        it "should be 1 at first level" do
          @char.update(:pf2_level => 1)

          expect(shown(sheet)).to eq 'Resistances: cold 1'
        end

        it "should grow with their level" do
          @char.update(:pf2_level => 7)

          expect(shown(sheet)).to eq 'Resistances: cold 3'
          expect(shown(csheet)).to eq 'Resistances: cold 3'
        end

        it "should take that much off the damage they resist" do
          @char.update(:pf2_level => 7)

          expect(IWR.apply(IWR.of(reread), 10, 'cold')['amount']).to eq 7
          expect(IWR.apply(IWR.of(reread), 10, 'fire')['amount']).to eq 10
        end
      end

      describe "what they are under outside a fight" do
        before(:each) do
          take_nephilim_resistance('fire')
          ActiveEffects.apply(reread, 'Effect: Frost Breath')
        end

        it "should show on the combat sheet" do
          expect(shown(csheet)).to eq 'Resistances: fire 5, cold 5'
        end

        it "should not show on the sheet" do
          expect(shown(sheet)).to eq 'Resistances: fire 5'
        end
      end

      describe "what they are under in an encounter" do
        before(:each) do
          take_nephilim_resistance('fire')
          state = Pf2eCombatantState.create(:character => reread)
          @states << state
          ActiveEffects.apply(state, 'Effect: Frost Breath')
          @state = Pf2eCombatantState[state.id]
        end

        it "should show on both encounter sheets" do
          expect(shown(sheet(@state))).to eq 'Resistances: fire 5, cold 5'
          expect(shown(csheet(@state))).to eq 'Resistances: fire 5, cold 5'
        end

        it "should not show on either sheet outside it" do
          expect(shown(sheet)).to eq 'Resistances: fire 5'
          expect(shown(csheet)).to eq 'Resistances: fire 5'
        end
      end

      describe "the rows" do
        it "should list each kind held, resistances first" do
          held = { 'immunity' => [ { 'type' => [ 'poison' ] }, { 'type' => [ 'void' ], 'implied' => true } ],
                   'weakness' => [ { 'type' => [ 'cold-iron' ], 'value' => 5 } ],
                   'resistance' => [ { 'type' => [ 'fire' ], 'value' => 5 }, { 'type' => [ 'cold' ], 'value' => 2 } ] }

          expect(IWR.sheet_rows(held)).to eq [ [ 'Resistances', 'fire 5, cold 2' ], [ 'Immunities', 'poison' ],
                                               [ 'Weaknesses', 'cold-iron 5' ] ]
        end
      end
    end
  end
end
