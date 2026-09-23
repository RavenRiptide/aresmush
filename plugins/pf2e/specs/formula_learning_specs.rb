require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Formulas: bought, worked out from an item, or given by staff. Knowledge rather than a thing carried,
    # so they are the character's and are held as grants like the rest of the sheet.
    describe Crafting, :dbtest => true do

      class FormulaClient
        attr_reader :failures, :said

        def initialize
          @failures = []
          @said = []
        end

        def logged_in?
          true
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

        @client = FormulaClient.new
        @char = Character.create(:name => "Crafter#{rand(1000000)}", :pf2_level => 3, :pf2_money => 100_000,
                                 :pf2_formula_book => {}, :pf2_baseinfo_locked => true)
        @skills = [ Pf2eSkills.create(:character => @char, :name => 'Crafting', :prof_level => 'expert') ]
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14) }

        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * 0.75).ceil, 1 ].max ] * amount.to_i }
      end

      after(:each) do
        Pf2eGrant.find(:character_id => @char.id).each(&:delete)
        (@skills + @abilities).each(&:delete)
        @char.delete
      end

      def char
        Character[@char.id]
      end

      def run(cmd_class, text)
        cmd_class.new(@client, Command.new(text), char).on_command
      end

      def known
        (char.pf2_formula_book || {}).values.flatten
      end

      it "should price a formula by the level of what it makes, not by the item's price" do
        expect(Crafting.price(1)).to eq 100
        expect(Crafting.price(12)).to eq 10_000
        expect(Crafting.craft_dc('level' => 3, 'traits' => [])).to eq 18
        expect(Crafting.craft_dc('level' => 3, 'traits' => [ 'Rare' ])).to eq 23
      end

      it "should buy a common formula, taking its price from their money" do
        purse = char.pf2_money

        run(PF2FormulaBuyCmd, 'formula/buy consumables=healing potion (minor)')

        expect(@client.failures).to eq []
        expect(known).to eq [ 'Healing Potion (Minor)' ]
        expect(char.pf2_money).to eq purse - Crafting.price(1)
      end

      it "should refuse one they already know, and one they cannot afford" do
        run(PF2FormulaBuyCmd, 'formula/buy consumables=healing potion (minor)')
        run(PF2FormulaBuyCmd, 'formula/buy consumables=healing potion (minor)')

        expect(@client.failures.last).to eq t('pf2e.formula_known', :formula => 'Healing Potion (Minor)')

        char.update(:pf2_money => 1)
        run(PF2FormulaBuyCmd, 'formula/buy consumables=healing potion (lesser)')

        expect(@client.failures.last).to eq t('pf2egear.not_enough_you', :item => 'money for that formula')
      end

      it "should record how it was come by, so it can be explained and taken back" do
        run(PF2FormulaBuyCmd, 'formula/buy consumables=healing potion (minor)')

        explained = Ledger.explain_for(char, :kind => 'grant_formula', :key => 'Healing Potion (Minor)')

        expect(explained.first['source_type']).to eq 'bought'

        Crafting.forget!(char, 'consumables', 'Healing Potion (Minor)', :by => 'Staff')

        expect(known).to eq []
      end

      # Once a character is finalized the book is folded from the ledger like the rest of the sheet.
      it "should fold onto the sheet for a character the ledger owns" do
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        Ledger.seed_from_sheet!(char)

        Crafting.learn!(char, 'consumables', 'Healing Potion (Minor)', :source_type => 'staff', :source_ref => 'given')

        expect(known).to eq [ 'Healing Potion (Minor)' ]
        expect(Ledger.derived(char)['formulas']).to eq('consumables' => [ 'Healing Potion (Minor)' ])

        Crafting.forget!(char, 'consumables', 'Healing Potion (Minor)', :by => 'Staff')

        expect(known).to eq []
      end

      describe "working one out from an item" do
        before(:each) do
          @potion = PF2Consumable.create(:name => 'Healing Potion (Minor)', :quantity => 1, :character => @char)
        end

        after(:each) { PF2Consumable[@potion.id]&.delete }

        it "should refuse an item they do not carry" do
          run(PF2FormulaReverseCmd, 'formula/reverse consumables=healing potion (lesser)')

          expect(@client.failures.last).to eq t('pf2e.formula_not_held', :item => 'Healing Potion (Lesser)')
        end

        it "should learn it on a success, paying for the materials" do
          purse = char.pf2_money

          run(PF2FormulaReverseCmd, 'formula/reverse consumables=healing potion (minor)')

          expect(@client.failures).to eq []
          expect(known).to eq [ 'Healing Potion (Minor)' ]
          expect(char.pf2_money).to eq purse - Crafting.price(1)
        end

        it "should waste half the materials on a critical failure, and teach them nothing" do
          allow(Pf2e).to receive(:roll_dice).and_return([ 1 ])
          purse = char.pf2_money

          run(PF2FormulaReverseCmd, 'formula/reverse consumables=healing potion (minor)')

          expect(known).to eq []
          expect(char.pf2_money).to eq purse - (Crafting.price(1) / 2)
        end
      end
    end
  end
end
