require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Grown of Oak's at-will innate spell, whose rank follows the character's highest, and Ultimate
    # Polymath, which makes every repertoire spell a signature spell.
    describe "at-will innate ranks and every spell a signature spell" do

      describe :innate_rank do
        let(:magic) { double(:innate_spells => []) }

        it "should give a grant without below_top its own rank" do
          expect(Entries.innate_rank(magic, { 'name' => 'Charm', 'level' => 4 })).to eq 4
        end

        it "should count below_top down from the highest rank any source has slots at" do
          allow(Entries).to receive(:slots_by_source).with(magic) do
            { 'Druid' => { 'cantrip' => 5, '1' => 3, '3' => 2 }, 'Wizard Archetype' => { '1' => 1 } }
          end

          grant = { 'name' => 'Oaken Resilience', 'level' => 'at will', 'below_top' => 1 }

          expect(Entries.innate_rank(magic, grant)).to eq 2
        end

        it "should never fall below 1" do
          allow(Entries).to receive(:slots_by_source).with(magic) { { 'Druid' => { '1' => 2 } } }

          expect(Entries.innate_rank(magic, { 'level' => 'at will', 'below_top' => 1 })).to eq 1
        end
      end

      # A grant whose level is a word other than a rank is cast at will: no use is spent, and a rest
      # stocks none.
      describe "an at-will grant" do
        let(:grant) { { 'name' => 'Oaken Resilience', 'level' => 'at will', 'below_top' => 1, 'tradition' => 'primal' } }
        let(:magic) { double(:innate_spells => [ grant ]) }

        it "should be the grant a cast draws on, with nothing used" do
          expect(Entries.innate_to_cast(magic, 'Oaken Resilience', {})).to eq grant
        end

        it "should take no slot" do
          expect(Entries.innate_ranked(magic)).to be_empty
        end
      end

      describe :signature_ranks do
        let(:character) { double }
        let(:magic) { double(:character => character) }
        let(:entry) do
          { 'name' => 'Bard', 'known' => { '1' => [ 'Fear' ], '3' => [ 'Haste', 'Fear' ] },
            'signature' => { '3' => [ 'Haste' ] } }
        end

        before(:each) do
          allow(Entries).to receive(:find).with(magic, 'Bard') { entry }
        end

        def holding(feats)
          allow(Pf2e).to receive(:feats_in_play).with(character) { feats.keys }
          allow(Pf2e).to receive(:get_feat_details) { |name| feats[name] ? [ name, feats[name] ] : 'not found' }
        end

        it "should give only the ranks a spell is a signature spell at, without the feat" do
          holding({})

          expect(Entries.signature_ranks(magic, 'Bard', 'Fear')).to be_empty
          expect(Entries.signature_ranks(magic, 'Bard', 'Haste')).to eq [ '3' ]
        end

        it "should give every rank a repertoire spell is known at, with the feat" do
          holding('Ultimate Polymath' => { 'all_signature' => true, 'assoc_charclass' => [ 'Bard' ] })

          expect(Entries.signature_ranks(magic, 'Bard', 'Fear')).to eq [ '1', '3' ]
        end

        it "should not speak for another class's repertoire" do
          holding('Ultimate Polymath' => { 'all_signature' => true, 'assoc_charclass' => [ 'Bard' ] })

          expect(Entries.all_signature?(magic, 'Sorcerer')).to eq false
        end
      end
    end
  end

  module Pf2e
    describe "an at-will innate grant on the ledger" do
      it "should keep below_top as a number" do
        record = Ledger.innate_record('name' => 'Oaken Resilience', 'level' => 'at will', 'below_top' => '1',
                                      'tradition' => 'primal', 'cast_stat' => 'Charisma')

        expect(record).to include('level' => 'at will', 'below_top' => 1)
      end

      it "should leave a grant without it equal to itself" do
        grant = { 'name' => 'Charm', 'level' => 1, 'tradition' => 'arcane', 'cast_stat' => 'Charisma' }

        expect(Ledger.innate_record(grant)).to eq Ledger.innate_record(grant.merge('level' => '1'))
        expect(Ledger.innate_record(grant)).to_not have_key('below_top')
      end
    end

    describe "a consequence's formula reading the one acting" do
      let(:holder) { double }
      let(:scene) { double(:actor => double(:holder => holder)) }

      before(:each) do
        allow(Effects).to receive(:context).with(holder) do
          { 'actor' => { 'level' => 9, 'abilities' => { 'con' => { 'mod' => 3 } } } }
        end
      end

      it "should work out Vivacious Conduit's healing for them" do
        expect(Acting.actor_formula(scene, '@actor.abilities.con.mod*floor(@actor.level/2)')).to eq '12'
      end

      it "should pass dice through" do
        expect(Acting.actor_formula(scene, '2d8')).to eq '2d8'
      end

      it "should never heal less than nothing" do
        allow(Effects).to receive(:context).with(holder) do
          { 'actor' => { 'level' => 9, 'abilities' => { 'con' => { 'mod' => -1 } } } }
        end

        expect(Acting.actor_formula(scene, '@actor.abilities.con.mod*floor(@actor.level/2)')).to eq '0'
      end
    end
  end
end
