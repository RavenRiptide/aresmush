require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # A witch familiar taking over: a human wizard who took the Familiar feat through Natural Ambition takes
    # Witch Dedication, owes a retrain of Familiar in that level, and makes it with advance/retrain.
    describe "retraining a familiar feat in a level", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        allow(Jobs).to receive(:notify)
        allow(Login).to receive(:notify)

        @char = Character.create(:name => "Wiz#{rand(1000000)}")
        @builder = AutoBuilder.new(@char)
        @builder.prefer.merge!('ancestry' => 'Natural Ambition', 'Natural Ambition' => 'Familiar')
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
      end

      after(:each) do
        @char.delete if @char
      end

      def run(text)
        @builder.clear
        @char = @builder.run(text)
      end

      def feats
        (Character[@char.id].pf2_feats || {}).values.flatten
      end

      def choices
        Pf2e.recorded_choices(Character[@char.id]).map { |name, label, _level| [ name, label ] }
      end

      def replacement
        held = feats.map(&:upcase)
        [ 'Reach Spell', 'Widen Spell' ].find { |name| !held.include?(name.upcase) }
      end

      def take_witch_dedication
        run 'advance'
        expect(@builder.failures).to be_empty

        run 'advance/feat charclass=Witch Dedication'
        expect(@builder.failures).to be_empty
      end

      it "should start with an approved familiar from the Familiar feat Natural Ambition gave" do
        expect(feats).to include 'Natural Ambition'
        expect(feats).to include 'Familiar'
        expect(Pf2e.recorded_choices(@char).map { |name, label, _| [ name, label ] }).to include [ 'Natural Ambition', 'Familiar' ]
        expect(Familiar.main_source(@char)['name']).to eq 'Familiar'
        expect(Familiar.awaiting_approval?(@char)).to be false
      end

      it "should owe a retrain of Familiar once Witch Dedication is taken" do
        take_witch_dedication

        owed = Character[@char.id].pf2_advancement['retrains']
        expect(owed.map { |one| one['from'] }).to eq [ 'Familiar' ]
        expect(owed.first).to include('bucket' => 'charclass', 'level' => 1, 'to' => nil)
        expect(@builder.instance_variable_get(:@client).oocs.join(' ')).to include 'advance/retrain'
      end

      # The old familiar's details carry over, so the player isn't told to set them as if it were new.
      it "should say the patron's familiar takes the old one's place, keeping its details" do
        name = Familiar.record(@char)['approved']['name']
        take_witch_dedication

        said = @builder.instance_variable_get(:@client).oocs.join(' ')
        expect(said).to include t('pf2e.familiar_taken_over', :name => name)
        expect(said).to include t('pf2e.familiar_patron_request', :url => Familiar.patron_wiki_url)
        expect(said).not_to include t('pf2e.familiar_gained')
      end

      # advance/info retrain lists what advance/retrain accepts, by the same checks.
      it "should list the feats the retrain accepts, and only those" do
        take_witch_dedication
        owed = Retrain.owed(Character[@char.id])

        listed = Retrain.options(Character[@char.id], owed)

        expect(listed).to include 'Reach Spell'
        expect(listed).not_to include 'Bespell Strikes'
        expect(listed).not_to include 'Familiar'

        # Another class's feats: Double Slice is a fighter's, Cackle a witch's (Witch Dedication doesn't
        # make them a witch for class feats).
        expect(listed).not_to include 'Double Slice'
        expect(listed).not_to include 'Cackle'
        other_class = listed.reject do |name|
          classes = Pf2e.get_feat_details(name)[1]['assoc_charclass']
          classes.nil? || classes.include?('Wizard')
        end
        expect(other_class).to eq []

        char = Character[@char.id]
        listed.sample(5).each do |name|
          details = Pf2e.get_feat_details(name)[1]
          expect(Retrain.check(owed, {}, name, details)).to be_nil
          expect(Retrain.sheet_block(char, owed, name, details)).to be_nil
        end

        run 'advance/info retrain=reach'
        expect(@builder.instance_variable_get(:@client).successes.join(' ')).to include 'Reach Spell'
      end

      it "should offer retrain at advance/info" do
        take_witch_dedication

        expect(Advancement::Outstanding.labels(CharState.of(Character[@char.id]))).to include 'retrain'
      end

      it "should refuse to finish the level until the retrain is made" do
        take_witch_dedication
        6.times { break if @builder.resolve_outstanding(:advance).zero? }

        run 'advance/done'

        expect(@builder.failures.join(' ')).to include 'Familiar'
        expect(Character[@char.id].advancing).to be true
      end

      it "should refuse a replacement above the old feat's level" do
        take_witch_dedication

        run 'advance/retrain Bespell Strikes'

        expect(@builder.failures).not_to be_empty
        expect(Character[@char.id].pf2_advancement['retrains'].first['to']).to be_nil
      end

      describe "once retrained" do
        before(:each) do
          take_witch_dedication
          @new = replacement
          run "advance/retrain #{@new}"
          expect(@builder.failures).to be_empty
        end

        it "should count the replacement and not the old feat while the level is open" do
          names = DraftSheet.of(Character[@char.id]).feat_names

          expect(names).to include @new.upcase
          expect(names).not_to include 'FAMILIAR'
        end

        it "should write the swap to the sheet when the level finishes, and take it back with the level" do
          run 'advance/archetype specialty=Night'
          run 'advance/spell spellbook/witch archetype/cantrip=Daze'
          run 'advance/spell spellbook/witch archetype/cantrip=Figment'
          expect(@builder.failures).to be_empty
          6.times { break if @builder.resolve_outstanding(:advance).zero? }
          @builder.settle_familiar
          run 'advance/done'

          expect(@builder.failures).to be_empty
          expect(feats).to include @new
          expect(feats).to include 'Witch Dedication'
          expect(feats).not_to include 'Familiar'

          # Natural Ambition's choice was Familiar, so the choice moves with the retrain.
          expect(choices).to include [ 'Natural Ambition', @new ]
          expect(choices).not_to include [ 'Natural Ambition', 'Familiar' ]

          expect(Pf2e.rollback_to_level(Character[@char.id], 2)).to be_nil
          expect(choices).to include [ 'Natural Ambition', 'Familiar' ]
          expect(choices).not_to include [ 'Natural Ambition', @new ]
          expect(feats).to include 'Familiar'
          expect(feats).not_to include @new
          expect(feats).not_to include 'Witch Dedication'
        end
      end
    end
  end
end
