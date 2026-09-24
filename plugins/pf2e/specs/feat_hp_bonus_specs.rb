require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Hit Points a feat adds to a character's maximum: Toughness adds their level, and each
    # Resiliency feat 3 for every class feat of its archetype they hold. Worked out from the feats on
    # the sheet whenever maximum Hit Points are asked for, so it follows the character's level and
    # later archetype feats without anything having to be written.
    describe "Pf2eHP.feat_hp_bonus" do

      def config
        {
          'Toughness' => { 'hp_bonus' => { 'per_level' => 1 } },
          'Barbarian Dedication' => { 'assoc_archetype' => [ 'Barbarian Archetype' ] },
          'Barbarian Resiliency' => { 'assoc_archetype' => [ 'Barbarian Archetype' ],
                                      'hp_bonus' => { 'per_archetype_feat' => 3 } },
          'Basic Fury' => { 'assoc_archetype' => [ 'Barbarian Archetype' ] },
          'Fighter Dedication' => { 'assoc_archetype' => [ 'Fighter Archetype' ] },
          'Power Attack' => { 'assoc_charclass' => [ 'Fighter' ] }
        }
      end

      def bonus(feats, level)
        Pf2eHP.feat_hp_bonus(feats, config, level)
      end

      it "should add nothing for feats that add no Hit Points" do
        expect(bonus([ 'Power Attack', 'Fighter Dedication' ], 5)).to eq 0
      end

      it "should add the character's level for Toughness" do
        expect(bonus([ 'Toughness' ], 7)).to eq 7
      end

      it "should count Resiliency and the Dedication before it" do
        expect(bonus([ 'Barbarian Dedication', 'Barbarian Resiliency' ], 4)).to eq 6
      end

      it "should grow as more of the archetype's feats are taken" do
        expect(bonus([ 'Barbarian Dedication', 'Barbarian Resiliency', 'Basic Fury' ], 6)).to eq 9
      end

      it "should not count another archetype's feats" do
        expect(bonus([ 'Barbarian Dedication', 'Barbarian Resiliency', 'Fighter Dedication' ], 6)).to eq 6
      end

      it "should add both together" do
        expect(bonus([ 'Toughness', 'Barbarian Dedication', 'Barbarian Resiliency' ], 4)).to eq 10
      end

      it "should match feat names however they are capitalised" do
        expect(bonus([ 'toughness' ], 3)).to eq 3
      end

      describe "the shipped feats" do
        before(:all) do
          @feats = {}

          %w(ancestry class dedication general skill).each do |file|
            @feats.merge!(YAML.load_file("game/config/pf2e_feat_#{file}.yml")['pf2e_feats'])
          end
        end

        it "should give Toughness a Hit Point per level" do
          expect(@feats['Toughness']['hp_bonus']).to eq({ 'per_level' => 1 })
        end

        it "should give each Resiliency 3 Hit Points per archetype feat" do
          %w(Barbarian Champion Fighter Monk Ranger).each do |cls|
            expect(@feats["#{cls} Resiliency"]['hp_bonus']).to eq({ 'per_archetype_feat' => 3 }), cls
          end
        end
      end
    end

    describe "Pf2eHP.get_max_hp", :dbtest => true do
      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Hardy#{rand(1000000)}", :pf2_level => 6)
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 6)
        @char.update(:hp => @hp)
      end

      after(:each) do
        @hp.delete if @hp
        @char.delete if @char
      end

      # (6 class + 0 Constitution) x 6 levels + 8 ancestry, before any feat.
      def base
        44
      end

      it "should add Toughness and Resiliency to the maximum" do
        @char.update(:pf2_feats => {
          'general' => [ 'Toughness' ],
          'charclass' => [ 'Fighter Dedication', 'Fighter Resiliency', 'Basic Maneuver' ]
        })

        expect(Pf2eHP.get_max_hp(Character[@char.id])).to eq base + 6 + 9
      end

      it "should raise current Hit Points with it" do
        @char.update(:pf2_feats => { 'general' => [ 'Toughness' ] })
        @hp.update(:damage => 10)

        expect(Pf2eHP.get_current_hp(Character[@char.id])).to eq base + 6 - 10
      end
    end
  end
end
