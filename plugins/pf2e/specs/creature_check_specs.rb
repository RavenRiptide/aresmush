require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a saved creature may not be, which keeps it from being saved: everything in the database is a
    # creature the engine can fight with.
    describe CreatureCheck do

      def block(**more)
        { 'name' => 'Bandit', 'level' => 2, 'ac' => 16, 'hp' => 30, 'perception' => 6,
          'saves' => { 'fortitude' => 8, 'reflex' => 6, 'will' => 4 }, 'traits' => [],
          'strikes' => [ { 'name' => 'Club', 'bonus' => 9, 'damage' => [ [ '1d6+4', 'bludgeoning', nil ] ], 'traits' => [] } ],
          'actions' => [ { 'name' => 'Rally', 'type' => 'action', 'cost' => 1, 'traits' => [], 'text' => 'It rallies.' } ] }
          .merge(more.transform_keys(&:to_s))
      end

      def codes(held)
        CreatureCheck.errors(held).map { |one| one['code'] }
      end

      it "should find nothing wrong with a creature the engine can fight" do
        expect(CreatureCheck.errors(block)).to eq []
      end

      ROWS = [
        [ 'no AC', { 'ac' => nil }, :creature_needs ],
        [ 'no Hit Points', { 'hp' => 0 }, :creature_needs ],
        [ 'a level out of the bestiary', { 'level' => 26 }, :creature_level ],
        [ 'a Strike with no damage', { 'strikes' => [ { 'name' => 'Club', 'bonus' => 9, 'damage' => [] } ] }, :creature_strike_damage ],
        [ 'a damage formula the game cannot read', { 'strikes' => [ { 'name' => 'Club', 'bonus' => 9, 'damage' => [ [ '1d6+', 'bludgeoning', nil ] ] } ] }, :creature_formula ],
        [ 'a Strike with no name', { 'strikes' => [ { 'name' => ' ', 'bonus' => 9, 'damage' => [ [ '1d6', 'bludgeoning', nil ] ] } ] }, :creature_unnamed ],
        [ 'an ability with no words', { 'actions' => [ { 'name' => 'Rally', 'type' => 'action', 'cost' => 1, 'text' => '' } ] }, :creature_ability_text ],
        [ 'an action costing four', { 'actions' => [ { 'name' => 'Rally', 'type' => 'action', 'cost' => 4, 'text' => 'x' } ] }, :creature_ability_cost ],
        [ 'two Strikes of one name', { 'strikes' => [ { 'name' => 'Club', 'bonus' => 9, 'damage' => [ [ '1d6', 'bludgeoning', nil ] ] },
                                                      { 'name' => 'club', 'bonus' => 7, 'damage' => [ [ '1d4', 'bludgeoning', nil ] ] } ] }, :creature_twice ]
      ].freeze

      ROWS.each do |what, change, code|
        it "should refuse #{what}" do
          expect(codes(block(**change.transform_keys(&:to_sym)))).to include(code)
        end
      end

      describe "a name" do
        def name(words, bestiary = [])
          CreatureCheck.name(words, ->(term) { bestiary.find { |one| one.casecmp?(term) } })
        end

        it "should be taken as it is" do
          expect(name('Barrow Hound').state).to eq 'Barrow Hound'
        end

        NAMES = [ [ '', :creature_name_empty ], [ 'Barrow=Hound', :creature_name_mark ], [ 'Bar;row', :creature_name_mark ],
                  [ 'Hound #2', :creature_name_mark ], [ 'Hound/Elite', :creature_name_mark ], [ '3 Hounds', :creature_name_count ],
                  [ 'elite hound', :creature_name_adjusted ], [ 'c:hound', :creature_name_mark ], [ 'x' * 61, :creature_name_long ] ].freeze

        NAMES.each do |words, code|
          it "should refuse #{words[0, 20].inspect}" do
            expect(name(words).code).to eq code
          end
        end

        it "should refuse a bestiary creature's name, which the bestiary keeps" do
          expect(name('goblin warrior', [ 'Goblin Warrior' ]).code).to eq :creature_name_bestiary
        end
      end
    end
  end
end
