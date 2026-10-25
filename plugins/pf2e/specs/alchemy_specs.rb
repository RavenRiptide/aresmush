require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # An alchemist's preparations: a list on the sheet, made into the day's items by a rest, with what is
    # left over spent on Quick Alchemy in an encounter.
    describe Alchemy, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Alch#{rand(1000000)}", :pf2_level => 3, :pf2_conditions => {},
                                 :pf2_reagents => { 'alchemist' => [ 3, 0, 3 ] }, :pf2_alchemy_plan => {},
                                 :pf2_formula_book => { 'consumables' => [ "Alchemist's Fire (Lesser)" ] },
                                 :pf2_features => { 'charclass_features' => [ 'Advanced Alchemy' ] })
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
        @char.update(:hp => @hp)
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14) }
        @encounter = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
        Combatants.join(@encounter, @char.name, 10, :holder => Character[@char.id])
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete
        PF2Consumable.find(:character_id => @char.id).each(&:delete)
        Character[@char.id].combat&.delete
        (@abilities + [ @hp, @char ]).each(&:delete)
      end

      def char
        Character[@char.id]
      end

      def standing
        CombatantStates.of(PF2Encounter[@encounter.id], Character[@char.id])
      end

      def prepare(name = "alchemist's fire (lesser)", many = 2)
        Alchemy.prepare!(char, name, many)
      end

      it "should take what they plan to make, and say what their reagents allow" do
        expect(prepare.ok?).to be true
        expect(Alchemy.plan(char)).to eq("Alchemist's Fire (Lesser)" => 2)

        expect(prepare("alchemist's fire (lesser)", 9).code).to eq :no_reagents
      end

      # What their reagents will make is their level and Intelligence, whether or not they have rested
      # since they gained them.
      it "should plan against what their reagents will make, before they have ever rested" do
        char.update(:pf2_reagents => { 'alchemist' => [ 0, 0, 0 ] }, :pf2_base_info => { 'charclass' => 'Alchemist' })

        expect(Alchemy.capacity(char)).to eq 5
        expect(prepare("alchemist's fire (lesser)", 10).ok?).to be true
        expect(prepare("alchemist's fire (lesser)", 1).code).to eq :no_reagents
      end

      it "should give an alchemist their level and Intelligence in batches at a rest" do
        char.update(:pf2_base_info => { 'charclass' => 'Alchemist' })

        Pf2e.rest(standing)

        expect(Alchemy.batches(standing)).to eq 5
      end

      # An alchemist is one by their class's Advanced Alchemy, whether or not anything recorded their reagents.
      it "should give an alchemist reagents at a rest though none were recorded" do
        char.update(:pf2_reagents => {}, :pf2_base_info => { 'charclass' => 'Alchemist' })
        standing.update(:pf2_reagents => {})

        Pf2e.rest(standing)

        expect(Alchemy.batches(standing)).to eq 5
        expect(Alchemy.left(standing)).to eq 5
      end

      it "should refuse what is not alchemical, what is too high a level, and what they cannot make" do
        expect(prepare('gecko potion', 1).code).to eq :not_alchemical
        expect(prepare("alchemist's fire (greater)", 1).code).to eq :too_high
        expect(prepare('acid flask (lesser)', 1).code).to eq :no_formula
      end

      it "should refuse anyone who is not an alchemist" do
        char.update(:pf2_reagents => {}, :pf2_features => { 'charclass_features' => [] })

        expect(prepare.code).to eq :not_alchemist
      end

      describe "at a rest" do
        before(:each) { prepare }

        it "should make what was prepared, to last until the next preparations" do
          made = Pf2e.rest(standing)

          fire = standing.consumables.to_a.find { |one| one.name == "Alchemist's Fire (Lesser)" }
          expect(fire.quantity).to eq 2
          expect([ fire.granted_by, fire.expires ]).to eq [ 'advanced alchemy', 'rest' ]
          expect(made.map { |one| one['key'] }).to include('pf2e.alchemy_prepared')
        end

        it "should spend the reagents it took, leaving the rest for Quick Alchemy" do
          Pf2e.rest(standing)

          expect(Alchemy.left(standing)).to eq 2
        end

        it "should let what it made lapse at the next rest, and make it again" do
          Pf2e.rest(standing)
          Pf2e.rest(standing)

          fire = standing.consumables.to_a.select { |one| one.name == "Alchemist's Fire (Lesser)" }
          expect(fire.map(&:quantity)).to eq [ 2 ]
        end
      end

      describe "Quick Alchemy" do
        it "should make one on the spot, spending a batch, until their next turn" do
          made = Alchemy.quick!(standing, "alchemist's fire (lesser)")

          expect(made.ok?).to be true
          fire = standing.consumables.to_a.find { |one| one.name == "Alchemist's Fire (Lesser)" }
          expect([ fire.quantity, fire.expires ]).to eq [ 1, 'turn' ]
          expect(Alchemy.left(standing)).to eq 2

          Turns.turn_started(PF2Encounter[@encounter.id], @char.name, 2)

          expect(standing.consumables.to_a).to eq []
        end

        it "should refuse once the day's reagents are gone" do
          3.times { Alchemy.quick!(standing, "alchemist's fire (lesser)") }

          expect(Alchemy.quick!(standing, "alchemist's fire (lesser)").code).to eq :no_reagents_left
        end
      end

      # What reagents make is its own, beside anything of the same name they already hold: it goes when its
      # time is up and takes nothing else with it.
      describe "what is made of reagents, beside what they already hold" do
        def fires(holder = standing)
          holder.consumables.to_a.select { |one| one.name == "Alchemist's Fire (Lesser)" }
        end

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

          thrown = Actors.of(standing).attacks.find { |names, _attack| names.include?("Alchemist's Fire (Lesser)") }.last
          quick = fires.find { |one| one.expires == 'turn' }

          expect(thrown['consumable']).to eq quick.id.to_s
        end

        describe "when it is something they own" do
          before(:each) do
            @own = PF2Consumable.create(:name => "Alchemist's Fire (Lesser)", :quantity => 2, :character => @char)
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

      # Someone who joins fresh joins rested, and a rest is when an alchemist's reagents and preparations
      # are made.
      describe "joining an encounter fresh" do
        before(:each) do
          char.update(:pf2_reagents => {}, :pf2_base_info => { 'charclass' => 'Alchemist' })
          @other = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
        end

        after(:each) { PF2Encounter[@other.id]&.delete }

        def joined
          Combatants.join(PF2Encounter[@other.id], @char.name, 10, :holder => Character[@char.id])
          CombatantStates.of(PF2Encounter[@other.id], Character[@char.id])
        end

        it "should start an alchemist with the day's reagents, though none were recorded" do
          expect([ Alchemy.batches(joined), Alchemy.left(joined) ]).to eq [ 5, 5 ]
        end

        it "should leave on their sheet nothing of what it made, however many encounters they join" do
          prepare

          3.times do
            later = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
            Combatants.join(PF2Encounter[later.id], @char.name, 10, :holder => Character[@char.id])
            state = CombatantStates.of(PF2Encounter[later.id], Character[@char.id])

            expect(state.consumables.to_a.map(&:quantity)).to eq [ 2 ]

            Encounters::Ending.end!(PF2Encounter[later.id])
            PF2Encounter[later.id].delete
          end

          expect(PF2Consumable.find(:character_id => @char.id).to_a).to eq []
        end

        it "should clear from their sheet what an earlier day's preparations left there" do
          stale = PF2Consumable.create(:name => "Alchemist's Fire (Lesser)", :quantity => 2, :character => @char,
                                       :granted_by => 'advanced alchemy', :expires => 'rest')

          state = joined
          expect(state.consumables.to_a).to eq []

          Encounters::Ending.end!(PF2Encounter[@other.id])
          expect(PF2Consumable[stale.id]).to be_nil
        end

        it "should start them with what they prepared, made of those reagents" do
          prepare

          fire = joined.consumables.to_a.find { |one| one.name == "Alchemist's Fire (Lesser)" }
          expect([ fire&.quantity, fire&.expires ]).to eq [ 2, 'rest' ]
          expect(Alchemy.left(joined)).to eq 4
        end
      end

      describe "what the day holds" do
        before(:each) { char.update(:pf2_reagents => {}, :pf2_base_info => { 'charclass' => 'Alchemist' }) }

        it "should be what a rest would give, for someone in no encounter" do
          expect(Alchemy.day(char)).to eq('batches' => 5, 'items' => 10, 'left' => 5)
        end

        it "should leave of it what their list will not take" do
          prepare("alchemist's fire (lesser)", 3)

          expect(Alchemy.day(char)).to eq('batches' => 5, 'items' => 10, 'left' => 3)
        end

        it "should be what they have left, for someone in an encounter" do
          Pf2e.rest(standing)
          Alchemy.quick!(standing, "alchemist's fire (lesser)")

          expect(Alchemy.day(standing)).to eq('batches' => 5, 'items' => 10, 'left' => 4)
        end
      end

      describe "the alchemy screen" do
        before(:each) do
          char.update(:pf2_reagents => {}, :pf2_base_info => { 'charclass' => 'Alchemist' })
          @client = AutoBuilder::CaptureClient.new
        end

        def shown
          PF2AlchemyViewCmd.new(@client, Command.new('alchemy'), char).on_command
          @client.successes.join("\n")
        end

        it "should show an alchemist in no encounter what a rest gives them" do
          expect(shown).to include('5 batches', '10 items a day', '5 batches for Quick Alchemy')
        end

        it "should list what is on their preparations" do
          prepare

          expect(shown).to include("2 Alchemist's Fire (Lesser)")
        end

        it "should say so where nothing is on the list" do
          expect(shown).to include(t('pf2e.alchemy_nothing_planned').strip)
        end

        it "should show someone in an encounter what they have left and what they made today" do
          prepare
          Pf2e.rest(standing)
          Alchemy.quick!(standing, "alchemist's fire (lesser)")

          screen = PF2AlchemyTemplate.new(standing, @client).render

          expect(screen).to include('5 batches', '3 batches left today',
                                    t('pf2e.alchemy_made_rest', :item => "Alchemist's Fire (Lesser)", :many => 2),
                                    t('pf2e.alchemy_made_turn', :item => "Alchemist's Fire (Lesser)", :many => 1))
        end
      end
    end
  end
end
