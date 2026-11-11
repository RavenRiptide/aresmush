require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Bone Magic asks whether a ciith's innate spells are primal or occult, then grants an innate
    # cantrip of that tradition. The ciith feats that need Bone Magic cast in the tradition it chose.
    describe "Bone Magic", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Gizzard#{rand(1000000)}")
        @builder = AutoBuilder.new(@char)
      end

      after(:each) do
        found = Character[@char.id]
        found&.magic&.delete
        found&.delete
      end

      def char
        Character[@char.id]
      end

      # A common cantrip on one of the two lists and not the other, from the shipped data.
      def cantrip_only_on(tradition, other)
        Pf2emagic.find_common_spells.find do |_name, details|
          traditions = Array(details['tradition']).map { |one| one.to_s.downcase }

          details['base_level'].to_s == 'cantrip' && traditions.include?(tradition) && !traditions.include?(other)
        end&.first
      end

      def innate_grants
        Pf2emagic::Entries.innate_grants(char.magic)
      end

      describe "taken at a level-up" do
        before(:each) do
          @builder.build('Wizard', 4, :ancestry => 'Ciith', :heritage => 'Pantli')
          @builder.clear
          @builder.run 'advance'
          @builder.run 'advance/feat ancestry=Bone Magic'
          @builder.run 'advance/option Bone Magic=Occult'
        end

        it "should let the cantrip be chosen from the tradition picked, and keep it after the level" do
          cantrip = cantrip_only_on('occult', 'primal')

          @builder.run "advance/spell innate/cantrip=#{cantrip}"
          6.times { break if @builder.resolve_outstanding(:advance).zero? }
          @builder.run 'advance/done'

          expect(@builder.failures).to eq []
          expect(char.pf2_level).to eq 5
          expect(innate_grants).to include(a_hash_including('name' => cantrip, 'tradition' => 'occult', 'level' => 'cantrip'))
          expect(Pf2emagic::Entries.pending_innate(char.magic)).to eq []
        end

        it "should refuse a cantrip from the other list" do
          @builder.clear
          @builder.run "advance/spell innate/cantrip=#{cantrip_only_on('primal', 'occult')}"

          expect(@builder.failures.join).to include(t('pf2emagic.innate_tradition_mismatch'))
        end
      end

      it "should open the cantrip of the tradition picked when it is chosen in chargen" do
        magic = PF2Magic.create(:character => @char)
        @char.update(:magic => magic, :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Ciith' })
        block = Pf2e.feat_choice_block_for('Bone Magic')

        Pf2e.apply_feat_choice(char, 'Bone Magic', block, 'Primal', nil)

        expect(Pf2emagic::Entries.pending_innate(char.magic))
          .to eq [ { 'level' => 'cantrip', 'tradition' => 'primal', 'cast_stat' => 'Charisma', 'name' => 'open' } ]
      end

      # Bone Investiture and Fossil Rider name no tradition of their own.
      describe "the feats that need it" do
        def stats_for(feat)
          Pf2e.resolve_caster_type_stats(@char, Global.read_config('pf2e_feats', feat)['magic_stats'])['innate_spell']
        end

        it "should cast in the tradition Bone Magic chose" do
          allow(Pf2e).to receive(:choice_labels_for).with(anything, 'Bone Magic').and_return([ 'Occult' ])

          expect(stats_for('Bone Investiture')).to include('name' => 'Dinosaur Form', 'level' => 5, 'tradition' => 'occult')
          expect(stats_for('Fossil Rider')).to include('name' => 'Mask of Terror', 'level' => 7, 'tradition' => 'occult')
        end
      end
    end
  end
end
