require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # An animal companion through the real commands: a druid of the animal order chooses a wolf in chargen,
    # sees it on cg/review, matures it at 4 and makes it savage at 8, with advance/review saying what each of
    # those levels changes; the one-companion and Bonded Animal refusals; and a goblin champion's faithful
    # steed, which may be a horse or, for a Rough Rider, a wolf.
    describe "animal companion feats", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        allow(Jobs).to receive(:notify)
        allow(Login).to receive(:notify)
      end

      after(:each) do
        @char.delete if @char
      end

      def make(name)
        @char = Character.create(:name => "#{name}#{rand(1000000)}")
        @builder = AutoBuilder.new(@char)
      end

      def approve
        @char = Character[@char.id]
        Roles.add_role(@char, 'approved')
        @char = Character[@char.id]
        Ledger.commit_chargen!(@char)
        @char = Character[@char.id]
        @builder.instance_variable_set(:@char, @char)
      end

      def run(text)
        @builder.clear
        @char = @builder.run(text)
      end

      def said
        (@builder.client.successes + @builder.client.oocs).join("\n")
      end

      # What was said as the player reads it, without colour codes: %r a line break, %b a space.
      def shown
        said.gsub('%r', "\n").gsub('%b', ' ').gsub(/%x(\d+|[a-z!])/i, '')
      end

      # One level, taking `feat` in the class feat slot, with everything else picked as AutoBuilder would.
      def level_up(feat = nil)
        run 'advance'
        expect(@builder.failures).to be_empty
        run "advance/feat charclass=#{feat}" if feat
        expect(@builder.failures).to be_empty
        6.times { break if @builder.resolve_outstanding(:advance).zero? }
        @char = @builder.char
        run 'advance/done'
        expect(@builder.failures).to be_empty
      end

      def climb_to(target, feats = {})
        Pf2e.award_xp(@char, (target + 2) * 1000, 'spec', 'level')
        @char = Character[@char.id]
        @builder.instance_variable_set(:@char, @char)
        ((@char.pf2_level + 1)..target).each { |level| level_up(feats[level]) }
      end

      def companion
        Companion.list(Character[@char.id]).first
      end

      describe "a druid of the animal order" do
        before(:each) do
          make('Druid')
          @builder.prefer.merge!('Animal Companion' => 'Wolf')
          @builder.build_level_one('Druid', specialty: 'Animal')
          @char = Character[@char.id]
        end

        it "should choose the order's companion's type in chargen" do
          expect(Companion.sources(@char)).to eq [ 'Animal Companion' ]
          expect(companion.values_at('type', 'mature', 'path')).to eq [ 'Wolf', false, nil ]
        end

        it "should offer the common types, and never Riding Drake" do
          offered = Pf2e.choice_options(@char, 'Animal Companion', Pf2e.find_choice_block(@char, 'Animal Companion'))

          # The wolf already chosen is left out, as any choice already made is.
          expect(offered).to include('Bear', 'Horse (Large)')
          expect(offered).not_to include('Wolf', 'Riding Drake', 'Arboreal Sapling')
        end

        it "should show the wolf on cg/review, pointing to its sheet for its stats" do
          run 'cg/review'

          expect(said).to include(t('pf2e.companion_review_title'))
          expect(said).to include('Wolf (young)')
          expect(said).to include(t('pf2e.companion_review_note'))
          expect(said).not_to include('Jaws')
        end

        it "should refuse a second companion and Bonded Animal, saying why" do
          steed = Global.read_config('pf2e_feats', 'Faithful Steed')
          bonded = Global.read_config('pf2e_feats', 'Bonded Animal')

          expect(Pf2e.can_take_feat_details?(@char, 'Faithful Steed', steed, nil, true)).to be false
          expect(Pf2e.explain_feat_block(@char, steed)).to eq t('pf2e.companion_one_only', :source => 'Animal Companion')
          expect(Pf2e.explain_feat_block(@char, bonded)).to eq t('pf2e.companion_bonded_animal')
        end

        describe "advancing" do
          before(:each) do
            approve
            climb_to(3)
          end

          it "should mature at 4, saying so on advance/review and advance/done" do
            Pf2e.award_xp(@char, 2000, 'spec', 'level')
            run 'advance'
            run 'advance/feat charclass=Mature Animal Companion (Druid)'
            run 'advance/review'

            expect(shown).to include('Animal Companion:')
            expect(shown).to include('Stage: Mature')
            expect(shown).to include('Size: Medium')
            expect(said).to include(t('pf2e.companion_level_unnamed'))
            expect(shown).not_to include('→')

            6.times { break if @builder.resolve_outstanding(:advance).zero? }
            @char = @builder.char
            run 'advance/done'

            expect(@builder.failures).to be_empty
            expect(said).to include(t('pf2e.companion_done_stage', :subject => t('pf2e.companion_subject_unnamed'), :stage => 'mature'))
            expect(companion['mature']).to be true
          end

          it "should say nothing about the companion at a level that leaves it as it was" do
            climb_to(4, 4 => 'Mature Animal Companion (Druid)')
            Pf2e.award_xp(@char, 2000, 'spec', 'level')
            run 'advance'
            run 'advance/review'

            expect(shown).not_to include('Animal Companion:')
          end

          it "should wait at 8 for nimble or savage, then show what savage changes" do
            climb_to(7, 4 => 'Mature Animal Companion (Druid)')
            Pf2e.award_xp(@char, 2000, 'spec', 'level')
            run 'advance'
            run 'advance/feat charclass=Incredible Companion (Druid)'
            run 'advance/review'

            expect(shown).not_to include('Stage: Savage')

            run 'advance/option Incredible Companion (Druid)=Savage'
            expect(@builder.failures).to be_empty
            run 'advance/review'

            expect(shown).to include('Stage: Savage')
            expect(shown).to include('Size: Large')
            expect(shown).to include('Advanced Maneuver: Takedown')

            6.times { break if @builder.resolve_outstanding(:advance).zero? }
            @char = @builder.char
            run 'advance/done'

            expect(@builder.failures).to be_empty
            expect(companion['path']).to eq 'savage'
            expect(Companion.stats(Character[@char.id], companion)['size']).to eq 'Large'
          end
        end
      end

      describe "a goblin champion" do
        before(:each) do
          make('Steed')
          @builder.prefer.merge!('ancestry' => 'Rough Rider', 'charclass' => 'Faithful Steed', 'Faithful Steed' => 'Wolf')
          @builder.build_level_one('Champion', ancestry: 'Goblin', heritage: 'Irongut')
          @char = Character[@char.id]
        end

        it "should offer a Rough Rider's faithful steed only mounts and a wolf, and take the wolf as a mount" do
          offered = Pf2e.choice_options(@char, 'Faithful Steed', Pf2e.find_choice_block(@char, 'Faithful Steed'))

          expect(DraftSheet.of(@char).feat_names).to include('ROUGH RIDER', 'FAITHFUL STEED')
          expect(companion['type']).to eq 'Wolf'
          expect(offered + [ 'Wolf' ]).to match_array [ 'Horse (Medium)', 'Horse (Large)', 'Wolf' ]
          expect(Companion.stats(@char, companion)['mount']).to be true
        end
      end
    end
  end
end
