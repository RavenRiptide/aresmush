require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Scrolls and wands: bought from the vendor by spell, cast with `use` in an encounter or told outside one,
    # and a wand's day, overcharge, breaking and repair.
    describe SpellItems, :dbtest => true do

      class SpellItemClient
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

        @client = SpellItemClient.new
        @room = Room.create(:name => "Shop#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Wand#{rand(1000000)}", :room => @room, :pf2_level => 5, :pf2_money => 100_000,
                                 :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {},
                                 :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @combat = Pf2eCombat.create(:character => @hero)
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 6)
        @magic = PF2Magic.create(:character => @hero,
                                 :tradition => { 'Sorcerer' => [ 'primal', 'trained' ] },
                                 :spell_abil => { 'Sorcerer' => 'Charisma' },
                                 :spells_per_day => { 'Sorcerer' => { '1' => 3 } },
                                 :repertoire => { 'Sorcerer' => { '1' => [ 'Charm' ] } })
        @hero.update(:combat => @combat, :hp => @hp, :magic => @magic, :pf2_base_info => { 'charclass' => 'Sorcerer' })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }

        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow_any_instance_of(Room).to receive(:emit_ooc)
        allow(Scenes).to receive(:add_to_scene)
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * 0.75).ceil, 1 ].max ] * amount.to_i }
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete if @encounter
        [ PF2Consumable, PF2MagicItem ].each { |model| model.find(:character_id => @hero.id).each(&:delete) }
        (@abilities + [ @magic, @hp, @combat, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def hero
        Character[@hero.id]
      end

      def run(klass, text, who = hero)
        klass.new(@client, Command.new(text), who).on_command
      end

      def buy(text)
        run(Pf2egear::PF2BuyCmd, text)
      end

      def scrolls
        hero.consumables.to_a.select { |one| one.spell }
      end

      def wands
        hero.magic_items.to_a.select { |one| one.spell }
      end

      def start
        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :organizer => @gm.name, :round => 1, :is_active => true)
        hero.encounters.add @encounter
        Combatants.join(@encounter, @hero.name, 10, :holder => hero)
      end

      def state
        CombatantStates.of(PF2Encounter[@encounter.id], hero)
      end

      def copy(category)
        Pf2egear::Inventory.held(state, category).find { |one| one.spell }
      end

      def number(holder, category)
        Pf2egear::Inventory.held(holder, category).index { |one| one.spell }
      end

      describe "the table" do
        it "should price every rank GM Core lists, the wand a rank short of the scroll" do
          expect(SpellItems.table['scroll']['ranks'].keys.map(&:to_i)).to eq (1..10).to_a
          expect(SpellItems.table['wand']['ranks'].keys.map(&:to_i)).to eq (1..9).to_a
        end
      end

      describe "buying" do
        it "should sell a scroll at the spell's own rank, carrying its spell" do
          buy('buy scroll=fireball')

          expect(@client.failures).to eq []
          expect(scrolls.map { |one| [ one.name, one.spell, one.spell_rank, one.level, one.price ] })
            .to eq [ [ 'Scroll of Fireball (rank 3)', 'Fireball', 3, 5, 3000 ] ]
          expect(hero.pf2_money).to eq 100_000 - 3000
        end

        it "should stack scrolls of the same spell and rank" do
          buy('buy scroll=heal/2')
          buy('buy scroll=heal')

          expect(scrolls.map { |one| [ one.name, one.quantity ] }).to eq [ [ 'Scroll of Heal (rank 1)', 3 ] ]
        end

        it "should heighten with buy/rank<n>, no higher than the buyer's level allows" do
          buy('buy/rank3 scroll=heal')
          buy('buy/rank4 scroll=heal')

          expect(scrolls.map(&:name)).to eq [ 'Scroll of Heal (rank 3)' ]
          expect(@client.failures).to eq [ t('pf2e.spell_item_too_high', :item => 'Scroll of Heal (rank 4)', :level => 7) ]
        end

        it "should sell a wand, one at a time" do
          buy('buy wand=heal')

          expect(wands.map { |one| [ one.name, one.spell_rank, one.level, one.price ] }).to eq [ [ 'Wand of Heal (rank 1)', 1, 3, 6000 ] ]
        end

        it "should refuse a cantrip, a focus spell, a rank below the spell's own, and an uncommon spell" do
          buy('buy scroll=electric arc')
          buy('buy scroll=lay on hands')
          buy('buy/rank1 scroll=fireball')
          buy('buy scroll=dominate')

          expect(@client.failures).to eq [ t('pf2e.spell_item_cantrip', :spell => 'Electric Arc', :kind => 'scroll'),
                                           t('pf2e.spell_item_focus', :spell => 'Lay on Hands', :kind => 'scroll'),
                                           t('pf2e.spell_item_low_rank', :spell => 'Fireball', :rank => 3),
                                           t('pf2e.spell_item_rare', :spell => 'Dominate', :rarity => 'uncommon', :kind => 'scroll') ]
          expect(scrolls).to eq []
        end

        it "should refuse a rank switch on anything but a scroll or wand" do
          buy('buy/rank3 gear=rope')

          expect(@client.failures.size).to eq 1
        end

        it "should show the table to browse, not every spell" do
          run(Pf2egear::PF2BrowseGearCmd, 'browse scroll')

          expect(@client.said.join).to include t('pf2e.spell_item_browse_line', :rank => 3, :level => 5, :price => Pf2egear.display_money(3000))
        end
      end

      describe "using one outside an encounter" do
        it "should tell the room and use up a scroll" do
          buy('buy scroll=heal/2')
          run(Pf2egear::PF2UseItemCmd, "use consumables=#{number(hero, 'consumables')}")

          expect(@client.failures).to eq []
          expect(@client.said.join).to include 'casts Heal at rank 1'
          expect(scrolls.map(&:quantity)).to eq [ 1 ]
        end

        it "should refuse a spell that isn't on their list" do
          buy('buy scroll=force barrage')
          run(Pf2egear::PF2UseItemCmd, "use consumables=#{number(hero, 'consumables')}")

          expect(@client.failures).to eq [ t('pf2e.spell_item_not_listed', :item => 'Scroll of Force Barrage (rank 1)', :spell => 'Force Barrage') ]
          expect(scrolls.size).to eq 1
        end

        it "should leave a wand's day alone" do
          buy('buy wand=heal')
          run(Pf2egear::PF2UseItemCmd, "use magicitem=#{number(hero, 'magicitem')}")

          expect(@client.failures).to eq []
          expect(wands.first.used_today).to be_falsey
        end
      end

      describe "casting one in an encounter" do
        before(:each) do
          buy('buy scroll=heal')
          buy('buy wand=heal')
          start
          allow(Acting).to receive(:cast).and_call_original
        end

        def use(text)
          run(Pf2egear::PF2EncounterUseCmd, text)
        end

        it "should cast a scroll's spell at its rank with their own casting, and use the scroll up" do
          use("e/use consumables=#{number(state, 'consumables')}/#{@hero.name}")

          expect(@client.failures).to eq []
          expect(Acting).to have_received(:cast) do |_scene, spell, targets, _words, cast:, noted:|
            expect([ spell, targets.map(&:label), cast['spell level'], cast['tradition'] ]).to eq [ 'Heal', [ @hero.name ], '1', 'primal' ]
          end
          expect(copy('consumables')).to be_nil
        end

        it "should take the scroll off their sheet when the encounter ends" do
          use("e/use consumables=#{number(state, 'consumables')}/#{@hero.name}")
          Equipment.settle!(state)

          expect(scrolls).to eq []
        end

        it "should cast from a wand once a day, and again after a rest" do
          use("e/use magicitem=#{number(state, 'magicitem')}/#{@hero.name}")
          use("e/use magicitem=#{number(state, 'magicitem')}/#{@hero.name}")

          expect(@client.failures).to eq [ t('pf2e.wand_used_today', :item => 'Wand of Heal (rank 1)') ]

          Pf2e.rest(state)
          use("e/use magicitem=#{number(state, 'magicitem')}/#{@hero.name}")

          expect(@client.failures.size).to eq 1
        end

        describe "overcharging" do
          def overcharge
            run(Pf2egear::PF2EncounterOverchargeCmd, "e/overcharge magicitem=#{number(state, 'magicitem')}/#{@hero.name}")
          end

          before(:each) do
            use("e/use magicitem=#{number(state, 'magicitem')}/#{@hero.name}")
          end

          it "should cast again and break the wand on a successful flat check, which settles onto their own" do
            overcharge

            expect(@client.failures).to eq []
            expect(Acting).to have_received(:cast).twice
            expect(copy('magicitem').broken).to be true

            Equipment.settle!(state)

            expect(wands.first.broken).to be true
          end

          it "should destroy the wand on a failed flat check, here and on their sheet" do
            allow(Pf2e).to receive(:roll_dice).and_return([ 4 ])
            overcharge

            expect(copy('magicitem')).to be_nil

            Equipment.settle!(state)

            expect(wands).to eq []
          end

          it "should leave a broken wand unusable until the GM repairs it" do
            overcharge
            Pf2e.rest(state)
            use("e/use magicitem=#{number(state, 'magicitem')}/#{@hero.name}")

            expect(@client.failures).to eq [ t('pf2e.wand_broken', :item => 'Wand of Heal (rank 1)') ]

            run(Pf2egear::PF2EncounterRepairCmd, "e/repair #{@hero.name}=#{number(state, 'magicitem')}", Character[@gm.id])

            expect(@client.failures.size).to eq 1
            expect(copy('magicitem').broken).to be false
          end

          it "should need the day's casting first" do
            Pf2e.rest(state)
            overcharge

            expect(@client.failures).to eq [ t('pf2e.wand_overcharge_unused', :item => 'Wand of Heal (rank 1)') ]
          end
        end
      end

      describe "specialty wands" do
        it "should sell one holding a spell it takes, priced as the stocked wand of its rank" do
          buy('buy wand=breathe fire (widening)')
          buy('buy wand=tailwind (continuation)')

          expect(@client.failures).to eq []
          expect(wands.map { |one| [ one.name, one.specialty, one.level, one.price ] })
            .to match_array [ [ 'Wand of Widening (Breathe Fire, rank 1)', 'widening', 4, 10000 ],
                              [ 'Wand of Continuation (Tailwind, rank 1)', 'continuation', 5, 16000 ] ]
        end

        it "should refuse a spell the specialty doesn't take, and the stocked wand without a spell" do
          buy('buy wand=heal (widening)')
          buy('buy wand=breathe fire (continuation)')
          buy('buy magicitem=Wand of Widening (1st-Rank Spell)')

          expect(@client.failures).to eq [
            # Heal takes 1 to 3 actions, which is asked before its area.
            t('pf2e.spell_item_specialty_unfit', :spell => 'Heal', :specialty => 'widening', :why => t('pf2e.spell_item_why_actions')),
            t('pf2e.spell_item_specialty_unfit', :spell => 'Breathe Fire', :specialty => 'continuation', :why => t('pf2e.spell_item_why_duration')),
            t('pf2e.spell_item_specialty_buy', :item => 'Wand of Widening (1st-Rank Spell)') ]
          expect(wands).to eq []
        end

        it "should work out the wider area and the longer duration" do
          expect([ SpellItems.widened('15-foot cone'), SpellItems.widened('20-foot burst'), SpellItems.widened('120-foot line') ])
            .to eq [ '20-foot cone', '25-foot burst', '130-foot line' ]
          expect([ SpellItems.lengthened('10 minutes'), SpellItems.lengthened('1 hour') ]).to eq [ '15 minutes', '90 minutes' ]
        end

        describe "cast in an encounter" do
          def use
            run(Pf2egear::PF2EncounterUseCmd, "e/use magicitem=#{number(state, 'magicitem')}/#{@hero.name}")
          end

          def actions
            TurnState.turn(state)['actions'].to_i
          end

          it "should take an action more and widen the area" do
            buy('buy wand=breathe fire (widening)')
            start
            use

            expect(@client.failures).to eq []
            expect(actions).to eq 3
            expect(@client.said.join).to include '20-foot cone'
          end

          it "should take an action more and keep the spell's effect half again as long, past the encounter" do
            buy('buy wand=tailwind (continuation)')
            start
            use

            effect = ActiveEffects.named_on(state, 'Spell Effect: Tailwind').first

            # Tailwind's 2 actions, and the wand's 1 more.
            expect(actions).to eq 3
            expect(effect.unit).to eq 'hours'
            expect(effect.started_round.to_i + ActiveEffects.rounds_long(effect) - PF2Encounter[@encounter.id].round.to_i).to eq 900
          end
        end
      end

      it "should say in the item view what it holds, and that a wand is broken" do
        buy('buy wand=heal')
        wands.first.update(:broken => true)

        shown = Pf2egear::Pf2eDisplayItemTemplate.new(hero, wands.first, 'magicitem', @client).render

        expect(shown).to include t('pf2e.spell_item_holds', :spell => 'Heal', :rank => 1)
        expect(shown).to include t('pf2e.wand_is_broken')
        expect(shown).to_not include 'This item cannot be used.'
      end

      it "should let staff repair a broken wand on a sheet" do
        buy('buy wand=heal')
        wands.first.update(:broken => true)
        allow_any_instance_of(Character).to receive(:has_permission?).and_return(true)

        run(Pf2egear::PF2WandRepairCmd, "wand/repair #{@hero.name}=#{number(hero, 'magicitem')}", Character[@gm.id])

        expect(@client.failures).to eq []
        expect(wands.first.broken).to be false
      end
    end
  end
end
