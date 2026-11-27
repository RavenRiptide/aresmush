require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Sil Atavism: a silyara gains the benefits of one sildanyar heritage. Their own heritage stays Silyara.
    describe "Sil Atavism" do

      describe "the data" do
        before(:all) do
          @feat = YAML.load_file("game/config/pf2e_feat_ancestry.yml")['pf2e_feats']['Sil Atavism']
        end

        # The sildanyar heritages, less the versatile ones and Silyara and Ghaluch.
        it "should offer the five sildanyar heritages and nothing else" do
          expect(@feat['feat_choice']['options'].keys).to eq %w(Arctic Cavern Seer Whisper Woodland)
        end

        it "should grant Cavern's darkvision and Seer's detect magic, as those heritages give them" do
          heritages = YAML.load_file("game/config/pf2e_heritages.yml")['pf2e_heritage']
          options = @feat['feat_choice']['options']

          expect(options['Cavern']['grants']['special']).to eq heritages['Cavern']['special']
          expect(options['Seer']['grants']['magic_stats']).to eq heritages['Seer']['magic_stats']
        end

        it "should give the Arctic heritage's cold resistance only to one who chose Arctic" do
          resistance = @feat['rules'].find { |rule| rule['key'] == 'Resistance' }
          heritage = YAML.load_file("game/config/pf2e_heritages.yml")['pf2e_heritage']['Arctic']['rules'].first

          expect(resistance.slice('type', 'value')).to eq heritage.slice('type', 'value')
          expect(resistance['predicate']).to eq [ 'sil-atavism:arctic' ]
        end
      end

      describe "taken at chargen", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Atavism#{rand(1000000)}")
          @builder = AutoBuilder.new(@char)
          @builder.build_level_one('Fighter', ancestry: 'Human', heritage: 'Silyara')
          @builder.clear
          @builder.run "cg/restore skills"
        end

        after(:each) do
          live = Character[@char.id]

          live.spellcasting_entries.each(&:delete) if live.respond_to?(:spellcasting_entries)
          live.magic&.delete
          live.delete
        end

        def take(heritage)
          @builder.clear
          @builder.run "commit skills"
          @builder.run "cg/feat ancestry=Sil Atavism"
          @builder.run "cg/option Sil Atavism=#{heritage}"

          expect(@builder.failures).to be_empty

          Character[@char.id]
        end

        it "should give a Cavern atavism darkvision, and leave their heritage Silyara" do
          char = take('Cavern')

          expect(char.pf2_special).to include 'Darkvision'
          expect(char.pf2_base_info['heritage']).to eq 'Silyara'
        end

        it "should give a Seer atavism detect magic as an innate cantrip" do
          char = take('Seer')
          innate = Pf2emagic::Entries.innate_grants(char.magic)

          expect(innate.map { |grant| [ grant['name'], grant['level'], grant['tradition'] ] }).to include [ 'Detect Magic', 'cantrip', 'arcane' ]
        end

        it "should give a Woodland atavism nothing the game tracks" do
          char = take('Woodland')

          expect(char.pf2_special).to_not include 'Darkvision'
        end
      end
    end
  end
end
