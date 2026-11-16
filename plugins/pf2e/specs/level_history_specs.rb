require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A character's build level by level, read from ledger rows: sheet/history, sheet/feats and
    # sheet/features.
    describe LevelHistory do

      def row(kind, payload, level, source = 'level_up', extra = {})
        @seq = (@seq || 0) + 1
        { 'seq' => @seq, 'txn' => "#{source}-#{level}", 'kind' => kind, 'payload' => payload,
          'source_type' => source, 'effective_level' => level, 'reverted_by' => nil }.merge(extra)
      end

      def feat(name, bucket, level, source = 'level_up', extra = {})
        row('grant_feat', { 'bucket' => bucket, 'feat' => name }, level, source, extra)
      end

      # A character built through chargen since the ledger, now level 4.
      def built
        [
          feat('Adapted Cantrip', 'ancestry', 1, 'chargen'),
          feat('Foretell Harm', 'charclass', 1, 'chargen'),
          row('raise_skill', { 'skill' => 'Medicine', 'to' => 'trained' }, 1, 'chargen'),
          row('boost_ability', { 'ability' => 'Wisdom' }, 1, 'chargen'),
          row('boost_ability', { 'ability' => 'Wisdom' }, 1, 'chargen'),
          row('boost_ability', { 'ability' => 'Charisma' }, 1, 'chargen'),
          row('make_choice', { 'choice' => 'Mystery', 'label' => 'Flames' }, 1, 'chargen'),
          row('grant_feature', { 'bucket' => 'charclass_features', 'feature' => 'Divine Access' }, 1, 'chargen'),
          feat('Champion Dedication', 'dedication', 2),
          feat('Assurance', 'skill', 2),
          row('make_choice', { 'choice' => 'Assurance', 'label' => 'Medicine' }, 2),
          feat('Armor Proficiency', 'general', 3),
          row('raise_skill', { 'skill' => 'Medicine', 'to' => 'expert' }, 3),
          row('spell_access', { 'source' => 'Oracle', 'rank' => 2, 'spell' => 'Restoration' }, 3),
          row('spell_access', { 'source' => 'Oracle', 'rank' => 0, 'spell' => 'Light' }, 3),
          row('set_prof', { 'group' => 'weapon_prof', 'key' => 'simple', 'to' => 'expert' }, 3),
          row('grant_feature', { 'bucket' => 'charclass_features', 'feature' => 'Expert Spellcaster' }, 3),
          feat('Continual Recovery', 'skill', 4)
        ]
      end

      def labels(groups, group)
        Hash[groups.find { |g, _| g == group }.last]
      end

      describe "the history" do
        it "should group by level, oldest first" do
          expect(LevelHistory.groups(built, 4).map(&:first)).to eq [ 1, 2, 3, 4 ]
        end

        it "should label each line by what it is, with feats by their slot" do
          level1 = labels(LevelHistory.groups(built, 4), 1)

          expect(level1['Ancestry feat']).to eq [ 'Adapted Cantrip' ]
          expect(level1['Class feat']).to eq [ 'Foretell Harm' ]
          expect(level1['Choice']).to eq [ 'Mystery: Flames' ]
          expect(level1['Skill']).to eq [ 'Medicine (trained)' ]
        end

        it "should call a boost an attribute boost, and count one taken twice" do
          expect(labels(LevelHistory.groups(built, 4), 1)['Attribute boosts']).to eq [ 'Wisdom (2 boosts)', 'Charisma' ]
        end

        it "should call a dedication an archetype feat" do
          expect(labels(LevelHistory.groups(built, 4), 2)['Archetype feat']).to eq [ 'Champion Dedication' ]
        end

        it "should name a feat's choice beside it rather than as a choice of its own" do
          level2 = labels(LevelHistory.groups(built, 4), 2)

          expect(level2['Skill feat']).to eq [ 'Assurance (Medicine)' ]
          expect(level2).not_to have_key('Choice')
        end

        it "should list spells with their rank, and a cantrip as one" do
          expect(labels(LevelHistory.groups(built, 4), 3)['Spells']).to eq [ 'Restoration (rank 2)', 'Light (cantrip)' ]
        end

        # These follow from the class table, not from anything the player chose.
        it "should leave out class features and proficiencies" do
          level3 = labels(LevelHistory.groups(built, 4), 3)

          expect(level3.keys).to contain_exactly('General feat', 'Skill', 'Spells')
        end

        it "should put feats before skills and spells within a level" do
          expect(LevelHistory.groups(built, 4).find { |g, _| g == 3 }.last.map(&:first)).to eq [ 'General feat', 'Skill', 'Spells' ]
        end

        it "should keep only the latest rank for a skill raised twice in one level" do
          rows = [ row('raise_skill', { 'skill' => 'Stealth', 'to' => 'trained' }, 1, 'chargen'),
                   row('raise_skill', { 'skill' => 'Stealth', 'to' => 'expert' }, 1, 'chargen') ]

          expect(labels(LevelHistory.groups(rows, 1), 1)['Skill']).to eq [ 'Stealth (expert)' ]
        end

        it "should leave out a reverted grant" do
          rows = built + [ feat('Toughness', 'general', 3, 'level_up', 'reverted_by' => 'rollback') ]

          expect(labels(LevelHistory.groups(rows, 4), 3)['General feat']).to eq [ 'Armor Proficiency' ]
        end

        # A boon for level 5 is dormant at level 4.
        it "should leave out a grant for a level the character hasn't reached" do
          rows = built + [ row('add_language', { 'language' => 'Silya' }, 5, 'boon') ]

          expect(LevelHistory.groups(rows, 4).map(&:first)).not_to include(5)
        end

        it "should put a grant with no level last, saying where it came from" do
          rows = built + [ row('grant_formula', { 'category' => 'consumables', 'formula' => 'Antidote' }, nil, 'bought') ]
          groups = LevelHistory.groups(rows, 4)

          expect(groups.last.first).to eq :global
          expect(labels(groups, :global)['Formula']).to eq [ 'Antidote (bought)' ]
        end

        it "should say where a levelled grant came from when it wasn't the level-up" do
          rows = built + [ row('add_language', { 'language' => 'Silya' }, 3, 'boon') ]

          expect(labels(LevelHistory.groups(rows, 4), 3)['Language']).to eq [ 'Silya (boon)' ]
        end

        it "should keep only the levels in a range" do
          expect(LevelHistory.groups(built, 4, :range => 2..3).map(&:first)).to eq [ 2, 3 ]
        end

        it "should leave the ungrouped rows out of a range" do
          rows = built + [ row('grant_formula', { 'formula' => 'Antidote' }, nil, 'bought') ]

          expect(LevelHistory.groups(rows, 4, :range => 1..4).map(&:first)).to eq [ 1, 2, 3, 4 ]
        end
      end

      # A character made before the ledger was seeded at level 1, whatever level they were.
      describe "a character from before the ledger" do
        def seeded(source)
          [ feat('Battle Medicine', 'skill', 1, source),
            feat('Toughness', 'general', 1, source),
            row('make_choice', { 'choice' => 'Mystery', 'label' => 'Flames' }, 4, source),
            feat('Quick Climb', 'skill', 6) ]
        end

        it "should not claim the seeded feats were taken at level 1" do
          groups = LevelHistory.groups(seeded('chargen'), 6)

          expect(groups.map(&:first)).to eq [ :before, 4, 6 ]
          expect(labels(groups, :before)['Skill feat']).to eq [ 'Battle Medicine' ]
        end

        it "should read an import the same way" do
          expect(LevelHistory.groups(seeded('imported'), 6).first.first).to eq :before
        end

        # Seeding kept the level a choice was recorded at.
        it "should still place a choice at the level it was recorded at" do
          expect(labels(LevelHistory.groups(seeded('chargen'), 6), 4)['Choice']).to eq [ 'Mystery: Flames' ]
        end

        it "should trust level 1 for a character who has never levelled and is level 1" do
          rows = [ feat('Toughness', 'general', 1, 'imported') ]

          expect(LevelHistory.groups(rows, 1).map(&:first)).to eq [ 1 ]
        end

        it "should not trust level 1 for a character seeded at a higher level with no level-ups since" do
          rows = [ feat('Toughness', 'general', 1, 'imported') ]

          expect(LevelHistory.groups(rows, 5).map(&:first)).to eq [ :before ]
        end
      end

      describe "feats by level" do
        it "should list each level's feats with their type in words" do
          expect(LevelHistory.feats_by_level(built, 4)).to eq [
            [ 1, [ 'Adapted Cantrip (ancestry feat)', 'Foretell Harm (class feat)' ] ],
            [ 2, [ 'Champion Dedication (archetype feat)', 'Assurance (Medicine) (skill feat)' ] ],
            [ 3, [ 'Armor Proficiency (general feat)' ] ],
            [ 4, [ 'Continual Recovery (skill feat)' ] ]
          ]
        end
      end

      describe "features by level" do
        it "should list each level's features" do
          expect(LevelHistory.features_by_level(built, 4)).to eq [ [ 1, [ 'Divine Access' ] ], [ 3, [ 'Expert Spellcaster' ] ] ]
        end

        it "should name a feature once when a specialty's version of it is held too" do
          rows = [ row('grant_feature', { 'feature' => 'Fifth Doctrine' }, 1, 'chargen'),
                   row('grant_feature', { 'feature' => 'Fifth Doctrine (Cloistered)' }, 1, 'chargen') ]

          expect(LevelHistory.features_by_level(rows, 1)).to eq [ [ 1, [ 'Fifth Doctrine (Cloistered)' ] ] ]
        end
      end

      describe :parse_range do
        it "should read a level and a range" do
          expect(LevelHistory.parse_range('5')).to eq 5..5
          expect(LevelHistory.parse_range('3-7')).to eq 3..7
          expect(LevelHistory.parse_range(' 3 - 7 ')).to eq 3..7
        end

        it "should refuse what isn't one" do
          expect(LevelHistory.parse_range('7-3')).to be_nil
          expect(LevelHistory.parse_range('0')).to be_nil
          expect(LevelHistory.parse_range('five')).to be_nil
          expect(LevelHistory.parse_range('')).to be_nil
        end
      end
    end
  end
end
