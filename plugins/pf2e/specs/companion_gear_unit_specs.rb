require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What an animal companion can wear, as plain data: barding's fit, the item bonus to Speed, the limit of two
    # invested items, horseshoes needing four legs, and what each refusal says.
    describe "companion gear rules" do

      before(:all) do
        @catalogue = YAML.load_file('game/config/pf2e_animal_companions.yml')['pf2e_animal_companions']
        @gear = YAML.load_file('game/config/pf2e_gear.yml')['pf2e_gear']
        @magic = YAML.load_file('game/config/pf2e_magicitem.yml')['pf2e_magicitem']
      end

      # An item as Gear.facts makes it, from the catalogue entry.
      def facts(name, info, invested: false)
        { 'name' => name,
          'traits' => Array(info['traits']),
          'armor' => Companion::Gear.armor_of(info),
          'bonus' => info['companion_bonus'] || {},
          'needs' => Array(info['companion_needs']).map(&:to_s),
          'investable' => Pf2e.has_trait?(info['traits'], 'invested'),
          'invested' => invested }
      end

      def barding(name)
        facts(name, @gear[name])
      end

      def magic(name, invested: false)
        facts(name, @magic[name], :invested => invested)
      end

      def refusal(item, worn: [], type: 'Wolf', size: 'Small', staff: false)
        Companion::Gear.refusal(item, :worn => worn, :type_info => @catalogue['types'][type], :type => type, :size => size,
                                      :names => { 'name' => 'Ash', 'mid' => 'Ash' }, :staff => staff)
      end

      describe "the catalogues" do
        it "should size every plain barding, and leave the barding of the zephyr to fit anyone" do
          sizes = @gear.select { |_name, info| info.is_a?(Hash) && info['companion_armor'] }
                       .to_h { |name, info| [ name, info['companion_armor']['sizes'] ] }

          expect(sizes).to eq('Barding of the Zephyr' => nil,
                              'Light Barding (Large)' => [ 'Large' ], 'Light Barding (Small or Medium)' => [ 'Small', 'Medium' ],
                              'Heavy Barding (Small or Medium)' => [ 'Small', 'Medium' ], 'Heavy Barding (Large)' => [ 'Large' ])
        end

        it "should give the horseshoes their Speed bonus, for four-legged companions only" do
          expect(@magic['Alacritous Horseshoes']['companion_bonus']).to eq('speed' => 5)
          expect(@magic['Alacritous Horseshoes (Greater)']['companion_bonus']).to eq('speed' => 10)
          expect(@magic['Alacritous Horseshoes']['companion_needs']).to eq 'quadruped'
          expect(@magic['Alacritous Horseshoes (Greater)']['companion_needs']).to eq 'quadruped'
        end

        it "should mark the four-legged types" do
          four = @catalogue['types'].select { |_name, info| info['quadruped'] == true }.keys.sort

          expect(four).to eq [ 'Badger', 'Bear', 'Boar', 'Cat', 'Crocodile', 'Horse', 'Riding Drake', 'Wolf' ]
        end
      end

      describe "fit" do
        it "should fit barding to the sizes it names, and barding without sizes to any" do
          small = barding('Light Barding (Small or Medium)')['armor']
          large = barding('Light Barding (Large)')['armor']
          zephyr = barding('Barding of the Zephyr')['armor']

          expect(Companion::Gear.fits?(small, 'Medium')).to be true
          expect(Companion::Gear.fits?(small, 'Large')).to be false
          expect(Companion::Gear.fits?(large, 'Small')).to be false
          expect(Companion::Gear.fits?(zephyr, 'Huge')).to be true
        end

        it "should keep on only what still fits the type and size" do
          wolf = @catalogue['types']['Wolf']
          bird = @catalogue['types']['Bird']

          expect(Companion::Gear.stays_on?(barding('Light Barding (Small or Medium)'), wolf, 'Large')).to be false
          expect(Companion::Gear.stays_on?(barding('Light Barding (Small or Medium)'), wolf, 'Medium')).to be true
          expect(Companion::Gear.stays_on?(magic('Alacritous Horseshoes'), bird, 'Small')).to be false
          expect(Companion::Gear.stays_on?(magic('Alacritous Horseshoes'), wolf, 'Small')).to be true
          expect(Companion::Gear.stays_on?(barding('Light Barding (Large)'), wolf, nil)).to be true
        end
      end

      describe "bonuses and investiture" do
        it "should count only the highest item bonus to Speed" do
          worn = [ magic('Alacritous Horseshoes', :invested => true), magic('Alacritous Horseshoes (Greater)', :invested => true) ]

          expect(Companion::Gear.item_bonuses(worn)).to eq('speed' => 10)
          expect(Companion::Gear.item_bonuses([ magic('Collar of Empathy', :invested => true) ])).to eq({})
        end

        it "should add the item bonus to the land Speed, before barding's penalty" do
          wolf = { 'type' => 'Wolf' }
          light = { 'name' => 'Light Barding (Small or Medium)', 'companion_armor' => @gear['Light Barding (Small or Medium)']['companion_armor'] }

          plain = Companion::Stats.of(wolf, :level => 1, :catalogue => @catalogue)
          shod = Companion::Stats.of(wolf, :level => 1, :item_bonuses => { 'speed' => 10 }, :catalogue => @catalogue)
          both = Companion::Stats.of(wolf, :level => 1, :barding => light, :item_bonuses => { 'speed' => 10 }, :catalogue => @catalogue)

          expect(plain['speeds']['land']).to eq 40
          expect(shod['speeds']['land']).to eq 50
          # A young wolf's Strength +2 is short of light barding's 3: the full 5-foot penalty.
          expect(both['speeds']['land']).to eq 45
        end

        it "should give a shark, with no land Speed, nothing from horseshoes" do
          shark = Companion::Stats.of({ 'type' => 'Shark' }, :level => 1, :item_bonuses => { 'speed' => 5 }, :catalogue => @catalogue)

          expect(shark['speeds'].key?('land')).to be false
        end

        it "should count what the companion has invested" do
          worn = [ magic('Collar of Empathy', :invested => true), barding('Light Barding (Small or Medium)') ]

          expect(Companion::Gear.invested_count(worn)).to eq 1
        end
      end

      describe "refusals" do
        it "should let a wolf wear light barding and a collar" do
          expect(refusal(barding('Light Barding (Small or Medium)'))).to be_nil
          expect(refusal(magic('Collar of Empathy'))).to be_nil
        end

        it "should refuse an item without the companion trait, unless staff allow it" do
          plain = facts('Rope', { 'traits' => [] })

          expect(refusal(plain).code).to eq :companion_gear_not_companion
          expect(refusal(plain, :staff => true)).to be_nil
        end

        it "should refuse a second barding" do
          found = refusal(barding('Heavy Barding (Small or Medium)'), :worn => [ barding('Light Barding (Small or Medium)') ])

          expect(found.code).to eq :companion_gear_second_barding
          expect(found.args['barding']).to eq 'Light Barding (Small or Medium)'
        end

        it "should refuse barding of the wrong size" do
          found = refusal(barding('Light Barding (Large)'))

          expect(found.code).to eq :companion_gear_wrong_size
          expect(found.args).to include('sizes' => 'Large', 'size' => 'Small')
          expect(refusal(barding('Light Barding (Large)'), :size => 'Large')).to be_nil
        end

        it "should refuse horseshoes on a companion without four legs" do
          found = refusal(magic('Alacritous Horseshoes'), :type => 'Bird')

          expect(found.code).to eq :companion_gear_needs_quadruped
          expect(found.args['type']).to eq 'bird'
          expect(refusal(magic('Alacritous Horseshoes'), :type => 'Horse', :size => 'Large')).to be_nil
        end

        it "should refuse a third invested item, but not barding that needs no investing" do
          worn = [ magic('Collar of Empathy', :invested => true), magic('Alacritous Horseshoes', :invested => true) ]

          found = refusal(magic('Collar of Inconspicuousness'), :worn => worn)
          expect(found.code).to eq :companion_gear_invest_full
          expect(found.args['items']).to eq 'Collar of Empathy and Alacritous Horseshoes'
          expect(refusal(barding('Light Barding (Small or Medium)'), :worn => worn)).to be_nil
        end

        it "should count the barding of the zephyr against both limits" do
          worn = [ magic('Collar of Empathy', :invested => true), magic('Alacritous Horseshoes', :invested => true) ]

          expect(refusal(barding('Barding of the Zephyr'), :worn => worn).code).to eq :companion_gear_invest_full
          expect(refusal(barding('Barding of the Zephyr'), :worn => [ barding('Light Barding (Small or Medium)') ]).code)
            .to eq :companion_gear_second_barding
        end

        it "should have every refusal's message" do
          keys = %w{not_companion second_barding wrong_size needs_quadruped invest_full category untyped already invested_yours
                    not_worn worn worn_invested worn_staff removed removed_staff came_off came_off_staff worn_mark invested_column}
          locale = YAML.load_file('plugins/pf2e/locales/locale_en.yml')['en']['pf2e']

          expect(keys.reject { |key| locale.key?("companion_gear_#{key}") }).to eq []
          expect(YAML.load_file('plugins/pf2egear/locales/locale_en.yml')['en']['pf2egear'].key?('item_on_companion')).to be true
        end

        it "should have a staff message for each one that speaks to the owner" do
          locale = YAML.load_file('plugins/pf2e/locales/locale_en.yml')['en']
          locale['pf2egear'] = YAML.load_file('plugins/pf2egear/locales/locale_en.yml')['en']['pf2egear']
          found = lambda { |key| key.split('.').reduce(locale) { |at, part| at.is_a?(Hash) ? at[part] : nil } }

          missing = Companion::Gear::STAFF_KEYS.to_a.flatten.reject { |key| found.call(key) }
          expect(missing).to eq []
          expect(Companion::Gear::STAFF_KEYS.values.map { |key| found.call(key) }.grep(/\byour\b/i)).to eq []
          expect(found.call('pf2e.companion_subject_unnamed_of')).to eq "%{char}'s animal companion"
        end

        it "should give staff the staff message, with the character's name, and keep the code" do
          char = double('Character', :name => 'Rowan')
          worn = Err.new(:companion_gear_not_worn, 'pf2e.companion_gear_not_worn', 'name' => 'Ash', 'item' => 'Rope')
          staffed = Companion::Gear.for_staff(worn, char)

          expect(staffed.code).to eq :companion_gear_not_worn
          expect(staffed.key).to eq 'pf2e.companion_gear_not_worn_staff'
          expect(staffed.args).to include('char' => 'Rowan', 'name' => 'Ash', 'item' => 'Rope')

          size = Err.new(:companion_gear_wrong_size, 'pf2e.companion_gear_wrong_size', 'mid' => 'Ash')
          expect(Companion::Gear.for_staff(size, char)).to equal size
        end
      end
    end
  end
end
