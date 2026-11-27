require "plugin_test_loader"

module AresMUSH
  module Pf2e

    describe Retrain do

      def taking(feat: 'Pet', bucket: 'general', level: 3)
        { 'feat' => feat, 'bucket' => bucket, 'level' => level }
      end

      def general(level: 1, **extra)
        { 'feat_type' => [ 'General' ], 'prereq' => { 'level' => level } }.merge(extra.transform_keys(&:to_s))
      end

      # advance/info retrain: the feats advance/retrain would accept, by the same checks.
      describe "options" do
        before do
          feats = {
            'Fleet' => general(level: 1),
            'Toughness' => general(level: 3),
            'Incredible Initiative' => general(level: 4),
            'Reach Spell' => { 'feat_type' => [ 'Charclass' ], 'prereq' => { 'level' => 1 } },
            'Some Dedication' => { 'feat_type' => [ 'General', 'Dedication' ], 'prereq' => { 'level' => 2 } },
            'Sealed' => general(level: 1, no_retrain: 'into'),
            'Pet' => general(level: 1),
            'Picky' => general(level: 1),
            'Other Class' => general(level: 1)
          }
          allow(Global).to receive(:read_config).and_call_original
          allow(Global).to receive(:read_config).with('pf2e_feats').and_return(feats)
          allow(Pf2e).to receive(:get_feat_details) { |name| feats[name] ? [ name, feats[name] ] : 'missing' }
          allow(Pf2e).to receive(:feat_tally).and_return(Hash.new(0))
          allow(Familiar).to receive(:blocks?).and_return(false)
          allow(Pf2e::SheetReads).to receive(:holding).and_yield
          allow(Pf2e).to receive(:can_take_feat_details?) { |_char, name, _details, _level| name != 'Other Class' }
          allow(Retrain).to receive(:candidate_block).and_call_original
          allow(Retrain).to receive(:candidate_block)
            .with(anything, anything, 'Picky', anything, any_args).and_return('needs something')

          @char = double('char')
        end

        it "should list the feats of the slot's type, up to its level, that the sheet allows" do
          expect(Retrain.options(@char, taking.merge('from' => 'Pet'))).to eq [ 'Fleet', 'Toughness' ]
        end

        it "should leave out a feat above the slot, of another type, a Dedication, a no-retrain feat, and the old feat" do
          listed = Retrain.options(@char, taking.merge('from' => 'Pet'))

          expect(listed).not_to include('Incredible Initiative', 'Reach Spell', 'Some Dedication', 'Sealed', 'Pet')
        end

        it "should leave out a feat the sheet refuses" do
          expect(Retrain.options(@char, taking.merge('from' => 'Pet'))).not_to include 'Picky'
        end

        # A feat for another class or ancestry: `prereq` doesn't say so, `assoc_charclass` does, and only
        # `can_take_feat_details?` reads it. Without it a sorcerer was offered fighter and witch feats.
        it "should leave out a feat they couldn't take, asked at the slot's level" do
          listed = Retrain.options(@char, taking.merge('from' => 'Pet'))

          expect(listed).not_to include 'Other Class'
          expect(Pf2e).to have_received(:can_take_feat_details?).with(@char, 'Fleet', anything, 3)
        end
      end

      describe "check" do
        it "should allow a general feat no higher than the slot" do
          expect(Retrain.check(taking, general, 'Fleet', general(level: 3))).to be_nil
        end

        it "should refuse a feat above the slot's level" do
          result = Retrain.check(taking(level: 2), general, 'Fleet', general(level: 3))

          expect(result.code).to eq :retrain_too_high
        end

        it "should refuse a feat of another type" do
          result = Retrain.check(taking, general, 'Reach Spell', { 'feat_type' => [ 'Charclass' ], 'prereq' => { 'level' => 1 } })

          expect(result.code).to eq :retrain_bad_type
        end

        it "should let a skill feat fill a general slot, which its types say it can" do
          skill = { 'feat_type' => [ 'Skill', 'General' ], 'prereq' => { 'level' => 1 } }

          expect(Retrain.check(taking, general, 'Assurance', skill)).to be_nil
        end

        it "should refuse retraining a feat into itself" do
          expect(Retrain.check(taking, general, 'pet', general).code).to eq :retrain_same
        end

        it "should refuse retraining out of a feat that forbids it" do
          result = Retrain.check(taking(feat: 'Hag Claws', bucket: 'ancestry'), { 'no_retrain' => 'out' }, 'Fleet',
                                 { 'feat_type' => [ 'Ancestry' ], 'prereq' => { 'level' => 1 } })

          expect(result.code).to eq :retrain_out_forbidden
        end

        it "should refuse retraining into a feat that forbids it" do
          result = Retrain.check(taking(bucket: 'ancestry'), {}, 'Tusks (Oruch)',
                                 { 'feat_type' => [ 'Ancestry' ], 'prereq' => { 'level' => 1 }, 'no_retrain' => 'into' })

          expect(result.code).to eq :retrain_into_forbidden
        end

        it "should read both as forbidding either way" do
          expect(Retrain.forbids?({ 'no_retrain' => 'both' }, 'into')).to be true
          expect(Retrain.forbids?({ 'no_retrain' => 'both' }, 'out')).to be true
          expect(Retrain.forbids?({ 'no_retrain' => 'into' }, 'out')).to be false
          expect(Retrain.forbids?({}, 'out')).to be false
        end
      end

      describe "what a retrain can record" do
        it "should take back a feat whose only grant is other feats" do
          expect(Retrain.reversible?(general(grants: { 'feat' => [ 'Pet' ] }))).to be true
          expect(Retrain.granted_feats(general(grants: { 'feat' => [ 'Pet' ] }))).to eq [ 'Pet' ]
        end

        it "should refuse to take back a feat granting anything else, or opening a choice" do
          expect(Retrain.reversible?(general(grants: { 'skill' => [ 'Arcana' ] }))).to be false
          expect(Retrain.reversible?(general(feat_choice: { 'summary' => 'x' }))).to be false
        end

        it "should say a replacement with grants, choices or later clauses opens something" do
          expect(Retrain.opens_anything?(general)).to be false
          expect(Retrain.opens_anything?(general(grants: { 'feat' => [ 'Pet' ] }))).to be true
          expect(Retrain.opens_anything?(general(at_level: { 17 => {} }))).to be true
        end

        it "should take back a feat granting features, and name them with their buckets" do
          details = general(grants: { 'feat' => [ 'Pet' ], 'feature' => { 'archetype_features' => [ 'Flurry of Blows' ] } })

          expect(Retrain.reversible?(details)).to be true
          expect(Retrain.granted_features(details)).to eq [ [ 'archetype_features', 'Flurry of Blows' ] ]
        end

        it "should read a plain list of features as class features" do
          details = general(grants: { 'feature' => [ 'Verdant Rest' ] })

          expect(Retrain.granted_features(details)).to eq [ [ 'charclass_features', 'Verdant Rest' ] ]
        end

        # Raging Intimidation's feats arrive once their prerequisites are met, so a retrain takes back
        # whichever of them arrived, and one into it would have to open what a retrain cannot.
        it "should take back the feats a feat hands over once eligible" do
          details = general(feats_when_eligible: [ 'Intimidating Glare', 'Scare to Death' ])

          expect(Retrain.reversible?(details)).to be true
          expect(Retrain.granted_feats(details)).to eq [ 'Intimidating Glare', 'Scare to Death' ]
          expect(Retrain.opens_anything?(details)).to be true
        end
      end

      describe "the config's no_retrain flags" do
        it "should use only the words the check reads" do
          feats = %w(ancestry class dedication general skill).each_with_object({}) do |file, all|
            all.merge!(YAML.load_file("game/config/pf2e_feat_#{file}.yml")['pf2e_feats'])
          end
          flags = feats.filter_map { |_name, info| info['no_retrain'] }

          expect(flags).not_to be_empty
          expect(flags - Retrain::NO_RETRAIN).to be_empty
        end
      end
    end

    describe "what a rollback brings back" do
      def grant(id, reverted_by)
        { 'id' => id, 'reverted_by' => reverted_by }
      end

      it "should bring back what a level at or above the target revoked, and nothing else" do
        grants = [
          grant('1', 'level-5-1700000000'),
          grant('2', 'level-4-retrain-1700000000-7'),
          grant('3', 'level-6-1700000000'),
          grant('4', 'rollback-1700000000-1-to-5'),
          grant('5', nil)
        ]

        expect(Ledger.level_revoked_ids(grants, 5)).to eq [ '1', '3' ]
      end

      it "should write markers the rollback reads" do
        expect(Ledger.level_revocation_marker(4, 'retrain')).to match(Ledger::LEVEL_REVOCATION)
        expect(Ledger.level_revocation_marker(4)[Ledger::LEVEL_REVOCATION, 1]).to eq '4'
      end
    end
  end
end
