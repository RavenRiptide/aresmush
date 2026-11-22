require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What `advance/review` says about a slot the level has left open.
    #
    # It named the slot but said nothing about where the commands are, and a player who cannot find
    # them cannot finish the level. Two players lost their Multilingual languages to exactly this:
    # the slot showed as outstanding, `lang/set` is chargen-only, and nothing pointed anywhere.
    #
    # The pointer is the help topic rather than the command grammar, which is how `cg/review`
    # answers the same question: the grammar written out here would be a second copy of the
    # parsers, kept in step by hand.
    describe PF2AdvanceReviewTemplate do

      # Every alias the table points at, as the help files define them.
      TOPICS = %w{advancelanguages advanceskills advanceattributes advancefeats advancefeatures
                  advancearchetypes advancespells advanceformulas advanceretrain}.freeze

      describe :help_for do
        it "should point an open language slot at the languages topic" do
          expect(PF2AdvanceReviewTemplate.help_for('open languages')).to include 'advancelanguages'
        end

        it "should name an activity and a topic for each slot it knows" do
          missing = PF2AdvanceReviewTemplate::RESOLVED_BY.reject do |_key, (activity, topic)|
            activity.to_s.match?(/\A[a-z]/) && TOPICS.include?(topic.to_s)
          end

          expect(missing).to eq({})
        end

        # A topic that no help file answers to renders as a pointer to nothing.
        it "should point only at topics the help files define" do
          defined = Dir[File.join(AresMUSH.game_path, '..', 'plugins', 'pf2e', 'help', 'en', '*.md')]
                      .flat_map { |path| File.read(path).scan(/^- (\S+)$/).flatten }

          expect(TOPICS - defined).to eq []
        end

        it "should say nothing for a slot it has no topic for, rather than guessing" do
          expect(PF2AdvanceReviewTemplate.help_for('something nobody has heard of')).to be_nil
        end

        # The keys are the ones to_assign actually uses, so a renamed key loses its hint silently.
        it "should key its hints on slots the draft really holds" do
          known = Pf2e::DraftKeys::KEYS.keys.map(&:to_s)
          strays = PF2AdvanceReviewTemplate::RESOLVED_BY.keys.map(&:to_s) - known

          expect(strays).to eq []
        end

        # Every slot a player is left to fill themselves needs a pointer against it. These are the
        # ones a level actually leaves open, and driving a character through level 11 found four of
        # them rendering with nothing at all: the pointer was appended on one branch of the review's
        # renderer and these go through the others.
        FILLED_BY_THE_PLAYER = [
          'raise ability', 'raise skill', 'raise skill choice', 'open languages', 'open skills',
          'feats', 'feat choice', 'repertoire', 'spellbook', 'innate', 'class option',
          'divine font', 'archetype_specialty', 'archetype specialty choice', 'archetype deity',
          'archetype key ability', 'archetype_sanctification', 'retrains'
        ].freeze

        it "should have a topic for every slot the player has to fill" do
          missing = FILLED_BY_THE_PLAYER.reject { |key| PF2AdvanceReviewTemplate.help_for(key) }

          expect(missing).to eq []
        end

        it "should point formula choices at a topic the help files define" do
          expect(TOPICS).to include PF2AdvanceReviewTemplate::FORMULA_CHOICE_HELP.last
        end
      end

      # A choice a feature carries is filled with advance/option, not advance/feat, and a player
      # told it was about "taking feats" went looking for the wrong command. A formula choice is
      # filled the same way, but its commands are in the formulas topic.
      describe :feat_choice_lines do
        before do
          @template = PF2AdvanceReviewTemplate.allocate
          allow(@template).to receive(:item_color).and_return('')
          allow(@template).to receive(:choice_block) do |name|
            name == 'Formula Book' ? { 'from_formulas' => {} } : { 'from_feats' => {} }
          end
          allow(Pf2e).to receive(:choice_summary).and_return('summary')
        end

        it "should point an option that grants a feat at the options topic" do
          lines = @template.feat_choice_lines('Skillful Lessons' => [ 'open' ])

          expect(lines.last).to include 'advancefeatures'
          expect(lines.join).not_to include 'advanceformulas'
        end

        it "should point a formula choice at the formulas topic" do
          lines = @template.feat_choice_lines('Formula Book' => [ 'open' ])

          expect(lines.last).to include 'advanceformulas'
          expect(lines.join).not_to include 'advancefeatures'
        end

        it "should list each group under its own pointer when both are open" do
          lines = @template.feat_choice_lines('Formula Book' => [ 'open' ], 'Skillful Lessons' => [ 'open' ])

          expect(lines.map { |line| line[/Skillful Lessons|Formula Book|advancefeatures|advanceformulas/] })
            .to eq [ 'Skillful Lessons', 'advancefeatures', 'Formula Book', 'advanceformulas' ]
        end

        it "should say nothing for choices with no open picks" do
          expect(@template.feat_choice_lines('Skillful Lessons' => [ 'Recognize Spell' ])).to eq []
        end
      end

      # A retrain the level owes (a witch familiar taking over) is a hash in the advancement draft. It
      # rendered as the raw hash under "Options So Far", and only the Messages section, which can't carry
      # commands, said it was owed.
      describe "a retrain" do
        OWED_RETRAIN = { 'feat' => 'Familiar', 'bucket' => 'charclass', 'level' => 1, 'from' => 'Familiar', 'also' => [], 'to' => nil }.freeze

        def template_with(retrains)
          template = PF2AdvanceReviewTemplate.allocate
          allow(template).to receive(:item_color).and_return('')
          char = double('char', :pf2_advancement => { 'retrains' => retrains })
          template.instance_variable_set(:@char, char)
          template
        end

        it "should list an open retrain to choose, as the feat and its slot" do
          lines = template_with([ OWED_RETRAIN ]).retrain_option_lines

          expect(lines).to eq [ 'Retrain:%xn Familiar (a level 1 class feat)' ]
        end

        it "should leave an open retrain out of the options so far" do
          adv = template_with([ OWED_RETRAIN ]).annotate_retrains('retrains' => [ OWED_RETRAIN ], 'feats' => { 'charclass' => [ 'Witch Dedication' ] })

          expect(adv).to eq('feats' => { 'charclass' => [ 'Witch Dedication' ] })
        end

        it "should show a retrain made as the old feat and its replacement, with what goes with it" do
          made = OWED_RETRAIN.merge('from' => 'Animal Accomplice', 'also' => [ 'Pet' ], 'to' => 'Reach Spell')
          template = template_with([ made ])

          expect(template.annotate_retrains('retrains' => [ made ])).to eq('retrains' => [ 'Animal Accomplice (with Pet) to Reach Spell' ])
          expect(template.retrain_option_lines).to eq []
        end

        it "should point an open retrain at the retraining topic" do
          expect(PF2AdvanceReviewTemplate.help_for('retrains')).to include 'advanceretrain'
        end
      end

      # PF2e's Remaster calls them attributes. The draft's key is still `raise ability`, but a player
      # never sees that word.
      describe "an attribute boost slot" do
        it "should be headed Raise Attributes" do
          template = PF2AdvanceReviewTemplate.allocate
          allow(template).to receive(:item_color).and_return('')

          line = template.option_lines_for('raise ability', %w(open open open open)).first

          expect(line).to start_with('Raise Attributes:')
          expect(line).not_to include('Ability')
        end
      end
    end
  end
end
