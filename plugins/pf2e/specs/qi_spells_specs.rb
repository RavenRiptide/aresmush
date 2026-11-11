require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Qi Spells grants a qi spell and asks once whether a monk's qi spells are divine or occult. The
    # answer is the monk's only tradition, so without it they hold a focus spell and are no caster.
    describe "Qi Spells", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Ulrikin#{rand(1000000)}")
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

      describe "taken at a level-up" do
        before(:each) do
          @builder.build('Monk', 1)
          @builder.advance_to(1)
          @builder.clear
          @builder.run 'advance'
          @builder.run 'advance/feat charclass=Qi Spells'
        end

        it "should ask for the qi tradition before the level is done" do
          expect(@builder.failures).to eq []
          expect(Array(char.pf2_to_assign.dig('feat choice', 'Qi Tradition'))).to include('open')
        end

        it "should make the monk a caster of the tradition picked, holding the spell picked" do
          @builder.run 'advance/option Qi Spells=Inner Upheaval'
          @builder.run 'advance/option Qi Tradition=Occult'
          6.times { break if @builder.resolve_outstanding(:advance).zero? }
          @builder.run 'advance/done'

          expect(@builder.failures).to eq []
          expect(char.pf2_level).to eq 2
          expect(Pf2emagic.is_caster?(char)).to be true
          expect(char.magic.tradition['Monk']).to eq [ 'occult', 'trained' ]
          expect(Pf2emagic::Entries.focus_spells(char.magic, 'qi')).to include('Inner Upheaval')
          expect(Pf2emagic.focus_pool_max(char.magic)).to eq 1
        end
      end
    end
  end
end
