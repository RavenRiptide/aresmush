require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Formulas a class or feat hands over, picked through the real commands: what lands in the book at
    # chargen and at each level, and that a rollback takes a level's picks back with the level.
    describe "granted formulas", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Formulist#{rand(1000000)}")
        @builder = AutoBuilder.new(@char)
      end

      after(:each) do
        Pf2eGrant.find(:character_id => @char.id).each(&:delete)
        @char.delete
      end

      def book
        (Character[@char.id].pf2_formula_book || {}).values.flatten
      end

      def item(name)
        Global.read_config('pf2e_consumables', name) || {}
      end

      def traits(name)
        Array(item(name)['traits'])
      end

      it "should fill an alchemist's book from the class, its research field and Alchemical Crafting" do
        @builder.build_level_one('Alchemist')

        expect(Character[@char.id].pf2_base_info['specialize']).to eq 'Bomber'
        expect(book.size).to eq 8
        expect(book).to all(satisfy { |name| traits(name).include?('alchemical') && item(name)['level'].to_i <= 1 })
        expect(book.count { |name| traits(name).include?('bomb') }).to be >= 2
      end

      it "should take picked formulas back with the chargen stage they were picked in" do
        @builder.build_level_one('Alchemist')
        expect(book.size).to eq 8

        @builder.clear
        @builder.run "cg/restore info"

        expect(@builder.failures).to eq []
        expect(book).to eq []
      end

      it "should take back only the last formula picked with cg/undo" do
        @builder.build_level_one('Alchemist')
        before = book.sort

        # The build ends on other steps, so undo back to the last formula picked.
        @builder.clear
        5.times do
          break if book.size < before.size

          @builder.run "cg/undo"
        end

        expect(@builder.failures).to eq []
        expect(book.size).to eq 7
        expect(before - book.sort).to eq [ (before - book.sort).first ]
        expect(Character[@char.id].pf2_to_assign['feat choice'].values.flatten).to include 'open'
      end

      it "should add two formulas at each level, and take a level's back when the level is rolled back" do
        @builder.build('Alchemist', 3)

        expect(@builder.summary['level']).to eq 3
        expect(book.size).to eq 12

        # Back to just before 3rd level, which keeps 2nd level's picks.
        expect(Pf2e.rollback_to_level(Character[@char.id], 3, Character[@char.id])).to be_nil
        expect(Character[@char.id].pf2_level).to eq 2
        expect(book.size).to eq 10
      end

      it "should keep a formula bought while a level was open when the level commits" do
        @builder.build('Alchemist', 2)
        Pf2egear.pay_player(Character[@char.id], 1000, 'Spec', 'formula money')

        @builder.clear
        @builder.run "advance"
        @builder.run "formula/buy consumables=healing potion (minor)"
        expect(@builder.failures).to eq []

        6.times { break if @builder.resolve_outstanding(:advance).zero? }
        @builder.run "advance/done"

        expect(@builder.summary['level']).to eq 3
        expect(book).to include 'Healing Potion (Minor)'
        expect(book.size).to eq 13
      end

      it "should give an investigator of alchemical sciences elixirs or tools, two at first and one a level" do
        @builder.build('Investigator', 2)

        expect(Character[@char.id].pf2_base_info['specialize']).to eq 'Alchemical Sciences'
        expect(book.size).to eq 7
        expect(book.count { |name| traits(name).include?('elixir') || item(name)['subcategory'] == 'tool' }).to be >= 3
      end

      it "should open Cauldron's repeat pick at 4th level, for a witch who took it through Natural Ambition" do
        allow(@builder).to receive(:feat_pick).and_wrap_original do |original, type|
          type.to_s == 'ancestry' ? 'Natural Ambition' : original.call(type)
        end

        allow(Pf2e).to receive(:choice_options).and_wrap_original do |original, char, name, block|
          name.to_s.casecmp?('Natural Ambition') ? [ 'Cauldron' ] : original.call(char, name, block)
        end

        @builder.build_level_one('Witch', :ancestry => 'Human', :heritage => 'Skilled')

        expect(DraftSheet.of(Character[@char.id]).feat_names.map(&:downcase)).to include 'cauldron'
        expect(book.size).to eq 4
        expect(book).to all(satisfy { |name| (traits(name) & [ 'oil', 'potion' ]).any? && item(name)['level'].to_i <= 1 })

        @builder.advance_to(3)
        expect(book.size).to eq 4

        @builder.advance_to(4)
        expect(@builder.summary['level']).to eq 4
        expect(book.size).to eq 5
      end
    end
  end
end
