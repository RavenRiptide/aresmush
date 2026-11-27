require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # What a feat hands over besides feats: a class feature or an action (`grants: feature:`), and feats it
    # gives once their prerequisites are met (`feats_when_eligible`, Raging Intimidation).
    describe "feats that hand things over", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Handover#{rand(1000000)}", :pf2_level => 1,
                                 :pf2_base_info => { 'charclass' => 'Barbarian', 'ancestry' => 'Human' },
                                 :pf2_feats => { 'charclass' => [] }, :pf2_advancement => {},
                                 :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @skill = Pf2eSkills.create(:character => @char, :name => 'Intimidation', :prof_level => 'untrained')
      end

      after(:each) do
        @skill&.delete
        @char&.delete
      end

      def char
        Character[@char.id]
      end

      def features(bucket)
        (char.pf2_features || {})[bucket] || []
      end

      describe "a feature" do
        it "should file the features under the bucket the grant names" do
          Pf2e.do_feat_grants(char, { 'feature' => { 'archetype_features' => [ 'Flurry of Blows' ] } }, 'Barbarian', nil)

          expect(features('archetype_features')).to eq [ 'Flurry of Blows' ]
          expect(features('charclass_features')).to eq []
        end

        it "should file a plain list as class features, and not twice" do
          2.times { Pf2e.do_feat_grants(char, { 'feature' => [ 'Verdant Rest' ] }, 'Barbarian', nil) }

          expect(features('charclass_features')).to eq [ 'Verdant Rest' ]
        end

        it "should refuse a bucket the sheet has no place for" do
          Pf2e.do_feat_grants(char, { 'feature' => { 'feat_features' => [ 'Flurry of Blows' ] } }, 'Barbarian', nil)

          expect((char.pf2_features || {}).values.flatten).to eq []
        end

        it "should make the action the feature names theirs to use" do
          expect(Actions.usable(char, 'Flurry of Blows').ok?).to be false

          Pf2e.do_feat_grants(char, { 'feature' => { 'archetype_features' => [ 'Flurry of Blows' ] } }, 'Barbarian', nil)

          expect(Actions.usable(char, 'Flurry of Blows').ok?).to be true
        end
      end

      describe "feats once eligible" do
        def held
          DraftSheet.of(char).feat_names
        end

        def raging
          @char.update(:pf2_feats => { 'charclass' => [ 'Raging Intimidation' ] })
        end

        it "should give nothing while the prerequisites are unmet" do
          raging

          EligibleFeats.settle!(char, nil)

          expect(held).not_to include 'INTIMIDATING GLARE'
        end

        it "should give the feats whose prerequisites are met, and only those" do
          raging
          @skill.update(:prof_level => 'trained')

          EligibleFeats.settle!(char, nil)

          expect(held).to include 'INTIMIDATING GLARE'
          expect(held).not_to include 'SCARE TO DEATH'
        end

        it "should give the higher one at the level and rank it asks" do
          raging
          @char.update(:pf2_level => 15)
          @skill.update(:prof_level => 'legendary')

          EligibleFeats.settle!(char, nil)

          expect(held).to include 'INTIMIDATING GLARE', 'SCARE TO DEATH'
        end

        it "should not give a feat they already hold again" do
          @char.update(:pf2_feats => { 'charclass' => [ 'Raging Intimidation' ], 'skill' => [ 'Intimidating Glare' ] })
          @skill.update(:prof_level => 'trained')

          EligibleFeats.settle!(char, nil)

          expect(held.count('INTIMIDATING GLARE')).to eq 1
        end

        it "should give nothing to a character without the feat" do
          @skill.update(:prof_level => 'trained')

          EligibleFeats.settle!(char, nil)

          expect(held).not_to include 'INTIMIDATING GLARE'
        end
      end

      # The check runs as a level-up commits, so what it gives is that level's and goes with it.
      describe "through a level-up" do
        before(:each) do
          @skill.delete
          @skill = nil
          @char.delete
          @char = AutoBuilder.new(Character.create(:name => "Raging#{rand(100000)}")).build('Fighter', 3)

          Ledger.write(@char, :source_type => 'staff', :source_ref => 'spec', :effective_level => 3) do |txn|
            txn.grant('grant_feat', 'bucket' => 'charclass', 'feat' => 'Raging Intimidation')
            txn.grant('raise_skill', 'skill' => 'Intimidation', 'to' => 'trained')
          end
          @char = Character[@char.id]
        end

        def feats
          (Character[@char.id].pf2_feats || {}).values.flatten
        end

        it "should give the feat as the level commits, and take it back with the level" do
          expect(feats).not_to include 'Intimidating Glare'

          # The builder's own skill feat slot at 4th level never takes it, so only the check can give it.
          allow(Pf2e).to receive(:get_feat_options).and_wrap_original { |original, *args| original.call(*args) - [ 'Intimidating Glare' ] }
          AutoBuilder.new(@char).advance_to(4)

          expect(Character[@char.id].pf2_level).to eq 4
          expect(feats).to include 'Intimidating Glare'

          expect(Pf2e.rollback_to_level(Character[@char.id], 3)).to be_nil
          expect(feats).not_to include 'Intimidating Glare'
        end
      end
    end
  end
end
