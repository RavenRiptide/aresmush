require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An egalrin feather fan's Wave Fan, through `use`: a spell the fan holds at its own rank, at the higher of
    # class DC and spell DC, one use each of the day's activations, and an innate cantrip for free.
    describe WaveFan, :dbtest => true do

      class WaveFanClient
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

      let(:fan) { 'Egalrin Feather Fan' }

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = WaveFanClient.new
        @room = Room.create(:name => "Cliff#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Egal#{rand(1000000)}", :room => @room, :pf2_level => 9,
                                 :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {},
                                 :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Egalrin' },
                                 :pf2_feats => { 'ancestry' => [ fan ] },
                                 :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @combat = Pf2eCombat.create(:character => @hero, :class_dc => 'expert')
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 6, :charclass_hp => 10)
        @hero.update(:combat => @combat, :hp => @hp)
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 16) }
        BoundItems.settle!(hero)

        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :organizer => @gm.name, :round => 1, :is_active => true)
        hero.encounters.add @encounter
        Combatants.join(@encounter, @hero.name, 10, :holder => hero)

        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow_any_instance_of(Room).to receive(:emit_ooc)
        allow(Scenes).to receive(:add_to_scene)
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * 0.75).ceil, 1 ].max ] * amount.to_i }
        allow(Acting).to receive(:cast).and_call_original
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete
        PF2MagicItem.find(:character_id => @hero.id).each(&:delete)
        @magic&.delete
        (@abilities + [ @hp, @combat, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def hero
        Character[@hero.id]
      end

      def state
        CombatantStates.of(PF2Encounter[@encounter.id], hero)
      end

      def held
        Pf2egear::Inventory.held(state, 'magicitem').find { |one| one.name == fan }
      end

      def number
        Pf2egear::Inventory.held(state, 'magicitem').index { |one| one.name == fan }
      end

      def use(rest = '')
        Pf2egear::PF2EncounterUseCmd.new(@client, Command.new("e/use magicitem=#{number}#{rest}"), hero).on_command
      end

      def last_cast
        found = nil
        expect(Acting).to have_received(:cast).at_least(:once) do |_scene, spell, _targets, _words, cast:, noted:|
          found = [ spell, cast ]
        end
        found
      end

      it "should cast the one spell it holds without naming it, at its rank and the fighter's class DC" do
        use

        expect(@client.failures).to eq []

        spell, cast = last_cast

        expect([ spell, cast['spell level'], cast['tradition'], cast['prof_level'] ]).to eq [ 'Gust of Wind', '1', 'primal', 'expert' ]
        expect(held.activations_used).to eq 1
      end

      it "should cast at their spell DC where it's higher than their class DC" do
        @magic = PF2Magic.create(:character => @hero, :tradition => { 'Sorcerer' => [ 'primal', 'master' ] },
                                 :spell_abil => { 'Sorcerer' => 'Charisma' })
        @hero.update(:magic => @magic)
        use

        expect(last_cast.last['prof_level']).to eq 'master'
      end

      describe "with Wind God's Fan" do
        before(:each) do
          @hero.update(:pf2_feats => { 'ancestry' => [ fan, "Wind God's Fan" ] })
        end

        it "should ask which spell, then cast the one named after the targets at its own rank" do
          use

          expect(@client.failures.first).to start_with t('pf2e.wave_fan_which', :item => fan, :spells => 'Gust of Wind, Wall of Wind')

          use('//wall of wind')

          expect(@client.failures.size).to eq 1
          expect(last_cast.first).to eq 'Wall of Wind'
          expect(last_cast.last['spell level']).to eq '3'
        end

        it "should cast as many times a day as it has activations, and again after a rest" do
          2.times { use('//gust of wind') }
          use('//gust of wind')

          expect(@client.failures).to eq [ t('pf2e.wave_fan_spent', :item => fan) ]

          Pf2e.rest(state)
          use('//gust of wind')

          expect(@client.failures.size).to eq 1
        end
      end

      it "should cast an innate cantrip without spending an activation" do
        @magic = PF2Magic.create(:character => @hero,
                                 :innate_spells => [ { 'name' => 'Electric Arc', 'level' => 'cantrip', 'tradition' => 'primal',
                                                       'cast_stat' => 'Charisma' } ])
        @hero.update(:magic => @magic)
        use
        use('//electric arc')

        expect(@client.failures).to eq []
        expect(last_cast.first).to eq 'Electric Arc'
        expect(held.activations_used).to eq 1
      end

      it "should refuse once they no longer hold the feat" do
        @hero.update(:pf2_feats => { 'ancestry' => [] })
        use

        expect(@client.failures).to eq [ t('pf2e.bound_item_cannot_use', :item => fan, :feat => fan) ]
      end

      it "should tell the room outside an encounter" do
        PF2Encounter[@encounter.id].update(:is_active => false)
        own = Pf2egear::Inventory.held(hero, 'magicitem').index { |one| one.name == fan }

        Pf2egear::PF2UseItemCmd.new(@client, Command.new("use magicitem=#{own}"), hero).on_command

        expect(@client.failures).to eq []
        expect(@client.said.join).to include t('pf2e.wave_fan_outside', :name => @hero.name, :spell => 'Gust of Wind', :item => fan)
      end
    end
  end
end
