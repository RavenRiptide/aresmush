require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Rewinding a chargen stage.
    #
    # A checkpoint is the character as they stood when a stage began, and `cg/restore` puts that
    # back. What the stage produced goes; everything the stages before it produced stays, whether
    # or not the restore path happens to rebuild it.
    describe "a chargen checkpoint", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Restore#{rand(1000000)}")
      end

      after(:each) { @char.delete if @char }

      # The builder takes the Acolyte background, which grants Student of the Canon while the
      # skills stage is locking.
      def built
        @builder = AutoBuilder.new(@char)
        @builder.build_level_one('Fighter')

        Character[@char.id]
      end

      def restore(checkpoint)
        @builder.clear
        char = @builder.run "cg/restore #{checkpoint}"

        expect(@builder.failures).to be_empty

        char
      end

      # The rewind itself: the feats chosen after the stage began are gone, and the slots they
      # spent are open again. Without this the rest of the file passes against a restore that
      # does nothing, since everything else it checks is true either way.
      it "should take back the picks made after the stage began" do
        char = built
        after_the_stage = DraftSheet.of(char).feats_by_bucket.values_at('ancestry', 'charclass').flatten.compact

        expect(after_the_stage).to_not be_empty

        char = restore('skills')
        held = DraftSheet.of(char).feat_names

        after_the_stage.each { |feat| expect(held).to_not include feat.upcase }

        # And the slots they spent: the open-pick bag is the one the stage started with.
        expect(char.pf2_to_assign).to eq Pf2e::Checkpoints.attrs_at(char, 'skills')['pf2_to_assign']
      end

      it "should keep a feat the background granted when the skills stage is rewound" do
        char = built

        expect(DraftSheet.of(char).feat_names).to include 'STUDENT OF THE CANON'

        expect(DraftSheet.of(restore('skills')).feat_names).to include 'STUDENT OF THE CANON'
      end

      it "should keep the languages the player picked when the skills stage is rewound" do
        char = built
        picked = Array(char.pf2_to_assign['open languages']).reject { |l| l.to_s.casecmp?('open') }

        expect(picked).to_not be_empty

        # Through DraftSheet: a picked language is the draft's, and the sheet's own list is what
        # the ancestry and background gave them.
        held = DraftSheet.of(restore('skills')).languages

        picked.each { |language| expect(held).to include language }
      end

      it "should leave the character standing at the stage before the one rewound to" do
        built

        expect(restore('skills').pf2_checkpoint).to eq 'abilities'
        expect(Character[@char.id].pf2_skills_locked).to be_falsey
      end

      # Rewinding a stage reopens that stage and nothing before it, so what base options built -
      # the ancestry's traits and size, the class's features - is still there.
      it "should keep the base options stage's work when the attributes stage is rewound" do
        built
        features = Character[@char.id].pf2_features

        char = restore('attributes')

        expect(char.pf2_traits).to include 'khazad'
        expect(char.pf2_movement['Size']).to_not be_blank
        expect(char.pf2_features).to eq features
        expect(char.pf2_baseinfo_locked).to be true
        expect(char.pf2_abilities_locked).to be_falsey
      end

      # The six ability rows are made while base options commits, after its checkpoint is taken, so
      # the checkpoint has no score for them. They go back to the score they were made with, not to
      # what the ancestry and the abilities stage boosted them to.
      it "should put the ability scores back to 10 when the base options stage is rewound" do
        built

        expect(DraftSnapshot.ability_scores(Character[@char.id]).values.uniq).to_not eq [ 10 ]

        scores = DraftSnapshot.ability_scores(restore('info'))

        expect(scores.size).to eq 6
        expect(scores.values.uniq).to eq [ 10 ]
      end

      # Committing base options again finds the rows already there and builds on them, so the
      # boosts spent before the rewind must not still be in them. The builder's ancestry moves no
      # score at this stage, so every score is still the one the row was made with.
      it "should start the abilities stage from fresh scores when base options is committed again" do
        built
        restore('info')

        @builder.clear
        @builder.run "commit info"

        expect(@builder.failures).to be_empty
        expect(DraftSnapshot.ability_scores(Character[@char.id]).values.uniq).to eq [ 10 ]
      end

      # A focus spell is held on a spellcasting entry, a collection beside the character rather
      # than one of its attributes. A restore that missed it left Initiate Warden's spell behind
      # when the feat went, and taking the feat again granted another, so a ranger could collect
      # all three initial warden spells.
      describe "a focus spell a feat granted" do
        def warden_spells(char)
          Pf2emagic::Entries.stored(char)
            .select { |entry| entry['category'] == Pf2emagic::Entries::FOCUS && entry['name'].to_s.casecmp?('warden') }
            .flat_map { |entry| Array((entry['known'] || {})['spell']) }
        end

        # The builder takes no feat with a choice, so the ranger takes Initiate Warden by hand in
        # the slot a rewound skills stage opens again.
        def take_warden(spell)
          @builder.clear
          @builder.run "commit skills"
          @builder.run "cg/feat charclass=Initiate Warden"
          @builder.run "cg/option Initiate Warden=#{spell}"

          expect(@builder.failures).to be_empty

          Character[@char.id]
        end

        before(:each) do
          @builder = AutoBuilder.new(@char)
          @builder.build_level_one('Ranger')
          restore('skills')
        end

        it "should take the spell back when the skills stage is rewound" do
          expect(warden_spells(take_warden('Heal Companion'))).to eq [ 'Heal Companion' ]

          expect(warden_spells(restore('skills'))).to be_empty
        end

        it "should leave only the spell picked the second time" do
          take_warden('Heal Companion')
          restore('skills')

          expect(warden_spells(take_warden('Gravity Weapon'))).to eq [ 'Gravity Weapon' ]
        end

        # A checkpoint saved before the snapshot held spellcasting entries has no record of them. It
        # must leave them alone rather than read as "none", which would delete every entry.
        it "should leave the entries alone when the checkpoint predates them" do
          char = take_warden('Heal Companion')
          row = Pf2e::Checkpoints.find(char, 'skills')
          row.update(:shape => row.shape.reject { |slice, _v| slice == 'spellcasting' })

          expect(warden_spells(restore('skills'))).to eq [ 'Heal Companion' ]
        end
      end

      # The picks the stage needed were restored with it, so there is nothing left open and the
      # stage commits straight away.
      it "should let the rewound stage be committed again" do
        built
        restore('skills')

        @builder.clear
        @builder.run "commit skills"

        expect(@builder.failures).to be_empty
        expect(Character[@char.id].pf2_skills_locked).to be true
      end
    end
  end
end
