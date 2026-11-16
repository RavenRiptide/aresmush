require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # sheet/history, sheet/feats and sheet/features against a character built through the real
    # commands, so the levels come from real commit boundaries rather than rows made up for a spec.
    describe "a sheet by level", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "History#{rand(100000)}")
      end

      after(:each) do
        @char.delete if @char
      end

      def shown(char, section, range = nil)
        template = Pf2eSheetTemplate.new(char, section, double(:screen_reader => false), char.pf2_base_info, char.pf2_faith)
        template.history_range = range

        SheetReads.holding(char) { template.render }.gsub(/%x(?:\d{1,3}|[a-zA-Z])/, '').gsub('%b', ' ')
      end

      it "should list what each level gave, from level 1 up" do
        char = AutoBuilder.new(@char).build('Fighter', 4)
        text = shown(char, 'history')

        expect(text).to include('Level 1:', 'Level 2:', 'Level 3:', 'Level 4:')
        expect(text).not_to include('Before level tracking')
        expect(text).to match(/Class feats?: /)
        expect(text).to include('Attribute boost')
      end

      it "should keep to the levels asked for" do
        char = AutoBuilder.new(@char).build('Fighter', 4)
        text = shown(char, 'history', 2..3)

        expect(text).to include('Level 2:', 'Level 3:')
        expect(text).not_to include('Level 1:', 'Level 4:')
      end

      it "should list feats and features by level, with the feat's type in words" do
        char = AutoBuilder.new(@char).build('Fighter', 2)

        expect(shown(char, 'feats')).to match(/Level 2: .*\(class feat\)/)
        expect(shown(char, 'features')).to include('Level 1:')
      end

      it "should say a level is in progress while it is being drafted" do
        builder = AutoBuilder.new(@char)
        builder.build('Fighter', 2)
        builder.run "advance"

        expect(shown(Character[@char.id], 'history')).to include('Level 3 is in progress')
      end

      it "should say an unapproved character has no history yet" do
        # A level 1 build is a finished chargen that hasn't been approved.
        char = AutoBuilder.new(@char).build('Fighter', 1)

        expect(Ledger.finalized?(char)).to be false
        expect(shown(char, 'history')).to include("history starts when they're approved")
      end
    end
  end
end
