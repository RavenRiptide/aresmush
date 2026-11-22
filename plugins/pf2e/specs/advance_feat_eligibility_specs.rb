require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # advance/feat asks whose a feat is. A class feat's class is in `assoc_charclass`, not `prereq`, and
    # advance/feat checked only `prereq`, so a wizard could take a fighter's Double Slice while advancing.
    describe "advance/feat eligibility", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        allow(Jobs).to receive(:notify)
        allow(Login).to receive(:notify)

        @char = Character.create(:name => "Wiz#{rand(1000000)}")
        @builder = AutoBuilder.new(@char)
        @builder.build_level_one('Wizard', ancestry: 'Human', heritage: 'Skilled', option: 'Spell Substitution')

        @char = Character[@char.id]
        Roles.add_role(@char, 'approved')
        @char = Character[@char.id]
        Ledger.commit_chargen!(@char)

        @char = Character[@char.id]
        @builder.instance_variable_set(:@char, @char)
        @builder.settle_familiar
        Pf2e.award_xp(@char, 3000, 'spec', 'level')
        @char = Character[@char.id]
        @builder.instance_variable_set(:@char, @char)

        run 'advance'
        expect(@builder.failures).to be_empty
      end

      after(:each) do
        @char.delete if @char
      end

      def run(text)
        @builder.clear
        @char = @builder.run(text)
      end

      def class_feats
        Array((Character[@char.id].pf2_advancement['feats'] || {})['charclass'])
      end

      it "should refuse another class's feat" do
        run 'advance/feat charclass=Double Slice'

        expect(@builder.failures.join(' ')).to include t('pf2e.does_not_qualify')
        expect(class_feats).not_to include 'Double Slice'
      end

      it "should take a feat for their own class" do
        run 'advance/feat charclass=Reach Spell'

        expect(@builder.failures).to be_empty
        expect(class_feats).to include 'Reach Spell'
      end

      # The command refuses exactly what the eligible-feat list leaves out.
      it "should agree with advance/info about another class's feats" do
        listed = Pf2e.get_feat_options(Character[@char.id], 'charclass')

        expect(listed).not_to include 'Double Slice'
        expect(listed).to include 'Reach Spell'
      end
    end
  end
end
