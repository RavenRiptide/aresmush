require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The formulas a class or feat lets a character pick: common items from the catalogue, by trait,
    # grouping and level, less the formulas they already know.
    describe :formula_pool do

      def consumables
        {
          'Acid Flask (Lesser)' => { 'level' => 1, 'traits' => [ 'alchemical', 'bomb', 'consumable' ] },
          'Elixir of Life (Minor)' => { 'level' => 1, 'traits' => [ 'alchemical', 'elixir', 'healing', 'consumable' ] },
          'Eagle Eye Elixir (Lesser)' => { 'level' => 1, 'traits' => [ 'alchemical', 'elixir', 'consumable' ] },
          'Glow Rod' => { 'level' => 1, 'subcategory' => 'tool', 'traits' => [ 'alchemical', 'consumable' ] },
          'Acid Flask (Moderate)' => { 'level' => 3, 'traits' => [ 'alchemical', 'bomb', 'consumable' ] },
          'Sinew-Shock Serum (Lesser)' => { 'level' => 1, 'traits' => [ 'uncommon', 'alchemical', 'elixir', 'consumable' ] },
          'Healing Potion (Minor)' => { 'level' => 1, 'traits' => [ 'magical', 'potion', 'healing', 'consumable' ] },
          'Shining Ammunition' => { 'level' => 1, 'traits' => [ 'magical', 'consumable' ] }
        }
      end

      def magicitem
        {
          'Shining Ammunition' => { 'level' => 1, 'traits' => [ 'magical', 'consumable' ] },
          'Wayfinder' => { 'level' => 2, 'traits' => [ 'magical' ] },
          'Bag of Holding (Type II)' => { 'level' => 7, 'traits' => [ 'magical' ] }
        }
      end

      def runes
        {
          'Striking' => { 'level' => 4, 'rarity' => 'common', 'traits' => [ 'magical' ] },
          'Ghost Touch' => { 'level' => 2, 'rarity' => 'common', 'traits' => [ 'magical' ] },
          'Vorpal' => { 'level' => 2, 'rarity' => 'rare', 'traits' => [ 'magical' ] }
        }
      end

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_consumables').and_return(consumables)
        allow(Global).to receive(:read_config).with('pf2e_magicitem').and_return(magicitem)
        allow(Global).to receive(:read_config).with('pf2e_runes').and_return(runes)
      end

      def char(level: 1, book: {}, advancing: false, staged: nil)
        double(:name => 'Someone', :pf2_level => level, :advancing => advancing, :pf2_formula_book => book,
               :pf2_advancement => { 'grants' => staged || {} })
      end

      it "should offer common items carrying one of the traits, up to the level" do
        pool = Crafting.pool(char, 'traits' => [ 'alchemical' ], 'max_level' => 1)

        expect(pool).to eq [ 'Acid Flask (Lesser)', 'Eagle Eye Elixir (Lesser)', 'Elixir of Life (Minor)', 'Glow Rod' ]
      end

      it "should ask for every trait under all_traits" do
        pool = Crafting.pool(char, 'all_traits' => [ 'elixir', 'healing' ], 'max_level' => 1)

        expect(pool).to eq [ 'Elixir of Life (Minor)' ]
      end

      it "should take an item by the grouping no trait marks" do
        pool = Crafting.pool(char, 'traits' => [ 'elixir' ], 'subcategory' => [ 'tool' ], 'max_level' => 1)

        expect(pool).to eq [ 'Eagle Eye Elixir (Lesser)', 'Elixir of Life (Minor)', 'Glow Rod' ]
      end

      it "should read level as the level the character is reaching" do
        expect(Crafting.pool(char(level: 2), 'traits' => [ 'bomb' ], 'max_level' => 'level')).to eq [ 'Acid Flask (Lesser)' ]
        expect(Crafting.pool(char(level: 2, advancing: true), 'traits' => [ 'bomb' ], 'max_level' => 'level'))
          .to eq [ 'Acid Flask (Lesser)', 'Acid Flask (Moderate)' ]
      end

      it "should hold a pick to exactly a level when both bounds name it" do
        pool = Crafting.pool(char(level: 2, advancing: true), 'traits' => [ 'alchemical' ], 'min_level' => 'level', 'max_level' => 'level')

        expect(pool).to eq [ 'Acid Flask (Moderate)' ]
      end

      it "should leave out a formula they know, or have picked in this level" do
        known = char(book: { 'consumables' => [ 'Acid Flask (Lesser)' ] }, advancing: true,
                     staged: { 'Formula Book' => { 'formula' => { 'consumables' => [ 'Glow Rod' ] } } })

        expect(Crafting.pool(known, 'traits' => [ 'alchemical' ], 'max_level' => 1))
          .to eq [ 'Eagle Eye Elixir (Lesser)', 'Elixir of Life (Minor)' ]
      end

      it "should search several catalogues, rarity read from traits or from a rune's own field" do
        pool = Crafting.pool(char, 'category' => [ 'consumables', 'magicitem', 'runes' ], 'traits' => [ 'magical' ], 'max_level' => 2)

        expect(pool).to eq [ 'Ghost Touch', 'Healing Potion (Minor)', 'Shining Ammunition', 'Wayfinder' ]
      end

      it "should file a pick under the first catalogue that holds it" do
        filter = { 'category' => [ 'magicitem', 'consumables' ] }

        expect(Crafting.pool_category(filter, 'shining ammunition')).to eq [ 'magicitem', 'Shining Ammunition' ]
        expect(Crafting.pool_category({}, 'Glow Rod')).to eq [ 'consumables', 'Glow Rod' ]
      end

      it "should grant the formula picked from a pool" do
        block = { 'from_formulas' => { 'category' => [ 'magicitem', 'runes' ] } }

        expect(Pf2e.choice_grants(char, block, 'Ghost Touch')).to eq('formula' => { 'runes' => [ 'Ghost Touch' ] })
      end

      it "should let an alchemist make a potion they took through Improbable Elixirs, and no other" do
        holder = char
        allow(Pf2e).to receive(:choice_labels_for).with(holder, 'Improbable Elixirs').and_return([ 'Healing Potion (Minor)' ])

        expect(Alchemy.makes?(holder, 'healing potion (minor)', consumables['Healing Potion (Minor)'])).to be true
        expect(Alchemy.makes?(holder, 'Shining Ammunition', consumables['Shining Ammunition'])).to be false
        expect(Alchemy.makes?(holder, 'Glow Rod', consumables['Glow Rod'])).to be true
      end

      describe "a feat's formula grant" do
        def grant(holder, drafting:)
          allow(Ledger).to receive(:drafting?).with(holder).and_return(drafting)

          Pf2e::GRANTS['formula']['apply'].call(:char => holder, :value => { 'consumables' => [ "Philosopher's Stone" ] })
        end

        it "should write the book during a draft, for the commit to record" do
          holder = char
          expect(Crafting).to receive(:write_formula).with(holder, 'consumables', "Philosopher's Stone")
          expect(Crafting).to_not receive(:learn!)

          expect(grant(holder, :drafting => true)).to eq [ [ 'pf2e.feat_grants_formula', { :formula => "Philosopher's Stone" } ] ]
        end

        it "should record it on the ledger outside one" do
          holder = char
          expect(Crafting).to receive(:learn!).with(holder, 'consumables', "Philosopher's Stone", :source_type => 'feat', :source_ref => "Philosopher's Stone")

          grant(holder, :drafting => false)
        end
      end

      # A formula pick never asks for more than its pool can give: Alchemical Scholar's 20th-level pick
      # has one item to offer, and a Formula Book pick in the same level can take it.
      describe "a formula choice with too little to offer" do
        it "should open no more picks than the pool holds, and none from an empty pool" do
          block = { 'count' => 2, 'from_formulas' => { 'traits' => [ 'alchemical' ], 'min_level' => 3, 'max_level' => 3 } }

          expect(Pf2e.choice_count(char, block)).to eq 1
          expect(Pf2e.choice_count(char(book: { 'consumables' => [ 'Acid Flask (Moderate)' ] }), block)).to eq 0
        end

        it "should open nothing for a count of nought" do
          to_assign = {}

          Pf2e.open_feat_choice(to_assign, 'Alchemical Scholar Formulas', 0)

          expect(to_assign).to eq({})
        end

        it "should close the picks another choice's pick left with nothing to offer" do
          holder = char(advancing: true)
          allow(holder).to receive(:pf2_to_assign)
            .and_return('feat choice' => { 'Alchemical Scholar Formulas' => [ 'open' ], 'Formula Book' => [ 'Glow Rod', 'open' ] })
          allow(Pf2e).to receive(:find_choice_block) do |_char, name|
            { 'from_formulas' => { 'traits' => [ name == 'Formula Book' ? 'alchemical' : 'nothing' ] } }
          end
          allow(Pf2e).to receive(:choice_labels_for).and_return([])

          expect(holder).to receive(:update).with(:pf2_to_assign => { 'feat choice' => { 'Formula Book' => [ 'Glow Rod', 'open' ] } })

          expect(Pf2e.close_exhausted_formula_choices(holder))
            .to eq [ t('pf2e.choice_formulas_exhausted', :choice => 'Alchemical Scholar Formulas') ]
        end
      end

      describe :choice_count do
        it "should open one slot unless the block says more" do
          expect(Pf2e.choice_count(char, {})).to eq 1
          expect(Pf2e.choice_count(char, 'count' => 4)).to eq 4
        end

        it "should count by an ability modifier, with a floor" do
          smart = char
          allow(Pf2eAbilities).to receive(:get_score).with(smart, 'Intelligence').and_return(18)

          dull = char
          allow(Pf2eAbilities).to receive(:get_score).with(dull, 'Intelligence').and_return(8)

          block = { 'count' => { 'ability' => 'Intelligence', 'min' => 1 } }

          expect(Pf2e.choice_count(smart, block)).to eq 4
          expect(Pf2e.choice_count(dull, block)).to eq 1
        end
      end
    end
  end
end
