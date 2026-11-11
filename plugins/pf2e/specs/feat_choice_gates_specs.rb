require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The small rules that decide whether a feat's choice opens and what it may offer.
    describe "feat choice gates" do
      let(:char) { double('Character', :pf2_level => 8, :advancing => false, :pf2_base_info => { 'charclass' => 'Fighter' }) }

      # Second Blessing offers only the blessings a champion does not hold yet, so an option may name
      # a feature the character must not have.
      describe "a feature prerequisite" do
        before(:each) do
          allow(Pf2e).to receive(:holds_feature?) { |_char, name| name == 'Blessed Shield' }
        end

        it "should pass when the character holds the feature it names" do
          expect(Pf2e.meets_prereqs?(char, { 'feature' => [ 'Blessed Shield' ] }, 8)).to be true
        end

        it "should refuse a feature the character holds when it is marked with '!'" do
          expect(Pf2e.meets_prereqs?(char, { 'feature' => [ '!Blessed Shield' ] }, 8)).to be false
        end

        it "should pass a feature marked with '!' that the character does not hold" do
          expect(Pf2e.meets_prereqs?(char, { 'feature' => [ '!Blessed Armament' ] }, 8)).to be true
        end
      end

      # Multitalented hands over a dedication "even if you normally couldn't take another dedication
      # feat until you take more feats from your current archetype".
      describe "the dedication lock" do
        let(:dedication) { { 'feat_type' => [ 'Dedication' ], 'assoc_class' => [ 'Fighter' ] } }

        before(:each) do
          allow(Pf2e).to receive(:dedication_archetype_ready?).and_return(false)
        end

        it "should refuse another dedication before the archetype is ready" do
          expect(Pf2e.dedication_allowed?(char, dedication)).to be false
        end

        it "should allow it when told to ignore the lock" do
          expect(Pf2e.dedication_allowed?(char, dedication, true)).to be true
        end

        it "should still refuse a class the archetype does not allow" do
          expect(Pf2e.dedication_allowed?(char, dedication.merge('assoc_class' => [ 'Wizard' ]), true)).to be false
        end

        it "should let a pool that ignores the lock offer the dedication" do
          allow(Pf2e).to receive(:can_take_feat_details?).and_return(true)
          filter = { 'feat_type' => 'Dedication', 'ignore_dedication_lock' => true }

          expect(Pf2e.choice_feat_match?(char, 'Some Dedication', dedication, filter)).to be true
          expect(Pf2e.choice_feat_match?(char, 'Some Dedication', dedication, filter.except('ignore_dedication_lock'))).to be false
        end
      end

      # Instinct Ability's free barbarian feat is the Fury instinct's, so its choice opens only for it.
      describe "a choice with a prerequisite of its own" do
        let(:block) { { 'prereq' => { 'specialize' => [ 'Fury' ] }, 'from_feats' => {} } }

        it "should open for a character who meets it" do
          allow(Pf2e).to receive(:held_specialties).and_return([ 'FURY' ])

          expect(Pf2e.feat_choice_open_to?(char, block)).to be true
        end

        it "should not open for a character who does not" do
          allow(Pf2e).to receive(:held_specialties).and_return([ 'ANIMAL' ])

          expect(Pf2e.feat_choice_open_to?(char, block)).to be false
        end

        it "should open a choice with no prerequisite for anyone" do
          expect(Pf2e.feat_choice_open_to?(char, { 'options' => {} })).to be true
        end
      end

      # A choice making two picks of innate spells - Celestial Magic - stages each pick under the feat's
      # name, and the second must not replace the first.
      describe "innate spells staged twice for one feat" do
        def innate(*names)
          { 'innate_spell' => { 'level' => 2, 'name' => names, 'tradition' => 'divine', 'cast_stat' => 'Charisma' } }
        end

        it "should keep both spells" do
          expect(Pf2e.add_feat_innate(innate('Clear Mind'), innate('Everlight'))['innate_spell']['name'])
            .to eq [ 'Clear Mind', 'Everlight' ]
        end

        it "should stage the first pick as it is" do
          expect(Pf2e.add_feat_innate(nil, innate('Clear Mind'))).to eq innate('Clear Mind')
        end

        it "should not list one spell twice" do
          expect(Pf2e.add_feat_innate(innate('Clear Mind'), innate('clear mind'))['innate_spell']['name'])
            .to eq [ 'Clear Mind' ]
        end

        # An open slot is a pick still to make, so two of them are two picks.
        it "should keep every open slot" do
          expect(Pf2e.add_feat_innate(innate('open'), innate('open'))['innate_spell']['name'])
            .to eq [ 'open', 'open' ]
        end
      end

      describe "a feat staff set up by hand" do
        def row
          Advancement::FeatGain::EFFECTS.find { |effect| effect['name'] == 'staff request' }
        end

        it "should tell the player what to put in a request for" do
          ctx = { :feat => 'Bloodline Mutation', :details => { 'staff_request' => 'which traits you gain' } }

          expect(row['when'].call(ctx)).to be_truthy
          expect(row['apply'].call(ctx))
            .to eq [ [ 'pf2e.feat_staff_request', { :feat => 'Bloodline Mutation', :details => 'which traits you gain' } ] ]
        end

        it "should say nothing for a feat with nothing to request" do
          expect(row['when'].call(:feat => 'Toughness', :details => {})).to be_falsey
        end
      end
    end
  end
end
