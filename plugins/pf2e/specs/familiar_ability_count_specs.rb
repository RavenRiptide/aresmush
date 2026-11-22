require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # How many abilities a familiar has each day, as the feats and features that give one write it. A base
    # (Pet's 2, Enhanced Familiar's 4) is set first and anything added goes on top, because the rows that
    # set it name an earlier priority. The witch's count includes the patron's ability, as Foundry's does.
    describe "a familiar's ability count", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Count#{rand(1000000)}", :pf2_level => 1, :pf2_conditions => {},
                                 :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {}, :pf2_features => {},
                                 :pf2_base_info => {})
      end

      after(:each) { @char.delete }

      def count(charclass:, level: 1, feats: {}, features: [], specialize: nil, option: nil)
        info = { 'charclass' => charclass, 'specialize' => specialize, 'specialize_info' => option }.compact
        @char.update(:pf2_base_info => info, :pf2_level => level, :pf2_feats => feats,
                     :pf2_features => { 'charclass_features' => features })

        reread = Character[@char.id]
        Paths.apply_all!(reread)

        Paths.held(Character[@char.id], 'familiarabilities-value')
      end

      it "should give the Pet feat 2" do
        expect(count(:charclass => 'Fighter', :feats => { 'general' => [ 'Pet' ] })).to eq 2
      end

      it "should give the Familiar feat 2" do
        expect(count(:charclass => 'Wizard', :feats => { 'charclass' => [ 'Familiar' ] })).to eq 2
      end

      it "should give Enhanced Familiar 4" do
        expect(count(:charclass => 'Wizard', :level => 2, :feats => { 'charclass' => [ 'Familiar', 'Enhanced Familiar' ] })).to eq 4
      end

      it "should add Leshy Familiar Secrets' one to the base" do
        feats = { 'charclass' => [ 'Leshy Familiar', 'Leshy Familiar Secrets' ] }

        expect(count(:charclass => 'Druid', :level => 4, :feats => feats, :specialize => 'Leaf')).to eq 3
      end

      it "should add Leshy Familiar Secrets' one to Enhanced Familiar's base" do
        feats = { 'charclass' => [ 'Leshy Familiar', 'Enhanced Familiar', 'Leshy Familiar Secrets' ] }

        expect(count(:charclass => 'Druid', :level => 4, :feats => feats, :specialize => 'Leaf')).to eq 5
      end

      # 2, plus the witch's 2 + min(3, floor(level / 6)): the extra ability and the patron's.
      it "should give a first-level witch 4" do
        expect(count(:charclass => 'Witch', :features => [ 'Familiar' ])).to eq 4
      end

      it "should give a sixth-level witch with Enhanced Familiar 7" do
        feats = { 'charclass' => [ 'Enhanced Familiar' ] }

        expect(count(:charclass => 'Witch', :level => 6, :feats => feats, :features => [ 'Familiar' ])).to eq 7
      end

      it "should give a witch no more than three extra at 18th level and beyond" do
        expect(count(:charclass => 'Witch', :level => 20, :features => [ 'Familiar' ])).to eq 7
      end

      # A dedicant gets "the normal number of abilities for a familiar", and Basic Witchcraft three.
      it "should give Witch Dedication 2, without the witch's extra abilities" do
        expect(count(:charclass => 'Wizard', :level => 2, :feats => { 'dedication' => [ 'Witch Dedication' ] })).to eq 2
      end

      it "should give Basic Witchcraft 3" do
        feats = { 'dedication' => [ 'Witch Dedication', 'Basic Witchcraft' ] }

        expect(count(:charclass => 'Wizard', :level => 4, :feats => feats)).to eq 3
      end

      it "should add Improved Familiar Attunement's bonus to a wizard's familiar" do
        expect(count(:charclass => 'Wizard', :level => 1, :feats => { 'charclass' => [ 'Familiar' ] },
                     :option => 'Improved Familiar Attunement')).to eq 3
        expect(count(:charclass => 'Wizard', :level => 6, :feats => { 'charclass' => [ 'Familiar' ] },
                     :option => 'Improved Familiar Attunement')).to eq 4
      end

      it "should read Improved Familiar Attunement as a wizard's option, not another class's" do
        expect(count(:charclass => 'Sorcerer', :feats => { 'charclass' => [ 'Familiar' ] },
                     :option => 'Improved Familiar Attunement')).to eq 2
      end

      it "should write nothing for a character with no familiar" do
        expect(count(:charclass => 'Fighter')).to be_nil
      end

      # Multilingual's counter is reset to nothing before each taking adds one, so the reset comes first.
      it "should count Multilingual once taken" do
        count(:charclass => 'Fighter', :feats => { 'skill' => [ 'Multilingual' ] })

        expect(Paths.held(Character[@char.id], 'flags.system.multilingualTaken')).to eq 1
      end
    end
  end
end
