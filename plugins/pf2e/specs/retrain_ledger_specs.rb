require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Retraining against a real character, and what a rollback does with it.
    describe "retraining on the ledger", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Retrain#{rand(100000)}")
        @char = AutoBuilder.new(@char).build('Fighter', 3)
      end

      after(:each) do
        @char.delete if @char
      end

      def feats(char)
        (Character[char.id].pf2_feats || {}).values.flatten
      end

      # The general feat the level 3 slot holds, and one it could be retrained into.
      def general_at_three
        row = Ledger.rows(@char).find do |g|
          g['reverted_by'].blank? && g['kind'] == 'grant_feat' && g['effective_level'].to_i == 3 &&
            g['payload']['bucket'] == 'general'
        end

        row['payload']['feat']
      end

      def replacement
        held = feats(@char).map(&:upcase)

        [ 'Diehard', 'Incredible Initiative', 'Breath Control', 'Fleet' ].find { |name| !held.include?(name.upcase) }
      end

      def retrain(old, new)
        found = Pf2e.get_feat_details(old)
        Retrain.retrain!(@char, Retrain.taking(@char, old), found[1], new, :by => 'Staff')
        @char = Character[@char.id]
      end

      it "should find the slot a feat was taken in" do
        old = general_at_three

        expect(Retrain.taking(@char, old)).to eq('feat' => old, 'bucket' => 'general', 'level' => 3)
      end

      it "should swap the feat in the same slot" do
        old = general_at_three
        new = replacement

        retrain(old, new)

        expect(feats(@char)).to include new
        expect(feats(@char)).not_to include old
        expect(Retrain.taking(@char, new)).to eq('feat' => new, 'bucket' => 'general', 'level' => 3)
      end

      it "should take a retrain back with its level, and put it back on a redo" do
        old = general_at_three
        new = replacement

        retrain(old, new)

        expect(Pf2e.rollback_to_level(@char, 3)).to be_nil
        expect(feats(@char)).not_to include new
        expect(feats(@char)).not_to include old

        expect(Pf2e.redo_rollback(@char)).to be_nil
        expect(feats(@char)).to include new
        expect(feats(@char)).not_to include old
      end

      it "should leave a retrain alone when a later level is rolled back" do
        builder = AutoBuilder.new(@char)
        @char = builder.build('Fighter', 4)
        old = general_at_three
        new = replacement

        retrain(old, new)

        expect(Pf2e.rollback_to_level(@char, 4)).to be_nil
        expect(feats(@char)).to include new
        expect(feats(@char)).not_to include old
      end

      describe "through admin/retrain" do
        before(:each) do
          @staff = Character.create(:name => "Boss#{rand(1000000)}")
          Roles.add_role(@staff, 'admin')
          @staff = Character[@staff.id]
          @client = AutoBuilder::CaptureClient.new
        end

        after(:each) { @staff.delete if @staff }

        def retrain_cmd(text)
          @client.clear
          PF2AdminRetrainCmd.new(@client, Command.new("admin/retrain #{@char.name}=#{text}"), Character[@staff.id]).on_command
          @char = Character[@char.id]
        end

        it "should retrain the feat and say so" do
          retrain(general_at_three, 'Diehard')

          retrain_cmd("Diehard/Fleet")

          expect(@client.failures).to be_empty
          expect(@client.successes.first).to include 'Fleet'
          expect(feats(@char)).to include 'Fleet'
          expect(feats(@char)).not_to include 'Diehard'
        end

        it "should refuse a feat that gave more than other feats" do
          retrain(general_at_three, 'Arcane Sense')

          retrain_cmd("Arcane Sense/Fleet")

          expect(@client.failures).to eq [ I18n.t('pf2e.retrain_old_grants', :feat => 'Arcane Sense') ]
          expect(feats(@char)).to include 'Arcane Sense'
        end

        it "should refuse a feat of another type and change nothing" do
          old = general_at_three

          retrain_cmd("#{old}/Reach Spell")

          expect(@client.failures.first).to include 'Reach Spell'
          expect(feats(@char)).to include old
        end

        it "should refuse a feat the character doesn't have" do
          retrain_cmd("Bestial Manifestation/Fleet")

          expect(@client.failures).not_to be_empty
        end

        it "should refuse anyone without the permission" do
          @client.clear
          PF2AdminRetrainCmd.new(@client, Command.new("admin/retrain #{@char.name}=#{general_at_three}/#{replacement}"),
                                 Character[@char.id]).on_command

          expect(@client.failures).to eq [ I18n.t('dispatcher.not_allowed') ]
        end
      end

      # What the level-up commit does when a level's draft takes a feat away.
      describe "a level revoking an earlier level's grant" do
        def class_feat_at_one
          Ledger.rows(@char).find { |g| g['reverted_by'].blank? && g['kind'] == 'grant_feat' && g['payload']['bucket'] == 'charclass' }
        end

        before(:each) do
          @row = class_feat_at_one
          @feat = @row['payload']['feat']

          Ledger.revert_matching!(@char, 'grant_feat', { 'feat' => @feat, 'bucket' => 'charclass' },
                                  :by => Ledger.level_revocation_marker(3), :limit => 1)
          @char = Character[@char.id]
        end

        it "should bring the grant back when that level is rolled back" do
          expect(feats(@char)).not_to include @feat

          expect(Pf2e.rollback_to_level(@char, 3)).to be_nil

          expect(feats(@char)).to include @feat
        end

        it "should revoke it again on a redo" do
          Pf2e.rollback_to_level(@char, 3)
          expect(Pf2e.redo_rollback(@char)).to be_nil

          expect(feats(@char)).not_to include @feat
        end

        it "should keep it once the rolled-back level is taken again" do
          expect(Pf2e.rollback_to_level(@char, 3)).to be_nil
          expect(Character[@char.id].pf2_rollback_marker).not_to be_blank

          Ledger.supersede_rollback!(Character[@char.id], 3)

          expect(Pf2eGrant[@row['id']].reverted_by).to be_nil
          expect(Pf2eGrant[@row['id']].restored_by).to be_nil
        end
      end
    end
  end
end
