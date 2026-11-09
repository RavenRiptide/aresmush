require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # An alchemist's day, as the remaster has it: prepared items made at each rest, and versatile vials,
    # counted apart. A vial is a bomb, or what Quick Alchemy spends to make an item on the spot.
    describe Alchemy, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        # Level 3 with Intelligence 14: 4 + 2 prepared items, and 2 + 2 vials.
        @char = Character.create(:name => "Alch#{rand(1000000)}", :pf2_level => 3, :pf2_conditions => {},
                                 :pf2_reagents => {}, :pf2_alchemy_plan => {},
                                 :pf2_base_info => { 'charclass' => 'Alchemist' },
                                 :pf2_formula_book => { 'consumables' => [ fire_name ] },
                                 :pf2_features => { 'charclass_features' => [ 'Advanced Alchemy', 'Versatile Vials' ] })
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
        @char.update(:hp => @hp)
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14) }
        @toolkit = Pf2egear.create_item(@char, 'gear', Alchemy::TOOLKIT, 1, Global.read_config('pf2e_gear', Alchemy::TOOLKIT))
        @encounter = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
        Combatants.join(@encounter, @char.name, 10, :holder => Character[@char.id])
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete
        PF2Consumable.find(:character_id => @char.id).each(&:delete)
        Character[@char.id].gear.each(&:delete)
        Character[@char.id].combat&.delete
        (@abilities + [ @hp, @char ]).each(&:delete)
      end

      def char
        Character[@char.id]
      end

      def fire_name
        "Alchemist's Fire (Lesser)"
      end

      def standing
        CombatantStates.of(PF2Encounter[@encounter.id], Character[@char.id])
      end

      def prepare(name = "alchemist's fire (lesser)", many = 2)
        Alchemy.prepare!(char, name, many)
      end

      def fires(holder = standing)
        holder.consumables.to_a.select { |one| one.name == fire_name }
      end

      describe "the allowances" do
        it "should give an alchemist 4 + Intelligence prepared items and 2 + Intelligence vials" do
          expect(Alchemy.allowances(char)).to include('prepared' => 6, 'vials' => 4, 'gathers' => true)
        end

        it "should give a vial of the highest type their level reaches" do
          expect([ 1, 3, 4, 11, 12, 18, 20 ].map { |level| Alchemy.vial_name(level) })
            .to eq [ 'Versatile Vial (Lesser)', 'Versatile Vial (Lesser)', 'Versatile Vial (Moderate)',
                     'Versatile Vial (Moderate)', 'Versatile Vial (Greater)', 'Versatile Vial (Major)',
                     'Versatile Vial (Major)' ]
        end

        it "should refuse anyone who is not an alchemist" do
          char.update(:pf2_base_info => { 'charclass' => 'Fighter' })

          expect(prepare.code).to eq :not_alchemist
        end
      end

      describe "the list" do
        it "should take what they plan to make, up to what their preparations make" do
          expect(prepare.ok?).to be true
          expect(Alchemy.plan(char)).to eq(fire_name => 2)

          expect(prepare("alchemist's fire (lesser)", 5).code).to eq :too_many
        end

        it "should refuse what is not an alchemical consumable, what is too high a level, and what they cannot make" do
          expect(prepare('gecko potion', 1).code).to eq :not_alchemical
          expect(prepare("alchemist's fire (greater)", 1).code).to eq :too_high
          expect(prepare('acid flask (lesser)', 1).code).to eq :no_formula
        end

        it "should never offer a versatile vial, which is made, not prepared" do
          expect(prepare('versatile vial (lesser)', 1).err?).to be true
        end
      end

      describe "at a rest" do
        before(:each) { prepare }

        it "should make what was prepared, to last until the next preparations" do
          made = Pf2e.rest(standing)

          fire = fires.first
          expect(fire.quantity).to eq 2
          expect([ fire.granted_by, fire.expires ]).to eq [ 'advanced alchemy', 'rest' ]
          expect(made.map { |one| one['key'] }).to include('pf2e.alchemy_prepared')
        end

        it "should give the day's vials, apart from the list" do
          Pf2e.rest(standing)

          expect(Alchemy.left(standing)).to eq 4
          expect(Alchemy.vials(standing).map { |one| [ one.name, one.expires ] }).to eq [ [ 'Versatile Vial (Lesser)', 'rest' ] ]
        end

        it "should let what it made lapse at the next rest, and make it again" do
          Pf2e.rest(standing)
          Pf2e.rest(standing)

          expect(fires.map(&:quantity)).to eq [ 2 ]
        end

        it "should give back the vials Quick Alchemy spent" do
          Alchemy.quick!(standing, "alchemist's fire (lesser)")
          Pf2e.rest(standing)

          expect(Alchemy.left(standing)).to eq 4
        end

        # A list written before the cap was lowered: the rest makes what fits, in the list's own order.
        it "should make what fits of a list past the cap, and say what was left off" do
          char.update(:pf2_alchemy_plan => { fire_name => 8 })

          made = Pf2e.rest(standing)

          expect(fires.first.quantity).to eq 6
          expect(made.map { |one| one['key'] }).to include('pf2e.alchemy_left_off')
        end
      end

      describe "Quick Alchemy" do
        it "should spend a vial for one item, until their next turn" do
          made = Alchemy.quick!(standing, "alchemist's fire (lesser)")

          expect(made.ok?).to be true
          expect(fires.map { |one| [ one.quantity, one.expires ] }).to eq [ [ 1, 'turn' ] ]
          expect(Alchemy.left(standing)).to eq 3

          Turns.turn_started(PF2Encounter[@encounter.id], @char.name, 2)

          expect(fires).to eq []
        end

        it "should refuse once the vials are gone" do
          4.times { Alchemy.quick!(standing, "alchemist's fire (lesser)") }

          expect(Alchemy.quick!(standing, "alchemist's fire (lesser)").code).to eq :no_vials_left
        end

        it "should need an alchemist's toolkit carried outside a bag" do
          standing.gear.to_a.each(&:delete)

          expect(Alchemy.quick!(standing, "alchemist's fire (lesser)").code).to eq :no_toolkit
        end

        it "should make one item at a time, and two with Double Brew, a vial each" do
          two = [ "alchemist's fire (lesser)", "alchemist's fire (lesser)" ]

          expect(Alchemy.quick!(standing, two).code).to eq :too_many_at_once

          char.update(:pf2_features => { 'charclass_features' => [ 'Advanced Alchemy', 'Versatile Vials', 'Double Brew' ] })

          expect(Alchemy.quick!(standing, two).state).to eq [ fire_name, fire_name ]
          expect(Alchemy.left(standing)).to eq 2
        end

        it "should refuse two items when only one vial is left" do
          char.update(:pf2_features => { 'charclass_features' => [ 'Advanced Alchemy', 'Versatile Vials', 'Double Brew' ] })
          3.times { Alchemy.quick!(standing, "alchemist's fire (lesser)") }

          expect(Alchemy.quick!(standing, [ "alchemist's fire (lesser)", "alchemist's fire (lesser)" ]).code).to eq :no_vials_left
        end
      end

      describe "a Quick Vial" do
        def quick_vials
          standing.consumables.to_a.select { |one| one.granted_by == Alchemy::QUICK_VIAL }
        end

        it "should make a vial that spends nothing and lasts until the end of the turn" do
          made = Alchemy.quick_vial!(standing)

          expect(made.state).to eq 'Versatile Vial (Lesser)'
          expect(quick_vials.map { |one| [ one.quantity, one.expires ] }).to eq [ [ 1, 'turn_end' ] ]
          expect(Alchemy.left(standing)).to eq 4

          Turns.turn_ended(PF2Encounter[@encounter.id], @char.name, 1)

          expect(quick_vials).to eq []
        end

        it "should never be fuel for Quick Alchemy" do
          4.times { Alchemy.quick!(standing, "alchemist's fire (lesser)") }
          Alchemy.quick_vial!(standing)

          expect(Alchemy.quick!(standing, "alchemist's fire (lesser)").code).to eq :no_vials_left
        end
      end

      # Gathering reagents in exploration, which the GM calls with encounter/gather.
      describe "gathering vials" do
        def spend(count)
          count.times { Alchemy.quick!(standing, "alchemist's fire (lesser)") }
        end

        it "should give back 2 vials for each 10 minutes, up to the maximum" do
          spend(3)

          expect(Alchemy.gather!(standing).state).to eq('gained' => 2, 'left' => 3)
          expect(Alchemy.gather!(standing, 3).state).to eq('gained' => 1, 'left' => 4)
        end

        it "should give 3 a period with Alchemical Expertise" do
          char.update(:pf2_features => { 'charclass_features' => [ 'Advanced Alchemy', 'Versatile Vials', 'Alchemical Expertise' ] })
          spend(4)

          expect(Alchemy.gather!(standing).state['gained']).to eq 3
        end

        it "should refuse an alchemist whose vials are all there" do
          expect(Alchemy.gather!(standing).code).to eq :full
        end

        it "should refuse an archetype alchemist, who can't regain vials during the day" do
          char.update(:pf2_base_info => { 'charclass' => 'Fighter' }, :pf2_feats => { 'charclass' => [ 'Alchemist Dedication' ] })
          spend(2)

          expect(Alchemy.gather!(standing).code).to eq :cannot_gather
        end
      end

      # Powerful Alchemy: what an alchemist makes carries their class DC, which a save against it uses where
      # it is higher than the item's own.
      describe "Powerful Alchemy" do
        before(:each) do
          combat = Pf2eCombat.create(:character => @char, :class_dc => 'trained', :weapon_prof => { 'martial' => 'trained' },
                                     :unarmed_attacks => {})
          @char.update(:combat => combat)
          prepare
        end

        def with_feature
          char.update(:pf2_features => { 'charclass_features' => [ 'Advanced Alchemy', 'Versatile Vials', 'Powerful Alchemy' ] })
        end

        it "should stamp nothing without the feature" do
          Pf2e.rest(standing)

          expect(fires.map(&:dc)).to eq [ 0 ]
        end

        it "should stamp their class DC on what they prepare and what Quick Alchemy makes" do
          with_feature
          Pf2e.rest(standing)
          Alchemy.quick!(standing, "alchemist's fire (lesser)")

          dc = Stat.total(char, 'class_dc')

          expect(dc).to be > 0
          expect(fires.map(&:dc)).to eq [ dc, dc ]
        end

        it "should carry the stamp onto a bomb's Strike" do
          with_feature
          Pf2e.rest(standing)

          thrown = Actors.of(standing).attacks.find { |names, _attack| names.include?(fire_name) }.last

          expect(thrown['maker_dc']).to eq Stat.total(char, 'class_dc')
        end

        it "should tell a note's save at the higher of the two DCs" do
          notes = [ { 'text' => 'Creatures within 10 feet must succeed at a DC 17 Fortitude save or be Deafened.' } ]

          expect(Consumables.at_makers_dc(notes, 22).first['text']).to include 'DC 22 Fortitude'
          expect(Consumables.at_makers_dc(notes, 15).first['text']).to include 'DC 17 Fortitude'
          expect(Consumables.at_makers_dc(notes, nil)).to eq notes
        end
      end

      # Quick Alchemy's limit: an effect from what it made lasts at most 10 minutes.
      describe "the 10-minute limit" do
        it "should cut an effect longer than 10 minutes, and only from Quick Alchemy" do
          expect(Consumables.quick_cap('Effect: Eagle Eye Elixir', Alchemy::QUICK)).to eq('unit' => 'minutes', 'value' => 10)
          expect(Consumables.quick_cap('Effect: Eagle Eye Elixir', Alchemy::PREPARED)).to be_nil
          expect(Consumables.quick_cap('Effect: Elixir of Life', Alchemy::QUICK)).to be_nil
          expect(Consumables.quick_cap("Effect: Cheetah's Elixir (Lesser)", Alchemy::QUICK)).to be_nil
        end

        it "should apply what Quick Alchemy made for 10 minutes" do
          Consumables.take(PF2Encounter[@encounter.id], @char.name, Combatants.find(PF2Encounter[@encounter.id], @char.name).state,
                           'Eagle Eye Elixir (Lesser)', :made_by => Alchemy::QUICK)

          effect = ActiveEffects.on(standing).find { |one| one.name == 'Effect: Eagle Eye Elixir' }

          expect([ effect.unit, effect.duration ]).to eq [ 'minutes', 10 ]
        end
      end

      # Abundant Vials, and the paragon feats like it, are quickened for good, by their own rule.
      it "should keep an alchemist with Abundant Vials quickened" do
        char.update(:pf2_features => { 'charclass_features' => [ 'Advanced Alchemy', 'Versatile Vials', 'Abundant Vials' ] })

        expect(Pf2e.held_conditions(char)).to have_key('Quickened')
      end

      describe "a versatile vial" do
        it "should be a bomb they can throw" do
          combat = Pf2eCombat.create(:character => @char, :weapon_prof => { 'martial' => 'trained' }, :unarmed_attacks => {})
          @char.update(:combat => combat)

          thrown = Actors.of(standing).attacks.find { |names, _attack| names.include?('Versatile Vial (Lesser)') }

          expect(thrown).to_not be_nil
          expect(thrown.last.values_at('damage_type', 'splash')).to eq [ 'acid', 1 ]
        end

        it "should be for sale nowhere, and have no formula" do
          expect(Crafting.pool(char, 'traits' => [ 'bomb' ], 'max_level' => 20)).to_not include('Versatile Vial (Lesser)')
          expect(Crafting.entry('consumables', 'Versatile Vial (Lesser)').err?).to be true
        end
      end

      # What is made is its own, beside anything of the same name they already hold: it goes when its time
      # is up and takes nothing else with it.
      describe "what alchemy made, beside what they already hold" do
        it "should leave what they prepared when what Quick Alchemy made is gone" do
          prepare
          Pf2e.rest(standing)
          Alchemy.quick!(standing, "alchemist's fire (lesser)")

          Turns.turn_started(PF2Encounter[@encounter.id], @char.name, 2)

          expect(fires.map { |one| [ one.quantity, one.expires ] }).to eq [ [ 2, 'rest' ] ]
        end

        it "should throw what will not last before what will" do
          combat = Pf2eCombat.create(:character => @char, :weapon_prof => { 'martial' => 'trained' }, :unarmed_attacks => {})
          @char.update(:combat => combat)
          prepare
          Pf2e.rest(standing)
          Alchemy.quick!(standing, "alchemist's fire (lesser)")

          thrown = Actors.of(standing).attacks.find { |names, _attack| names.include?(fire_name) }.last
          quick = fires.find { |one| one.expires == 'turn' }

          expect(thrown['consumable']).to eq quick.id.to_s
        end

        describe "when it is something they own" do
          before(:each) do
            @own = PF2Consumable.create(:name => fire_name, :quantity => 2, :character => @char)
            @later = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
            Combatants.join(PF2Encounter[@later.id], @char.name, 10, :holder => Character[@char.id])
          end

          after(:each) { PF2Encounter[@later.id]&.delete }

          def there
            CombatantStates.of(PF2Encounter[@later.id], Character[@char.id])
          end

          it "should leave their own, and take none of it from them when the encounter ends" do
            Alchemy.quick!(there, "alchemist's fire (lesser)")
            Turns.turn_started(PF2Encounter[@later.id], @char.name, 2)

            expect(fires(there).map { |one| [ one.quantity, one.expires ] }).to eq [ [ 2, nil ] ]

            Equipment.settle!(there)

            expect(PF2Consumable[@own.id].quantity).to eq 2
          end
        end
      end

      # Someone who joins fresh joins rested, and a rest is when an alchemist's vials and prepared items are
      # made.
      describe "joining an encounter fresh" do
        before(:each) { @other = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true) }

        after(:each) { PF2Encounter[@other.id]&.delete }

        def joined
          Combatants.join(PF2Encounter[@other.id], @char.name, 10, :holder => Character[@char.id])
          CombatantStates.of(PF2Encounter[@other.id], Character[@char.id])
        end

        it "should start an alchemist with the day's vials" do
          expect(Alchemy.left(joined)).to eq 4
        end

        it "should leave on their sheet nothing of what it made, however many encounters they join" do
          prepare

          3.times do
            later = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
            Combatants.join(PF2Encounter[later.id], @char.name, 10, :holder => Character[@char.id])
            state = CombatantStates.of(PF2Encounter[later.id], Character[@char.id])

            expect(fires(state).map(&:quantity)).to eq [ 2 ]

            Encounters::Ending.end!(PF2Encounter[later.id])
            PF2Encounter[later.id].delete
          end

          expect(PF2Consumable.find(:character_id => @char.id).to_a).to eq []
        end

        it "should clear from their sheet what an earlier day's preparations left there" do
          stale = PF2Consumable.create(:name => fire_name, :quantity => 2, :character => @char,
                                       :granted_by => 'advanced alchemy', :expires => 'rest')

          state = joined
          expect(fires(state)).to eq []

          Encounters::Ending.end!(PF2Encounter[@other.id])
          expect(PF2Consumable[stale.id]).to be_nil
        end

        it "should start them with what they prepared, leaving their vials whole" do
          prepare

          fire = fires(joined).first
          expect([ fire&.quantity, fire&.expires ]).to eq [ 2, 'rest' ]
          expect(Alchemy.left(joined)).to eq 4
        end
      end

      describe "what the day holds" do
        it "should be what a rest would give, for someone in no encounter" do
          expect(Alchemy.day(char)).to eq('vials' => 4, 'left' => 4, 'prepared' => 6)
        end

        it "should be what they have left, for someone in an encounter" do
          Alchemy.quick!(standing, "alchemist's fire (lesser)")

          expect(Alchemy.day(standing)).to eq('vials' => 4, 'left' => 3, 'prepared' => 6)
        end
      end

      describe "the alchemy screen" do
        before(:each) { @client = AutoBuilder::CaptureClient.new }

        def shown
          PF2AlchemyViewCmd.new(@client, Command.new('alchemy'), char).on_command
          @client.successes.join("\n")
        end

        it "should show an alchemist in no encounter what a rest gives them" do
          expect(shown).to include('4 versatile vials a day', 'up to 6 items')
        end

        it "should list what is on their preparations" do
          prepare

          expect(shown).to include("2 #{fire_name}")
        end

        it "should say so where nothing is on the list" do
          expect(shown).to include(t('pf2e.alchemy_nothing_planned').strip)
        end

        it "should show someone in an encounter what they have left and what they made today" do
          prepare
          Pf2e.rest(standing)
          Alchemy.quick!(standing, "alchemist's fire (lesser)")

          screen = PF2AlchemyTemplate.new(standing, @client).render

          expect(screen).to include('3 left today',
                                    t('pf2e.alchemy_made_rest', :item => fire_name, :many => 2),
                                    t('pf2e.alchemy_made_turn', :item => fire_name, :many => 1))
        end
      end

      # The Alchemist archetype's allowances are separate: Alchemist Dedication's 4 versatile vials, and the
      # archetype's Advanced Alchemy's 4 prepared items.
      describe "an alchemist by the archetype" do
        def archetype(feats)
          char.update(:pf2_level => 4, :pf2_base_info => { 'charclass' => 'Fighter' },
                      :pf2_features => { 'charclass_features' => [] }, :pf2_feats => { 'charclass' => feats })
          char
        end

        it "should give the dedication 4 vials, and nothing to prepare" do
          archetype([ 'Alchemist Dedication' ])

          expect(Alchemy.alchemist?(char)).to be true
          expect(Alchemy.allowances(char)).to include('vials' => 4, 'prepared' => 0, 'gathers' => false)
          expect(prepare.code).to eq :cannot_prepare

          Pf2e.rest(standing)

          expect(Alchemy.left(standing)).to eq 4
          expect(Alchemy.vials(standing).first.name).to eq 'Versatile Vial (Moderate)'
          expect(Alchemy.quick!(standing, "alchemist's fire (lesser)").ok?).to be true
          expect(Alchemy.left(standing)).to eq 3
        end

        it "should let Advanced Alchemy prepare 4 items, apart from the vials" do
          archetype([ 'Alchemist Dedication', 'Advanced Alchemy' ])

          expect(prepare("alchemist's fire (lesser)", 4).ok?).to be true
          expect(prepare("alchemist's fire (lesser)", 1).code).to eq :too_many
          expect(Alchemy.day(char)).to eq('vials' => 4, 'left' => 4, 'prepared' => 4)

          Pf2e.rest(standing)

          expect(fires.first.quantity).to eq 4
          expect(Alchemy.left(standing)).to eq 4
        end

        it "should say the two allowances on the alchemy screen" do
          archetype([ 'Alchemist Dedication', 'Advanced Alchemy' ])

          screen = PF2AlchemyTemplate.new(char).render

          expect(screen).to include('4 versatile vials a day', 'up to 4 items')
        end
      end
    end
  end
end
