require "plugin_test_loader"

module AresMUSH
  module Pf2egear

    # Whether a property rune fits an item (`RuneFit`), which staff's `etch/property` and the vendor both ask.
    # A rune's `usage` comes from its pack item; the tests of an item are ours.
    describe "whether a property rune fits", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Fitter#{rand(1000000)}", :pf2_level => 20)
        @made = [ @char ]
      end

      after(:each) do
        @made.each { |one| one&.delete }
      end

      def item(category, name, potency: 3, runes: [])
        made = Pf2egear.create_item(@char, category, name, 1, Global.read_config("pf2e_#{category}", name))
        made.update(:runes => { 'fundamental' => { 'potency' => potency }, 'property' => { 'list' => runes } })
        @made << made
        made
      end

      def fit(category, name, rune, **options)
        RuneFit.property(item(category, name, **options), category, rune)
      end

      def code(category, name, rune, **options)
        found = fit(category, name, rune, **options)

        found.ok? ? :ok : found.code
      end

      describe "what a rune is etched onto" do
        {
          'weapon' => [ 'Flaming', 'weapons', 'Longbow', :ok ],
          'melee weapon' => [ 'Shifting', 'weapons', 'Longsword', :ok ],
          'melee weapon, on a ranged one' => [ 'Shifting', 'weapons', 'Longbow', :wrong_usage ],
          'thrown weapon' => [ 'Returning', 'weapons', 'Javelin', :ok ],
          'thrown weapon, on one that is not' => [ 'Returning', 'weapons', 'Longsword', :wrong_usage ],
          'bludgeoning weapon' => [ 'Shockwave', 'weapons', 'Mace', :ok ],
          'bludgeoning weapon, on a slashing one' => [ 'Shockwave', 'weapons', 'Longsword', :wrong_usage ],
          'slashing melee weapon' => [ 'Vorpal', 'weapons', 'Longsword', :ok ],
          'slashing melee weapon, on a piercing one' => [ 'Vorpal', 'weapons', 'Rapier', :wrong_usage ],
          'piercing or slashing melee weapon' => [ 'Keen', 'weapons', 'Rapier', :ok ],
          'piercing or slashing melee weapon, on a bludgeoning one' => [ 'Keen', 'weapons', 'Mace', :wrong_usage ],
          'piercing or slashing melee weapon, on a ranged one' => [ 'Keen', 'weapons', 'Longbow', :wrong_usage ],
          'armor, on clothing' => [ 'Slick', 'armor', "Explorer's Clothing", :ok ],
          'light armor' => [ 'Invisibility', 'armor', 'Leather', :ok ],
          'light armor, on medium' => [ 'Invisibility', 'armor', 'Hide', :wrong_usage ],
          'medium or heavy armor' => [ 'Fortification', 'armor', 'Full Plate', :ok ],
          'medium or heavy armor, on light' => [ 'Fortification', 'armor', 'Leather', :wrong_usage ],
          'light or medium armor that is not metal' => [ 'Shadow', 'armor', 'Hide', :ok ],
          'light or medium armor that is not metal, on chain' => [ 'Shadow', 'armor', 'Chain Shirt', :wrong_usage ],
          'light or medium armor that is not metal, on heavy' => [ 'Shadow', 'armor', 'Full Plate', :wrong_usage ]
        }.each_pair do |what, (rune, category, name, expected)|
          it "should answer #{expected} for #{rune}, etched onto a #{what}" do
            expect(code(category, name, rune)).to eq expected
          end
        end

        # A usage nothing tests is refused, so a new rune is never etched without a test.
        it "should refuse a rune whose usage nothing tests" do
          allow(Pf2egear).to receive(:rune_entry).and_call_original
          allow(Pf2egear).to receive(:rune_entry).with('Flaming')
                                                 .and_return(Pf2egear.runes['Flaming'].merge('usage' => 'clan-dagger'))

          expect(code('weapons', 'Longsword', 'Flaming')).to eq :wrong_usage
        end
      end

      describe "the kind of item" do
        it "should refuse an armor rune on a weapon, and a weapon rune on armor" do
          expect(code('weapons', 'Longsword', 'Slick')).to eq :wrong_kind
          expect(code('armor', 'Leather', 'Flaming')).to eq :wrong_kind
        end

        it "should refuse a property rune on a shield" do
          expect(code('shields', 'Steel Shield', 'Flaming')).to eq :wrong_kind
        end

        it "should refuse a property rune on a staff" do
          expect(code('weapons', 'Animal Staff', 'Flaming')).to eq :staff
        end

        it "should refuse a rune the catalogue lacks" do
          expect(code('weapons', 'Longsword', 'Flamming')).to eq :unknown
          expect(code('weapons', 'Longsword', 'Flaming (Purple)')).to eq :unknown
        end
      end

      describe "room on the item" do
        it "should hold as many as its potency rune is worth" do
          expect(code('weapons', 'Longsword', 'Frost', potency: 1, runes: [ 'Flaming' ])).to eq :no_slot
          expect(code('weapons', 'Longsword', 'Frost', potency: 2, runes: [ 'Flaming' ])).to eq :ok
        end
      end

      describe "holy and unholy" do
        it "should keep them off one item" do
          expect(code('weapons', 'Longsword', 'Unholy', runes: [ 'Holy' ])).to eq :excluded
          expect(code('weapons', 'Longsword', 'Holy', runes: [ 'Unholy' ])).to eq :excluded
        end
      end

      describe "a family of runes" do
        it "should let a stronger rune replace a weaker one, without a slot of its own" do
          found = fit('weapons', 'Longsword', 'Greater Flaming', potency: 1, runes: [ 'Flaming' ])

          expect(found.state).to eq('rune' => 'Greater Flaming', 'replaces' => 'Flaming')
        end

        it "should refuse a rune beside a stronger one of its family" do
          expect(code('weapons', 'Longsword', 'Flaming', runes: [ 'Greater Flaming' ])).to eq :has_stronger
        end

        # A specific item names its rune the pack's way, and that is still the rune.
        it "should know the pack's spelling for the family" do
          expect(code('weapons', 'Longsword', 'Flaming', runes: [ 'Flaming (Greater)' ])).to eq :has_stronger
        end
      end

      describe "an energy-resistant rune" do
        it "should need its damage type" do
          found = fit('armor', 'Leather', 'Energy Resistant')

          expect(found.code).to eq :needs_choice
          expect(found.args['choices']).to eq 'acid, cold, electricity, fire'
        end

        it "should store the type with the rune" do
          expect(fit('armor', 'Leather', 'energy resistant (fire)').state['rune']).to eq 'Energy Resistant (Fire)'
        end

        it "should take one of each damage type" do
          expect(code('armor', 'Leather', 'Energy Resistant (Acid)', runes: [ 'Energy Resistant (Fire)' ])).to eq :ok
        end

        it "should let a greater one replace a lesser of the same type" do
          found = fit('armor', 'Leather', 'Greater Energy Resistant (Fire)', potency: 1, runes: [ 'Energy Resistant (Fire)' ])

          expect(found.state['replaces']).to eq 'Energy Resistant (Fire)'
        end

        it "should refuse a lesser one beside a greater of the same type" do
          expect(code('armor', 'Leather', 'Energy Resistant (Fire)', runes: [ 'Greater Energy Resistant (Fire)' ]))
            .to eq :has_stronger
        end
      end

      describe "reading a rune's name" do
        it "should read the pack's spelling, grade last, as the catalogue's" do
          expect(Pf2egear.rune_named('Frost (Greater)')).to eq 'Greater Frost'
          expect(Pf2egear.rune_named('Fortification (Greater)')).to eq 'Greater Fortification'
        end

        it "should read a choice rune with its choice, by name or slug" do
          expect(Pf2egear.rune_named('Energy Resistant (Fire)')).to eq 'Energy Resistant'
          expect(Pf2egear.rune_choice('energy-resistant-fire')).to eq 'fire'
          expect(Pf2egear.rune_spelled('energy-resistant-fire')).to eq 'Energy Resistant (Fire)'
        end

        it "should give no choice to a rune that takes none" do
          expect(Pf2egear.rune_named('Flaming (Fire)')).to be_nil
        end

        # The specific magic items that name their rune the pack's way now reach its rules.
        it "should give a specific item's rune in the catalogue's spelling" do
          icicle = Pf2egear.create_item(@char, 'weapons', 'Icicle', 1, Global.read_config('pf2e_weapons', 'Icicle'))
          @made << icicle

          expect(icicle.runes.dig('property', 'list')).to eq [ 'Frost (Greater)' ]
          expect(Pf2egear.property_runes(icicle)).to eq [ 'greater-frost' ]
          expect(Pf2egear.rune_entry('greater-frost')['rules']).to_not be_empty
        end

        # The catalogue writes a specific item's runes as a bare list. An item made that way is still read.
        it "should read runes an item holds as a bare list" do
          blade = item('weapons', 'Longsword')
          blade.update(:runes => { 'fundamental' => { 'potency' => 2 }, 'property' => [ 'Flaming' ] })

          expect(Pf2egear.property_runes(blade)).to eq [ 'flaming' ]
          expect(RuneFit.property(blade, 'weapons', 'Frost').state['rune']).to eq 'Frost'
        end
      end
    end
  end
end
