require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The animal companion catalogue, and the statistics Player Core gives a companion at each stage.
    # Each expected number is worked by hand from Player Core pp. 206-211.
    describe "animal companions" do

      before(:all) do
        @catalogue = YAML.load_file('game/config/pf2e_animal_companions.yml')['pf2e_animal_companions']
        @gear = YAML.load_file('game/config/pf2e_gear.yml')['pf2e_gear']
      end

      def stats(type, level, barding: nil, **companion)
        held = { 'type' => type }.merge(companion.transform_keys(&:to_s))
        armor = barding ? { 'name' => barding, 'companion_armor' => @gear[barding]['companion_armor'] } : nil

        Companion::Stats.of(held, :level => level, :barding => armor, :catalogue => @catalogue)
      end

      def skill(out, name)
        out['skills'][name]['value']
      end

      describe "the catalogue" do
        it "should hold Player Core's sixteen types" do
          expect(@catalogue['types'].keys.sort).to eq [ 'Ape', 'Arboreal Sapling', 'Badger', 'Bat', 'Bear', 'Bird', 'Boar',
                                                       'Cat', 'Crocodile', 'Dromaeosaur', 'Horse', 'Riding Drake',
                                                       'Scorpion', 'Shark', 'Snake', 'Wolf' ]
          expect(@catalogue['types'].values.map { |info| info['source'] }.uniq).to eq [ 'Player Core' ]
        end

        it "should give every type its stat block, support benefit and advanced maneuver" do
          bad = @catalogue['types'].reject do |_name, info|
            info['hp'].to_i.positive? && !info['attacks'].blank? && !info['speeds'].blank? && !info['support'].blank? &&
              !info['maneuver']['name'].blank? && !info['maneuver']['description'].blank? &&
              Companion::Stats::SKILLS.key?(info['skill'])
          end

          expect(bad.keys).to be_empty
        end

        # The mature stage's "expert if it was already trained from its type" assumes it.
        it "should give every type a skill the mature stage trains" do
          trained = @catalogue['stages']['mature']['trained']

          expect(@catalogue['types'].values.map { |info| info['skill'] } - trained).to be_empty
        end

        it "should leave Arboreal Sapling to the leaf order and Riding Drake to staff" do
          uncommon = @catalogue['types'].select { |_name, info| info['rarity'] == 'uncommon' }

          expect(uncommon.keys.sort).to eq [ 'Arboreal Sapling', 'Riding Drake' ]
          expect(uncommon['Arboreal Sapling']['access']).to eq('specialize' => 'leaf')
          expect(uncommon['Riding Drake']['access']).to be_nil
        end

        it "should let a Horse be Medium or Large, and no other type choose" do
          sized = @catalogue['types'].select { |_name, info| info['sizes'] }

          expect(sized.transform_values { |info| info['sizes'] }).to eq('Horse' => [ 'Medium', 'Large' ])
        end

        it "should hold the six specializations and Auspice, each described" do
          expect(@catalogue['specializations'].keys.sort).to eq %w{Ambusher Auspice Bully Daredevil Racer Tracker Wrecker}
          expect(@catalogue['specializations'].values.map { |info| info['description'] }).to all(be_present)
          expect(@catalogue['specializations']['Auspice']['only_for']).to eq [ 'Auspicious Mount' ]
        end

        it "should describe every stage" do
          expect(@catalogue['stages'].keys).to eq %w{young mature nimble savage specialized}
          expect(@catalogue['stages'].values.map { |info| info['description'] }).to all(be_present)
        end
      end

      describe "a young wolf at level 1" do
        before(:all) { @out = stats('Wolf', 1) }

        it "should take its type's numbers and the young companion's proficiencies" do
          expect(@out.values_at('stage', 'size', 'hp', 'ac', 'perception')).to eq [ 'young', 'Small', 14, 16, 4 ]
          expect(@out['saves']).to eq('Fortitude' => 5, 'Reflex' => 6, 'Will' => 4)
        end

        it "should be trained in Acrobatics, Athletics and its type's skill" do
          expect(@out['skills'].transform_values { |one| one['value'] }).to eq('Acrobatics' => 6, 'Athletics' => 5, 'Survival' => 4)
        end

        it "should Strike with one die, adding Strength, and Dexterity to hit for a finesse attack" do
          jaws = @out['attacks'].first

          expect(jaws.values_at('name', 'bonus', 'dice', 'die', 'modifier', 'damage_type')).to eq [ 'Jaws', 6, 1, 'd8', 2, 'piercing' ]
          expect(jaws['traits']).to eq [ 'finesse' ]
        end

        it "should have the minion trait and no advanced maneuver yet" do
          expect(@out['traits']).to eq %w{animal minion}
          expect(@out['maneuver']).to be_nil
          expect(@out['support']).to include 'status penalty to its Speeds'
        end
      end

      describe "a savage wolf at level 8" do
        before(:all) { @out = stats('Wolf', 8, :mature => true, :path => 'savage') }

        it "should add the mature and savage increases" do
          expect(@out['attributes']).to eq('Strength' => 5, 'Dexterity' => 5, 'Constitution' => 4, 'Intelligence' => -4,
                                           'Wisdom' => 3, 'Charisma' => 0)
        end

        it "should grow twice, from Small to Large" do
          expect(@out['size']).to eq 'Large'
        end

        it "should have the plan's numbers" do
          expect(@out.values_at('stage', 'hp', 'ac', 'perception')).to eq [ 'savage', 86, 25, 15 ]
          expect(@out['saves']).to eq('Fortitude' => 16, 'Reflex' => 17, 'Will' => 15)
          expect(@out['skills'].transform_values { |one| one['value'] }).to eq('Acrobatics' => 15, 'Athletics' => 17,
                                                                               'Intimidation' => 10, 'Stealth' => 15,
                                                                               'Survival' => 15)
        end

        it "should make its type's skill expert at mature, and Athletics expert at savage" do
          expect(@out['skills'].transform_values { |one| one['rank'] }).to include('Survival' => 'expert', 'Athletics' => 'expert',
                                                                                   'Stealth' => 'trained')
        end

        it "should deal two dice plus 3 more, and magical" do
          jaws = @out['attacks'].first

          expect(jaws.values_at('bonus', 'dice', 'modifier')).to eq [ 15, 2, 8 ]
          expect(jaws['traits']).to eq %w{finesse magical}
        end

        it "should know its advanced maneuver" do
          expect(@out['maneuver']['name']).to eq 'Takedown'
        end
      end

      describe "a nimble wolf at level 8" do
        before(:all) { @out = stats('Wolf', 8, :mature => true, :path => 'nimble') }

        it "should grow only once, and favour Dexterity and Acrobatics" do
          expect(@out['size']).to eq 'Medium'
          expect(@out['attributes'].values_at('Strength', 'Dexterity')).to eq [ 4, 6 ]
          expect(@out['ac']).to eq 26
          expect(skill(@out, 'Acrobatics')).to eq 18
          expect(skill(@out, 'Athletics')).to eq 14
        end

        it "should deal 2 more damage" do
          expect(@out['attacks'].first.values_at('bonus', 'modifier')).to eq [ 16, 6 ]
        end
      end

      describe "a specialized savage wolf at level 14" do
        it "should become expert in attacks and master in saves and Perception, with three dice and doubled damage" do
          out = stats('Wolf', 14, :mature => true, :path => 'savage', :specializations => [ { 'name' => 'Racer', 'choice' => 'land' } ])

          expect(out['attributes']).to eq('Strength' => 5, 'Dexterity' => 6, 'Constitution' => 5, 'Intelligence' => -2,
                                          'Wisdom' => 3, 'Charisma' => 0)
          expect(out.values_at('stage', 'hp', 'ac', 'perception')).to eq [ 'specialized', 160, 32, 23 ]
          expect(out['attacks'].first.values_at('bonus', 'dice', 'modifier')).to eq [ 24, 3, 11 ]
        end

        it "should give a racer a legendary Fortitude and 10 feet on the Speed it chose" do
          out = stats('Wolf', 14, :mature => true, :path => 'savage', :specializations => [ { 'name' => 'Racer', 'choice' => 'land' } ])

          expect(out['saves']).to eq('Fortitude' => 27, 'Reflex' => 26, 'Will' => 23)
          expect(out['speeds']).to eq('land' => 50)
        end

        it "should raise a bully's Athletics a rank past the savage expert, and Intimidation to expert" do
          out = stats('Wolf', 14, :mature => true, :path => 'savage', :specializations => [ { 'name' => 'Bully' } ])

          expect(out['attributes'].values_at('Strength', 'Charisma')).to eq [ 6, 3 ]
          expect(out['skills']['Athletics']).to eq('rank' => 'master', 'value' => 26)
          expect(out['skills']['Intimidation']).to eq('rank' => 'expert', 'value' => 21)
        end

        it "should make a tracker master in the Survival its type made expert" do
          out = stats('Wolf', 14, :mature => true, :path => 'nimble', :specializations => [ { 'name' => 'Tracker' } ])

          expect(out['skills']['Survival']['rank']).to eq 'master'
        end

        it "should make an ambusher expert in Stealth and in unarmored defense" do
          out = stats('Wolf', 14, :mature => true, :path => 'nimble', :specializations => [ { 'name' => 'Ambusher' } ])

          expect(out['skills']['Stealth']['rank']).to eq 'expert'
          expect(out['ranks']['unarmored']).to eq 'expert'
          expect(out['ac']).to eq 10 + out['attributes']['Dexterity'] + 18
        end
      end

      describe "size" do
        it "should keep a Horse chosen Large at Large, and grow a Medium one" do
          expect(stats('Horse', 4, :size => 'Large', :mature => true)['size']).to eq 'Large'
          expect(stats('Horse', 4, :size => 'Medium', :mature => true)['size']).to eq 'Large'
          expect(stats('Horse', 1)['size']).to eq 'Medium'
        end

        it "should ignore a size the type can't choose" do
          expect(stats('Wolf', 1, :size => 'Large')['size']).to eq 'Small'
        end
      end

      describe "type specials" do
        it "should add a scorpion's poison to its stinger, more once specialized" do
          young = stats('Scorpion', 1)['attacks'].find { |attack| attack['name'] == 'Stinger' }
          special = stats('Scorpion', 14, :mature => true, :path => 'savage', :specializations => [ { 'name' => 'Wrecker' } ])
                    .then { |out| out['attacks'].find { |attack| attack['name'] == 'Stinger' } }

          expect(young['extra']).to eq '1d4 poison'
          expect(special['extra']).to eq '2d4 poison'
        end

        it "should make a crocodile's tail finesse, not agile" do
          tail = stats('Crocodile', 1)['attacks'].find { |attack| attack['name'] == 'Tail' }

          expect(tail['traits']).to eq [ 'finesse' ]
        end

        it "should give a shark only a swim Speed" do
          out = stats('Shark', 1)

          expect(out['speeds']).to eq('swim' => 40)
          expect(out['traits']).to include 'aquatic'
        end

        it "should mark a mount" do
          expect(stats('Horse', 1)['mount']).to be true
          expect(stats('Wolf', 1)['mount']).to be false
        end
      end

      describe "barding" do
        it "should cap Dexterity, add its item bonus and take a check and Speed penalty when too heavy" do
          out = stats('Bear', 1, :barding => 'Heavy Barding (Small or Medium)')

          expect(out['ac']).to eq 18
          expect(out['skills'].transform_values { |one| one['value'] }).to eq('Acrobatics' => 2, 'Athletics' => 3, 'Intimidation' => 3)
          expect(out['speeds']).to eq('land' => 25)
          expect(out['barding']).to eq 'Heavy Barding (Small or Medium)'
        end

        it "should spare a strong enough companion the check penalty and 5 feet of the Speed penalty" do
          out = stats('Ape', 1, :barding => 'Light Barding (Small or Medium)')

          expect(out['ac']).to eq 15
          expect(skill(out, 'Athletics')).to eq 6
          expect(out['speeds']).to eq('land' => 25, 'climb' => 25)
        end

        it "should slow a companion too weak for light barding by 5 feet" do
          out = stats('Wolf', 1, :barding => 'Light Barding (Small or Medium)')

          expect(out['ac']).to eq 17
          expect(skill(out, 'Acrobatics')).to eq 5
          expect(out['speeds']).to eq('land' => 35)
        end
      end

      describe "Auspice" do
        def steed(level, choice)
          stats('Horse', level, :size => 'Large', :mature => true, :path => 'savage',
                :specializations => [ { 'name' => 'Auspice', 'choice' => choice } ])
        end

        it "should give a celestial steed its traits, weakness, wings and extra Hit Points" do
          out = steed(18, 'celestial')

          expect(out['attributes'].values_at('Intelligence', 'Wisdom')).to eq [ 0, 4 ]
          expect(out['hp']).to eq 8 + (6 + 4) * 18 + 25 + 5
          expect(out['traits']).to include('celestial', 'holy')
          expect(out['weaknesses']).to eq('unholy' => 5)
          expect(out['speeds']).to eq('land' => 40, 'fly' => 40)
          expect(out['skills']['Religion']).to eq('rank' => 'expert', 'value' => 26)
        end

        it "should give a monitor no weakness and no extra 5" do
          out = steed(20, 'monitor')

          expect(out['hp']).to eq 8 + (6 + 4) * 20 + 30
          expect(out['weaknesses']).to eq({})
        end
      end

      it "should know nothing of a type the catalogue doesn't have" do
        expect(stats('Griffon', 1)).to be_nil
      end
    end
  end
end
