require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # One formula makes every type of its item (GM Core p. 223), except types that are different items
    # and types rarer than the one whose formula they hold.
    describe "a formula's types" do

      def consumables
        {
          'Elixir of Life (Minor)' => { 'level' => 1, 'traits' => [ 'alchemical', 'elixir', 'healing', 'consumable' ] },
          'Elixir of Life (Lesser)' => { 'level' => 5, 'traits' => [ 'alchemical', 'elixir', 'healing', 'consumable' ] },
          'Elixir of Life (Moderate)' => { 'level' => 9, 'traits' => [ 'alchemical', 'elixir', 'healing', 'consumable' ] },
          'Sinew-Shock Serum (Lesser)' => { 'level' => 1, 'traits' => [ 'alchemical', 'elixir', 'consumable' ] },
          'Sinew-Shock Serum (Greater)' => { 'level' => 9, 'traits' => [ 'uncommon', 'alchemical', 'elixir', 'consumable' ] },
          'Energy Breath Potion (Fire, Lesser)' => { 'level' => 7, 'traits' => [ 'magical', 'potion', 'consumable' ] },
          'Energy Breath Potion (Fire, Moderate)' => { 'level' => 12, 'traits' => [ 'magical', 'potion', 'consumable' ] },
          'Energy Breath Potion (Cold, Lesser)' => { 'level' => 7, 'traits' => [ 'magical', 'potion', 'consumable' ] },
          'Marvelous Miniature (Boat)' => { 'level' => 8, 'traits' => [ 'magical', 'consumable' ] },
          'Marvelous Miniature (Horse)' => { 'level' => 8, 'traits' => [ 'magical', 'consumable' ] },
          'Versatile Vial (Lesser)' => { 'level' => 1, 'made_only' => true, 'traits' => [ 'alchemical', 'bomb', 'consumable' ] },
          'Versatile Vial (Moderate)' => { 'level' => 4, 'made_only' => true, 'traits' => [ 'alchemical', 'bomb', 'consumable' ] }
        }
      end

      def runes
        {
          'Flaming' => { 'level' => 8, 'rarity' => 'common', 'traits' => [ 'magical' ] },
          'Greater Flaming' => { 'level' => 15, 'rarity' => 'common', 'traits' => [ 'magical' ] },
          'Frost' => { 'level' => 8, 'rarity' => 'common', 'traits' => [ 'magical' ] }
        }
      end

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_consumables').and_return(consumables)
        allow(Global).to receive(:read_config).with('pf2e_runes').and_return(runes)
      end

      def char(level: 9, book: {}, advancing: false, staged: nil)
        double(:name => 'Someone', :pf2_level => level, :advancing => advancing, :pf2_formula_book => book,
               :pf2_advancement => { 'grants' => staged || {} })
      end

      describe :family do
        it "should take a grade off the end of a name" do
          { 'Elixir of Life (Minor)' => 'Elixir of Life',
            'Acid Flask (Moderate)' => 'Acid Flask',
            'Elixir of Life (True)' => 'Elixir of Life',
            'Spellstrike Ammunition (Type IV)' => 'Spellstrike Ammunition',
            'Cold Iron Ammunition (Low-Grade)' => 'Cold Iron Ammunition',
            'Alloy Orb (Exquisite High-Grade)' => 'Alloy Orb',
            'Wand of Widening (3rd-Rank Spell)' => 'Wand of Widening',
            'Handwraps of Mighty Blows (+2 Greater Striking)' => 'Handwraps of Mighty Blows',
            'Ring of Sigils' => 'Ring of Sigils' }.each do |name, family|
            expect(Crafting.family('consumables', name)).to eq family
          end
        end

        it "should keep a type that is a different item" do
          [ 'Aeon Stone (Preserving)', 'Marvelous Miniature (Boat)', 'Dragonplate (Umbral)', 'Lock (Poor)' ].each do |name|
            expect(Crafting.family('magicitem', name)).to eq name
          end
        end

        it "should keep what isn't a grade from a name with both" do
          expect(Crafting.family('consumables', 'Energy Breath Potion (Fire, Lesser)')).to eq 'Energy Breath Potion (Fire)'
        end

        it "should take a rune's grade off the front, and only a rune's" do
          expect(Crafting.family('runes', 'Greater Flaming')).to eq 'Flaming'
          expect(Crafting.family('runes', 'Major Shadow')).to eq 'Shadow'
          expect(Crafting.family('consumables', 'Greater Flaming')).to eq 'Greater Flaming'
        end
      end

      describe :known? do
        let(:minor) { char(book: { 'consumables' => [ 'Elixir of Life (Minor)' ] }) }

        it "should know every type of a formula in the book, whatever its level" do
          expect(Crafting.known?(minor, 'consumables', 'Elixir of Life (Lesser)')).to be true
          expect(Crafting.known?(minor, 'consumables', 'elixir of life (moderate)')).to be true
        end

        it "should know a lower type from a higher one" do
          moderate = char(book: { 'consumables' => [ 'Elixir of Life (Moderate)' ] })

          expect(Crafting.known?(moderate, 'consumables', 'Elixir of Life (Minor)')).to be true
        end

        it "should not reach a different item, or another element" do
          breath = char(book: { 'consumables' => [ 'Energy Breath Potion (Fire, Lesser)', 'Marvelous Miniature (Boat)' ] })

          expect(Crafting.known?(breath, 'consumables', 'Energy Breath Potion (Fire, Moderate)')).to be true
          expect(Crafting.known?(breath, 'consumables', 'Energy Breath Potion (Cold, Lesser)')).to be false
          expect(Crafting.known?(breath, 'consumables', 'Marvelous Miniature (Horse)')).to be false
        end

        it "should need its own formula for a type rarer than the one they know" do
          common = char(book: { 'consumables' => [ 'Sinew-Shock Serum (Lesser)' ] })
          uncommon = char(book: { 'consumables' => [ 'Sinew-Shock Serum (Greater)' ] })

          expect(Crafting.known?(common, 'consumables', 'Sinew-Shock Serum (Greater)')).to be false
          expect(Crafting.known?(uncommon, 'consumables', 'Sinew-Shock Serum (Lesser)')).to be true
        end

        it "should know a rune's greater grade from its base" do
          book = char(book: { 'runes' => [ 'Flaming' ] })

          expect(Crafting.known?(book, 'runes', 'Greater Flaming')).to be true
          expect(Crafting.known?(book, 'runes', 'Frost')).to be false
        end

        it "should name the formula that makes it, its own first" do
          both = char(book: { 'consumables' => [ 'Elixir of Life (Minor)', 'Elixir of Life (Lesser)' ] })

          expect(Crafting.covering(both, 'consumables', 'Elixir of Life (Lesser)')).to eq 'Elixir of Life (Lesser)'
          expect(Crafting.covering(minor, 'consumables', 'Elixir of Life (Moderate)')).to eq 'Elixir of Life (Minor)'
        end

        it "should say which formula already makes one they ask for" do
          expect(Crafting.known_message(minor, 'consumables', 'Elixir of Life (Minor)'))
            .to eq t('pf2e.formula_known', :formula => 'Elixir of Life (Minor)')
          expect(Crafting.known_message(minor, 'consumables', 'Elixir of Life (Lesser)'))
            .to eq t('pf2e.formula_covered', :known => 'Elixir of Life (Minor)', :formula => 'Elixir of Life (Lesser)')
          expect(Crafting.known_message(minor, 'consumables', 'Marvelous Miniature (Boat)')).to be_nil
        end

        it "should keep in_book? to what is written there" do
          expect(Crafting.in_book?(minor, 'consumables', 'elixir of life (minor)')).to be true
          expect(Crafting.in_book?(minor, 'consumables', 'Elixir of Life (Lesser)')).to be false
        end
      end

      it "should list every type the book makes, and never a made-only item" do
        book = char(book: { 'consumables' => [ 'Elixir of Life (Minor)', 'Versatile Vial (Lesser)' ] })

        expect(Crafting.makeable_names(book, 'consumables'))
          .to eq [ 'Elixir of Life (Minor)', 'Elixir of Life (Lesser)', 'Elixir of Life (Moderate)' ]
      end

      it "should offer no other type of a formula they know, or picked in this level" do
        filter = { 'traits' => [ 'elixir' ], 'max_level' => 20 }

        expect(Crafting.pool(char, filter)).to eq [ 'Elixir of Life (Lesser)', 'Elixir of Life (Minor)',
                                                    'Elixir of Life (Moderate)', 'Sinew-Shock Serum (Lesser)' ]

        picked = char(advancing: true, staged: { 'Formula Book' => { 'formula' => { 'consumables' => [ 'Elixir of Life (Lesser)' ] } } })

        expect(Crafting.pool(picked, filter)).to eq [ 'Sinew-Shock Serum (Lesser)' ]
      end

      it "should offer a cauldron every type of a formula they know, up to their level" do
        brewer = char(level: 7, book: { 'consumables' => [ 'Elixir of Life (Minor)' ] })

        expect(DailyChoices.known_formulas(brewer, 'traits' => [ 'elixir' ]))
          .to eq [ 'Elixir of Life (Lesser)', 'Elixir of Life (Minor)' ]
      end

      # A grade word the list doesn't hold would quietly split a family, so the real catalogue is held to it:
      # every typed alchemical item belongs to an item with more than one type.
      it "should group every typed alchemical consumable in the catalogue with its other types" do
        file = File.join(AresMUSH.game_path, 'config', 'pf2e_consumables.yml')
        catalogue = YAML.load_file(file)['pf2e_consumables']
        alchemical = catalogue.select { |_name, info| info.is_a?(Hash) && Array(info['traits']).include?('alchemical') }
        families = alchemical.keys.group_by { |name| Crafting.family('consumables', name) }

        alone = alchemical.keys.select { |name| name.include?('(') && families[Crafting.family('consumables', name)].size < 2 }

        expect(alone).to eq []
      end
    end
  end
end
