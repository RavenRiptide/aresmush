require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A familiar's statistics, worked out from its master (Player Core p. 212). The witch here is the one in
    # the approved sheet mockup: level 6, Intelligence 18, Night patron.
    describe "a familiar's statistics", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Morwen#{rand(1000000)}")
        @combat = Pf2eCombat.create(:character => @char, :key_abil => 'Intelligence', :perception => 'trained',
                                    :armor_prof => { 'unarmored' => 'trained' },
                                    :saves => { 'Fortitude' => 'trained', 'Reflex' => 'trained', 'Will' => 'expert' })
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 6, :charclass_hp => 6)
        @char.update(:combat => @combat, :hp => @hp, :pf2_level => 6, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_derived => {}, :pf2_feats => {},
                     :pf2_base_info => { 'charclass' => 'Witch', 'specialize' => 'Night' },
                     :pf2_features => { 'charclass_features' => [ 'Familiar' ] })
        @abilities = Pf2e::ABILITIES.map do |name|
          Pf2eAbilities.create(:character => @char, :name => name, :base_val => name == 'Intelligence' ? 18 : 12)
        end
      end

      after(:each) do
        @abilities.each(&:delete)
        @hp.delete
        @combat.delete
        @char.delete
      end

      def master
        Character[@char.id]
      end

      def stats(*abilities, **options)
        Familiar::Stats.of(master, abilities.map { |one| one.is_a?(Hash) ? one : { 'name' => one } }, **options)
      end

      def score(ability, value)
        @abilities.find { |one| one.name == ability }.update(:base_val => value)
      end

      it "should be nothing for a character with no familiar" do
        @char.update(:pf2_features => { 'charclass_features' => [] })

        expect(stats).to be_nil
      end

      it "should be the master's level, with 5 Hit Points per level" do
        expect(stats['level']).to eq 6
        expect(stats['hp']).to eq 30
      end

      it "should add Tough's hit points" do
        expect(stats('Tough')['hp']).to eq 42
      end

      describe "AC and saves" do
        it "should be the master's" do
          expect(stats['ac']).to eq Stat.total(master, 'ac')
          expect(stats['saves']['Will']).to eq Stat.total(master, 'save', 'Will')
        end

        it "should not share the master's status penalties" do
          before = stats

          @char.update(:pf2_conditions => { 'Frightened' => { 'value' => 2, 'status' => true } })

          expect(Stat.total(master, 'ac')).to eq before['ac'] - 2
          expect(stats['ac']).to eq before['ac']
          expect(stats['saves']).to eq before['saves']
        end

        it "should not share the master's circumstance penalties" do
          before = stats['ac']

          @char.update(:pf2_conditions => { 'Off-Guard' => { 'status' => true } })

          expect(Stat.total(master, 'ac')).to eq before - 2
          expect(stats['ac']).to eq before
        end

        it "should be a Spellslime's own AC" do
          expect(stats(specific: 'Spellslime')['ac']).to eq 16
        end
      end

      describe "skills" do
        it "should give Perception, Acrobatics and Stealth the level plus the witch's Intelligence" do
          expect(stats['attribute']).to eq 'Intelligence'
          expect(stats['perception']).to eq 10
          expect(stats['skills']).to eq('Acrobatics' => 10, 'Stealth' => 10)
        end

        it "should use 3 where the attribute modifier is lower" do
          score('Intelligence', 12)

          expect(stats['perception']).to eq 9
        end

        it "should give a Skilled skill the level plus the attribute modifier" do
          found = stats({ 'name' => 'Skilled', 'choice' => 'Occultism' })

          expect(found['skills']['Occultism']).to eq 10
          expect(found['other_skills']).to eq 6
        end

        it "should give a pet with no spellcasting source the level plus 3" do
          @char.update(:pf2_features => { 'charclass_features' => [] }, :pf2_feats => { 'general' => [ 'Pet' ] })

          expect(stats['attribute']).to be_nil
          expect(stats['perception']).to eq 9
        end
      end

      describe "movement and senses" do
        it "should have a 25-foot land Speed and low-light vision" do
          expect(stats['speeds']).to eq('land' => 25)
          expect(stats['senses']).to eq [ 'low-light vision' ]
        end

        it "should swim and not walk in an aquatic form" do
          expect(stats(form: 'aquatic')['speeds']).to eq('swim' => 25)
          expect(stats(form: 'aquatic')['traits']).to include 'aquatic'
        end

        it "should fly with Flier, at 40 feet with Fast Movement on its fly Speed" do
          expect(stats('Flier')['speeds']).to eq('land' => 25, 'fly' => 25)
          expect(stats('Flier', { 'name' => 'Fast Movement', 'choice' => 'Fly' })['speeds']).to eq('land' => 25, 'fly' => 40)
        end

        it "should give an Aeon Wyrd no land Speed" do
          expect(stats('Construct', 'Flier', specific: 'Aeon Wyrd')['speeds']).to eq('fly' => 25)
        end

        it "should see in the dark with Darkvision" do
          expect(stats('Darkvision')['senses']).to eq [ 'low-light vision', 'darkvision' ]
        end
      end

      describe "traits" do
        it "should be a minion and an animal" do
          expect(stats['traits']).to eq %w{minion animal}
        end

        it "should be a construct instead of an animal with Construct" do
          expect(stats('Tough', 'Construct')['traits']).to eq %w{minion construct}
        end

        it "should take the chosen element with Elemental" do
          found = stats({ 'name' => 'Resistance', 'choice' => %w{fire cold} }, { 'name' => 'Elemental', 'choice' => 'Fire' })

          expect(found['traits']).to include('elemental', 'fire')
          expect(found['traits']).to_not include 'animal'
        end

        it "should take a specific familiar's traits" do
          expect(stats('Climber', specific: 'Pipefox')['traits']).to eq %w{minion beast}
        end
      end

      describe "resistances" do
        it "should resist the two chosen kinds by half its level" do
          found = stats({ 'name' => 'Resistance', 'choice' => %w{Fire Cold} })

          expect(found['resistances']).to contain_exactly({ 'type' => 'fire', 'value' => 3 }, { 'type' => 'cold', 'value' => 3 })
        end

        it "should resist them by its level with Major Resistance" do
          @char.update(:pf2_level => 8)
          found = stats({ 'name' => 'Resistance', 'choice' => %w{Fire Cold} }, 'Major Resistance')

          expect(found['resistances']).to contain_exactly({ 'type' => 'fire', 'value' => 8 }, { 'type' => 'cold', 'value' => 8 })
        end

        it "should give an Aeon Wyrd weakness to sonic equal to its level" do
          expect(stats('Construct', 'Flier', specific: 'Aeon Wyrd')['weaknesses']).to eq [ { 'type' => 'sonic', 'value' => 6 } ]
        end

        it "should give Construct's immunities" do
          expect(stats('Tough', 'Construct')['immunities']).to include('poison', 'death-effects')
        end
      end

      describe "how many abilities" do
        def count
          Paths.apply_all!(master)
          Familiar::Stats.ability_count(master)
        end

        # 2, and the witch's 2 + 1 at 6th level, less the patron's ability, which is free.
        it "should give a sixth-level witch 4 besides the patron's" do
          expect(count).to eq 4
        end

        it "should give a sixth-level witch with Enhanced Familiar 6 besides the patron's" do
          @char.update(:pf2_feats => { 'charclass' => [ 'Enhanced Familiar' ] })

          expect(count).to eq 6
        end

        it "should leave the patron out of a dedicant's count, which has none" do
          @char.update(:pf2_base_info => { 'charclass' => 'Wizard' }, :pf2_features => { 'charclass_features' => [] },
                       :pf2_feats => { 'dedication' => [ 'Witch Dedication' ] })

          expect(count).to eq 2
        end
      end

      describe "abilities it has without choosing" do
        it "should give a witch their patron's ability" do
          expect(Familiar::Stats.innate(master)).to eq('abilities' => [ 'Familiar of Stalking Night' ], 'choose' => [])
        end

        it "should give a dedicant no patron's ability" do
          @char.update(:pf2_base_info => { 'charclass' => 'Wizard' }, :pf2_features => { 'charclass_features' => [] },
                       :pf2_feats => { 'dedication' => [ 'Witch Dedication' ] })

          expect(Familiar::Stats.innate(master)['abilities']).to eq []
        end

        it "should give Alchemical Familiar its Construct, and keep it when merged into the witch's familiar" do
          @char.update(:pf2_base_info => { 'charclass' => 'Alchemist' }, :pf2_features => { 'charclass_features' => [] },
                       :pf2_feats => { 'charclass' => [ 'Alchemical Familiar' ], 'dedication' => [ 'Witch Dedication' ] })

          expect(Familiar::Stats.innate(master)['abilities']).to eq [ 'Construct' ]
        end

        it "should ask a leshy familiar's master to choose Plant or Fungus" do
          @char.update(:pf2_base_info => { 'charclass' => 'Druid', 'specialize' => 'Leaf' },
                       :pf2_features => { 'charclass_features' => [] }, :pf2_feats => { 'charclass' => [ 'Leshy Familiar' ] })

          expect(Familiar::Stats.innate(master)['choose']).to eq [ %w{Plant Fungus} ]
        end
      end
    end
  end
end
