require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Mutagens as polymorphs: one at a time for anyone, two for a Mutagenist at 13th level, each a benefit
    # and a drawback a later polymorph or a field vial can part.
    describe Mutagens, :dbtest => true do

      class MutagenClient
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

      let(:bestial) { 'Effect: Bestial Mutagen (Lesser)' }
      let(:juggernaut) { 'Effect: Juggernaut Mutagen (Lesser)' }
      let(:cognitive) { 'Effect: Cognitive Mutagen (Lesser)' }

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = MutagenClient.new
        @room = Room.create(:name => "Lab#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Mutt#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @hero, :armor_prof => { 'unarmored' => 'trained' }, :class_dc => 'expert',
                                    :weapon_prof => { 'simple' => 'trained', 'bomb' => 'expert', 'unarmed' => 'trained' },
                                    :unarmed_attacks => {})
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 8)
        @hero.update(:combat => @combat, :hp => @hp, :pf2_level => 13, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_roll_options => {},
                     :pf2_base_info => { 'charclass' => 'Fighter' },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map do |name|
          Pf2eAbilities.create(:character => @hero, :name => name, :base_val => name == 'Intelligence' ? 18 : 14)
        end
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => @gm.name, :round => 1, :is_active => true)
        @hero.encounters.add @encounter
        @encounter.characters.add @hero
        Combatants.join(@encounter, @hero.name, 30, :holder => @hero)

        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * 0.5).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow(Scenes).to receive(:add_to_scene)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Login).to receive(:notify)
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
      end

      after(:each) do
        (@abilities + [ @encounter, @hp, @combat, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def state
        CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id])
      end

      def drink(name)
        ActiveEffects.apply(state, name, :encounter => PF2Encounter[@encounter.id]).state
      end

      def effect(name)
        ActiveEffects.on(state).find { |one| one.name == name }
      end

      def rules_now(name)
        ActiveEffects.sources(state).find { |source| source['name'] == name }['rules']
      end

      def mutagenist
        @hero.update(:pf2_base_info => { 'charclass' => 'Alchemist', 'specialize' => 'Mutagenist' },
                     :pf2_features => { 'charclass_features' => [ 'Advanced Alchemy', 'Versatile Vials', 'Field Discovery',
                                                                  'Advanced Vials', 'Greater Field Discovery' ],
                                        'archetype_features' => [] })
      end

      # Every stocked mutagen has a benefit and a drawback, told apart by what its rules do.
      it "should find a benefit and a drawback in every stocked mutagen" do
        lopsided = Mutagens.effect_names.reject do |name|
          rules = Array(ActiveEffects.info(name)['rules'])
          rules.any? { |row| Mutagens.drawback?(row) } && rules.any? { |row| !Mutagens.drawback?(row) }
        end

        expect(lopsided).to eq []
      end

      describe "the polymorph rule" do
        it "should end the benefits of the mutagen before, and keep its drawbacks" do
          drink(bestial)
          drink(juggernaut)

          expect(effect(bestial).benefits_lost).to be true
          expect(effect(juggernaut).benefits_lost).to be false
          expect(rules_now(bestial).map { |row| Mutagens.drawback?(row) }.uniq).to eq [ true ]
        end

        it "should end every mutagen's benefits when a battle form begins" do
          drink(bestial)
          form = ActiveEffects.catalogue.find { |_name, info| Array((info || {})['rules']).any? { |row| row['key'] == 'BattleForm' } }.first
          Mutagens.began!(state, double(:name => form, :id => 0))

          expect(effect(bestial).benefits_lost).to be true
        end

        it "should let a Mutagenist with Greater Field Discovery keep two, the third ending the older" do
          mutagenist
          drink(bestial)
          drink(juggernaut)

          expect([ effect(bestial).benefits_lost, effect(juggernaut).benefits_lost ]).to eq [ false, false ]

          drink(cognitive)

          expect([ effect(bestial).benefits_lost, effect(juggernaut).benefits_lost, effect(cognitive).benefits_lost ])
            .to eq [ true, false, false ]
        end
      end

      describe "a Mutagenist's field vial" do
        before(:each) do
          mutagenist
          Pf2e.rest(state)
          drink(bestial)
        end

        def use_vial
          number = Pf2egear::Inventory.held(state, 'consumables').index { |one| one.name == 'Versatile Vial (Greater)' }
          Pf2egear::PF2EncounterUseCmd.new(@client, Command.new("e/use consumables=#{number}"), Character[@hero.id]).on_command
        end

        it "should quiet the mutagen's drawbacks for a minute" do
          use_vial

          expect(@client.failures).to eq []
          expect(effect(bestial).drawbacks_until).to eq PF2Encounter[@encounter.id].round.to_i + 10
          expect(rules_now(bestial).map { |row| Mutagens.drawback?(row) }.uniq).to eq [ false ]
        end

        it "should resist physical damage by half their level meanwhile, with Advanced Vials" do
          use_vial

          resisted = Array(IWR.for(state)['resistance']).find { |one| Array(one['type']).include?('physical') }

          expect(resisted['value']).to eq 6
        end
      end

      it "should give a Mutagenist temporary Hit Points for using a mutagen, once a minute" do
        mutagenist
        2.times do
          Pf2egear.create_item(state, 'consumables', 'Bestial Mutagen (Lesser)', 1,
                               Global.read_config('pf2e_consumables', 'Bestial Mutagen (Lesser)'))
        end

        number = Pf2egear::Inventory.held(state, 'consumables').index { |one| one.name == 'Bestial Mutagen (Lesser)' }
        Pf2egear::PF2EncounterUseCmd.new(@client, Command.new("e/use consumables=#{number}"), Character[@hero.id]).on_command

        expect(state.hp.temp_hp).to eq 10
        expect(TurnState.of(state)[ResearchField::MUTAGEN_TEMP]).to eq PF2Encounter[@encounter.id].round.to_i + 10
      end

      describe "Persistent Mutagen" do
        def persist
          PF2PersistentMutagenCmd.new(@client, Command.new('e/persistentmutagen'), Character[@hero.id]).on_command
        end

        before(:each) do
          @hero.update(:pf2_feats => { 'charclass' => [ 'Persistent Mutagen' ] })
        end

        it "should need the feat" do
          @hero.update(:pf2_feats => {})
          drink(bestial)
          persist

          expect(@client.failures).to eq [ t('pf2e.persistent_mutagen_no_feat') ]
        end

        it "should make the newest mutagen last until the next rest, which ends it" do
          drink(bestial)
          persist

          expect(@client.failures).to eq []
          expect(effect(bestial).unit).to eq 'days'

          Pf2e.rest(state)

          expect(effect(bestial)).to be_nil
        end

        it "should work once a day, and again after a rest" do
          drink(bestial)
          persist
          drink(juggernaut)
          persist

          expect(@client.failures).to eq [ t('pf2e.persistent_mutagen_used') ]
          expect(effect(juggernaut).unit).to eq 'minutes'

          Pf2e.rest(state)
          drink(juggernaut)
          persist

          expect(@client.failures.size).to eq 1
          expect(effect(juggernaut).unit).to eq 'days'
        end
      end

      # The record of the dice says what a check was, which is what the reroll asks of it.
      it "should record a save as what it is" do
        allow(Pf2e).to receive(:roll_dice).and_call_original
        tape = DiceTape.recording { Resolve.roll(Check.of(state, 'save', 'fortitude', []), :dc => 15) }

        expect(tape.last['about']).to eq 'save:fortitude'
      end

      describe "the Field Discovery reroll" do
        def reroll
          PF2MutagenRerollCmd.new(@client, Command.new('e/mutagenreroll'), Character[@hero.id]).on_command
        end

        def last_check(about)
          allow(HeroFortune).to receive(:last_check).and_return(Ok.new(:state => { 'row' => { 'about' => about, 'faces' => [ 4 ] } }))
        end

        it "should be a Mutagenist's" do
          reroll

          expect(@client.failures).to eq [ t('pf2e.mutagen_reroll_not_mutagenist') ]
        end

        it "should reroll only a Fortitude save, and only while under a mutagen" do
          mutagenist
          last_check('save:fortitude')
          reroll

          expect(@client.failures.last).to eq t('pf2e.mutagen_reroll_none')

          drink(bestial)
          last_check('save:reflex')
          reroll

          expect(@client.failures.last).to eq t('pf2e.mutagen_reroll_not_fortitude')
        end

        it "should make the check again, then end the mutagen" do
          mutagenist
          drink(bestial)
          last_check('save:fortitude')
          allow(HeroFortune).to receive(:again).and_return(Ok.new(:state => { 'was' => 4, 'now' => 15 }))

          reroll

          expect(@client.failures).to eq []
          expect(effect(bestial)).to be_nil
        end
      end
    end
  end
end
