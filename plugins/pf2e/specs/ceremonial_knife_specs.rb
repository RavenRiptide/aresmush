require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A witch's ceremonial knife: a knife-group weapon picked each day to work as a wand holding one of the
    # familiar's spells (CeremonialKnife).
    describe CeremonialKnife do

      describe "the highest rank it holds" do
        block = { 'max_rank' => { 'level' => 6, 'rank' => 1, 'every' => 2 } }

        it "should hold rank 1 at 6th level, and 1 more at 8th and every 2 levels after" do
          ranks = [ 6, 7, 8, 9, 10, 20 ].map { |level| CeremonialKnife.max_rank(double(:pf2_level => level), block) }

          expect(ranks).to eq [ 1, 1, 2, 2, 3, 8 ]
        end
      end

      describe "on a witch", :dbtest => true do

        class KnifeClient
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

          @client = KnifeClient.new
          @room = Room.create(:name => "Hut#{rand(1000000)}")
          @scene = Scene.create(:room => @room)
          @room.update(:scene => @scene)
          @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
          @hero = Character.create(:name => "Witch#{rand(1000000)}", :room => @room, :pf2_level => 8,
                                   :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {}, :pf2_daily_choices => {},
                                   :pf2_feats => { 'charclass' => [ 'Ceremonial Knife' ] },
                                   :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
          @combat = Pf2eCombat.create(:character => @hero)
          @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 6)
          @magic = PF2Magic.create(:character => @hero,
                                   :tradition => { 'Witch' => [ 'occult', 'trained' ] },
                                   :spell_abil => { 'Witch' => 'Intelligence' },
                                   :spells_per_day => { 'Witch' => { '1' => 2, '2' => 2, '3' => 2 } },
                                   :spellbook => { 'Witch' => { '1' => [ 'Fear', 'Command' ], '2' => [ 'Invisibility' ], '3' => [ 'Haste' ] } })
          @hero.update(:combat => @combat, :hp => @hp, :magic => @magic, :pf2_base_info => { 'charclass' => 'Witch' })
          @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
          @dagger = PF2Weapon.create(:character => @hero, :name => 'Dagger', :group => 'knife')
          @sword = PF2Weapon.create(:character => @hero, :name => 'Longsword', :group => 'sword')

          allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
          allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
          allow_any_instance_of(Room).to receive(:emit_ooc)
          allow(Scenes).to receive(:add_to_scene)
          allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * 0.75).ceil, 1 ].max ] * amount.to_i }
        end

        after(:each) do
          PF2Encounter[@encounter.id]&.delete if @encounter
          PF2Weapon.find(:character_id => @hero.id).each(&:delete)
          (@abilities + [ @magic, @hp, @combat, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
        end

        def hero
          Character[@hero.id]
        end

        def pick(typed)
          DailyChoices.pick!(hero, 'ceremonialknife', typed)
        end

        def run(klass, text, who = hero)
          klass.new(@client, Command.new(text), who).on_command
        end

        def start
          @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :organizer => @gm.name, :round => 1, :is_active => true)
          hero.encounters.add @encounter
          Combatants.join(@encounter, @hero.name, 10, :holder => hero)
        end

        def state
          CombatantStates.of(PF2Encounter[@encounter.id], hero)
        end

        def knife_number
          Pf2egear::Inventory.held(state, 'weapons').index { |one| one.name == 'Dagger' }
        end

        def copy
          Pf2egear::Inventory.held(state, 'weapons').find { |one| one.name == 'Dagger' }
        end

        describe "the pick" do
          it "should offer their knife-group weapons and the spells their familiar knows, up to the rank it holds" do
            offered = DailyChoices.options(hero, DailyChoices.for_switch(hero, 'ceremonialknife'))

            expect(offered).to eq [ t('pf2e.knife_offer_weapons', :weapons => 'Dagger'),
                                    t('pf2e.knife_offer_spells', :rank => 2, :spells => 'Command, Fear, Invisibility') ]
          end

          it "should bind the weapon by its id, with the spell at its own rank unless one is given" do
            expect(pick('dagger: fear')).to be_ok
            expect(CeremonialKnife.today(hero)).to eq('weapon' => @dagger.id.to_s, 'name' => 'Dagger', 'spell' => 'Fear', 'rank' => 1)

            DailyChoices.unpick!(hero, 'ceremonialknife')
            pick('Dagger: Fear 2')

            expect(CeremonialKnife.today(hero)['rank']).to eq 2
          end

          it "should refuse a weapon outside the knife group" do
            expect(pick('Longsword: Fear').code).to eq :knife_no_weapon
          end

          it "should refuse a spell their familiar doesn't know, or one too high" do
            expect(pick('Dagger: Charm').code).to eq :knife_no_spell
            expect(pick('Dagger: Haste').code).to eq :knife_no_spell
            expect(pick('Dagger: Fear 3').code).to eq :knife_bad_rank
          end

          it "should hold through a rest while they carry the knife" do
            pick('Dagger: Fear')
            DailyChoices.rested!(hero)

            expect(CeremonialKnife.today(hero)).to include('spell' => 'Fear')
          end

          # Selling it ends the binding rather than being refused.
          it "should end when the knife is sold" do
            pick('Dagger: Fear')
            @dagger.delete

            expect(CeremonialKnife.knife?(hero, @sword)).to be false

            DailyChoices.rested!(hero)

            expect(CeremonialKnife.today(hero)).to be_nil
          end

          it "should not make the knife work for anyone else who carries it" do
            pick('Dagger: Fear')
            other = Character.create(:name => "Other#{rand(1000000)}", :pf2_daily_choices => {})
            @dagger.update(:character => other)

            expect(CeremonialKnife.knife?(other, PF2Weapon[@dagger.id])).to be false
            expect(CeremonialKnife.knife?(hero, PF2Weapon[@dagger.id])).to be true

            other.delete
          end

          it "should say on the weapon's view what it holds today" do
            pick('Dagger: Fear')

            expect(CeremonialKnife.describe(hero, @dagger)).to eq [ t('pf2e.knife_holds', :spell => 'Fear', :rank => 1) ]
            expect(CeremonialKnife.describe(hero, @sword)).to eq []
          end
        end

        describe "casting from it in an encounter" do
          before(:each) do
            pick('Dagger: Fear 2')
            start
            allow(Acting).to receive(:cast).and_call_original
          end

          def use
            run(Pf2egear::PF2EncounterUseCmd, "e/use weapons=#{knife_number}/#{@hero.name}")
          end

          def overcharge
            run(Pf2egear::PF2EncounterOverchargeCmd, "e/overcharge weapons=#{knife_number}/#{@hero.name}")
          end

          it "should cast its spell at its rank, once a day, and again after a rest" do
            use

            expect(@client.failures).to eq []
            expect(Acting).to have_received(:cast) do |_scene, spell, _targets, _words, cast:, noted:, adds:|
              expect([ spell, cast['spell level'] ]).to eq [ 'Fear', '2' ]
            end

            use

            expect(@client.failures).to eq [ t('pf2e.wand_used_today', :item => 'Dagger') ]

            Pf2e.rest(state)
            use

            expect(@client.failures.size).to eq 1
          end

          it "should break on a successful overcharge, which settles onto their own dagger" do
            use
            overcharge

            expect(@client.failures).to eq []
            expect(copy.broken).to be true

            Pf2e.rest(state)
            use

            expect(@client.failures).to eq [ t('pf2e.knife_broken', :item => 'Dagger') ]

            Equipment.settle!(state)

            expect(PF2Weapon[@dagger.id].broken).to be true
          end

          it "should be destroyed on a failed overcharge, here and on their sheet" do
            use
            allow(Pf2e).to receive(:roll_dice).and_return([ 4 ])
            overcharge

            expect(copy).to be_nil

            Equipment.settle!(state)

            expect(PF2Weapon[@dagger.id]).to be_nil
          end

          it "should not let another weapon be overcharged" do
            sword = Pf2egear::Inventory.held(state, 'weapons').index { |one| one.name == 'Longsword' }
            run(Pf2egear::PF2EncounterOverchargeCmd, "e/overcharge weapons=#{sword}/#{@hero.name}")

            expect(@client.failures).to eq [ t('pf2e.wand_overcharge_only_wands') ]
          end
        end
      end
    end
  end
end
