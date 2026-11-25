require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # sheet/familiar, rendered through the command: the approved mockups' lines for each kind of familiar.
    describe "a familiar's sheet", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        allow(Jobs).to receive(:notify)
        allow(Login).to receive(:notify)

        @made = []
        @client = AutoBuilder::CaptureClient.new
      end

      after(:each) { @made.each { |one| one.delete } }

      def character(prefix)
        found = Character.create(:name => "#{prefix}#{rand(1000000)}")
        @made << found
        found
      end

      # The sheet as text, colour codes left out.
      def sheet(of, viewer = of, target = nil)
        @client.clear
        PF2FamiliarSheetCmd.new(@client, Command.new("sheet/familiar #{target}".strip), Character[viewer.id]).on_command
        (@client.successes + @client.failures).join("\n").gsub(/%x(\d+|[a-zA-Z])/, '')
      end

      # A character built by hand: a class, feats, a level, and approved familiar details.
      def by_hand(prefix, charclass:, level:, feats: {}, features: [], specialize: nil, approved: nil)
        char = character(prefix)
        combat = Pf2eCombat.create(:character => char, :key_abil => 'Intelligence', :perception => 'trained',
                                   :armor_prof => { 'unarmored' => 'trained' },
                                   :saves => { 'Fortitude' => 'trained', 'Reflex' => 'trained', 'Will' => 'expert' })
        @made << combat
        char.update(:combat => combat, :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {}, :pf2_daily_choices => {},
                    :pf2_lang => [ 'Kamin' ], :pf2_level => level, :pf2_feats => feats,
                    :pf2_base_info => { 'charclass' => charclass, 'specialize' => specialize }.compact,
                    :pf2_features => { 'charclass_features' => features })
        @made += Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => char, :name => name, :base_val => 14) }
        Paths.apply_all!(Character[char.id])
        Character[char.id].update(:pf2_familiar => { 'approved' => approved }) if approved
        Character[char.id]
      end

      describe "a witch's familiar" do
        before(:each) do
          @char = character('Morwen')
          AutoBuilder.new(@char).build_level_one('Witch')
        end

        def set_details
          [ 'familiar/name Smudge', 'familiar/species black cat', 'familiar/form land' ].each do |text|
            PF2FamiliarSetCmd.new(@client, Command.new(text), Character[@char.id]).on_command
          end
        end

        def approve_app
          Roles.add_role(@char, 'approved')
          Ledger.commit_chargen!(Character[@char.id])
          Familiar.approve_with_app!(Character[@char.id])
        end

        it "should show what is waiting in chargen, and the spells it contains, without stats" do
          set_details
          shown = sheet(@char)

          expect(shown).to include "Pathfinder 2E Familiar: Smudge (#{@char.name}'s familiar)"
          expect(shown).to include 'Waiting for Approval'
          expect(shown).to include 'Staff approve your familiar with your application.'
          expect(shown).to match(/Smudge contains your witch spells: [1-9]\d* cantrips and [1-9]\d* spells\. To see them, use 'spellbook'\./)
          expect(shown).not_to include 'Stats'
          expect(shown).not_to include 'Abilities Today'
        end

        it "should name the request a familiar waits in, and what it still needs" do
          approve_app
          shown = sheet(@char)

          expect(shown).to include "(request ##{Familiar.job(Character[@char.id]).id})"
          expect(shown).not_to include 'help chargen_familiar'
          expect(shown).to include 'Still needed: name, species, form.'
          expect(shown).to include 'Name: Not set'
          expect(shown).to include 'Specific familiar (optional): No'
          expect(shown).to include "only your familiar's spells are allowed"
          expect(shown).to match(/Your familiar contains your witch spells/)
        end

        describe "once approved" do
          before(:each) do
            set_details
            approve_app
          end

          it "should show its stats, the patron's ability, and the rules that bind it" do
            shown = sheet(@char)

            expect(shown).to include 'Basic Information'
            expect(shown).to include 'Species: Black cat'
            expect(shown).to include 'Source: Witch'
            expect(shown).to include 'Traits: Animal, Minion'
            expect(shown).to include 'Speed: 25 feet'
            expect(shown).to include 'Senses: low-light vision'
            expect(shown).to include "Patron: #{Familiar::Stats.patron_ability(Character[@char.id])}"
            expect(shown).to include 'Smudge can act only when you Command it: 2 actions and no reactions.'
            expect(shown).not_to include 'Waiting for Approval'
          end

          it "should say when nothing is chosen today, and show the day's picks once they are" do
            expect(sheet(@char)).to include 'Abilities Today (0 of 3)'
            expect(sheet(@char)).to include "None chosen yet. Choose with 'prepare/familiar'."

            DailyChoices.pick!(Character[@char.id], 'familiar', 'Darkvision, Lifelink')
            shown = sheet(@char)

            expect(shown).to include 'Abilities Today (2 of 3)'
            expect(shown).to include 'Familiar: Darkvision'
            expect(shown).to include 'Master: Lifelink'
            expect(shown).to include 'Senses: low-light vision, darkvision'
            expect(shown).to include "You can change Smudge's abilities at your next daily preparations with 'prepare/familiar'."
          end

          it "should show anyone another character's familiar" do
            other = character('Bram')

            expect(sheet(@char, other, @char.name)).to include "Pathfinder 2E Familiar: Smudge (#{@char.name}'s familiar)"
          end
        end
      end

      it "should show a plain pet's two abilities, and no day's abilities or spells" do
        bram = by_hand('Bram', :charclass => 'Fighter', :level => 3, :feats => { 'general' => [ 'Pet' ] },
                       :approved => { 'name' => 'Biscuit', 'species' => 'terrier', 'form' => 'land', 'source' => 'Pet',
                                      'pet_abilities' => [ { 'name' => 'Darkvision' }, { 'name' => 'Tough' } ] })
        shown = sheet(bram)

        expect(shown).to include "Pathfinder 2E Pet: Biscuit (#{bram.name}'s pet)"
        expect(shown).to include 'Pet Abilities'
        expect(shown).to include 'Darkvision, Tough'
        expect(shown).to include 'HP: 21'
        expect(shown).not_to include 'Abilities Today'
        expect(shown).not_to include 'Spells'
      end

      it "should show a specific familiar's abilities and specials, and the day's count left" do
        morwen = by_hand('Morwen', :charclass => 'Witch', :specialize => 'Night', :level => 6,
                         :feats => { 'charclass' => [ 'Enhanced Familiar' ] }, :features => [ 'Familiar' ],
                         :approved => { 'name' => 'Whisk', 'species' => 'pipefox', 'form' => 'land', 'source' => 'Familiar',
                                        'specific' => 'Pipefox', 'choices' => { 'skill' => 'Arcana', 'language' => 'Myrrish' } })
        shown = sheet(morwen)

        expect(shown).to include "Pipefox (5 of Whisk's 6 Abilities)"
        expect(shown).to include 'Skilled (Arcana)'
        expect(shown).to include "Scholarly Linguist: Whisk speaks and understands every language you know, plus one common language you don't: Myrrish."
        expect(shown).to include 'Arcana: +8 (Skilled)'
        expect(shown).to include 'Traits: Beast, Minion'
        expect(shown).to include 'Abilities Today (0 of 1)'
      end

      # Natural Ambition's pick is labelled "Familiar", the name of the Witch's class feature, and a label
      # is not a feature.
      describe "a sorcerer's familiar from Natural Ambition, in chargen" do
        before(:each) do
          @sorcerer = by_hand('Corla', :charclass => 'Sorcerer', :level => 1,
                              :feats => { 'ancestry' => [ 'Natural Ambition' ], 'charclass' => [ 'Familiar' ] })
          @sorcerer.update(:pf2_to_assign => { 'feat_choices' => { 'Natural Ambition' => [ 'Familiar' ] } })
          @sorcerer = Character[@sorcerer.id]
        end

        it "should come from the feat, not the Witch's class feature" do
          expect(Familiar.witch_feature?(@sorcerer)).to be false
          expect(Familiar.sources(@sorcerer)).to eq [ { 'name' => 'Familiar', 'kind' => 'basic', 'feature' => false } ]
        end

        it "should show what is waiting, without spells" do
          shown = sheet(@sorcerer)

          expect(shown).to include 'Name: Not set'
          expect(shown).to include 'Species: Not set'
          expect(shown).to include 'Specific familiar (optional): No'
          expect(shown).to include 'Staff approve your familiar with your application.'
          # The details, then a divider, then what to do, as cg/review puts its messages last.
          expect(shown).to match(/Specific familiar \(optional\): No\s*\n%ld\s*\nStill needed: name, species, form\./)
          expect(shown).to include "For more information about setting up your familiar, see 'help chargen_familiar'."
          expect(shown).not_to include 'spells are allowed'
          expect(shown).not_to include 'Spells'
        end

        it "should list its details for cg/review, leaving what is still needed to the messages" do
          lines = Familiar.review_lines(@sorcerer)

          expect(lines).to include [ 'Name', 'Not set' ]
          expect(lines).to include [ 'Specific familiar (optional)', 'No' ]
          expect(lines.join).not_to include 'Still needed'
          expect(lines.last).to eq t('pf2e.familiar_review_note')
        end

        it "should say in cg/review's messages that there is a familiar to set up, until its details are set" do
          display = PF2CGReviewLockDisplay.new(@sorcerer, @client)
          allow(display).to receive(:stage).and_return('feats')

          expect(display.familiar_messages).to eq [ t('pf2e.familiar_review_setup') ]

          @sorcerer.update(:pf2_familiar => { 'pending' => { 'name' => 'Smudge', 'species' => 'black cat', 'form' => 'land' } })
          display = PF2CGReviewLockDisplay.new(Character[@sorcerer.id], @client)
          allow(display).to receive(:stage).and_return('feats')

          expect(display.familiar_messages).to eq []
        end

        it "should hold cg/review at the feats stage until the familiar's details are set" do
          @sorcerer.update(:pf2_checkpoint => 'skills', :pf2_skills_locked => true)

          stage = lambda do
            display = PF2CGReviewLockDisplay.new(Character[@sorcerer.id], @client)
            allow(display).to receive(:feat_messages).and_return([])
            allow(display).to receive(:magic_messages).and_return([])
            display.stage
          end

          expect(stage.call).to eq 'feats'

          @sorcerer.update(:pf2_familiar => { 'pending' => { 'name' => 'Smudge', 'species' => 'black cat', 'form' => 'land' } })

          expect(stage.call).to eq 'final'
        end
      end

      it "should say a familiar was gained when Natural Ambition's choice picks Familiar in chargen" do
        sorcerer = by_hand('Corla', :charclass => 'Sorcerer', :level => 1, :feats => { 'ancestry' => [ 'Natural Ambition' ] })
        sorcerer.update(:pf2_to_assign => { 'feat_choices' => { 'Natural Ambition' => [ 'open' ] } })
        sorcerer = Character[sorcerer.id]
        block = Pf2e.feat_choice_def(Pf2e.get_feat_details('Natural Ambition')[1])

        said = Pf2e.apply_feat_choice(sorcerer, 'Natural Ambition', block, 'Familiar', nil)

        expect(said).to include Advancement::FeatGain.familiar_gained(:details => Pf2e.get_feat_details('Familiar')[1], :chargen => true)
      end

      describe "gaining a familiar" do
        def gained(feat, chargen:)
          found = Pf2e.get_feat_details(feat)
          Advancement::FeatGain.familiar_gained(:details => found[1], :chargen => chargen)
        end

        it "should say what to set and that staff approve it with the application" do
          said = gained('Familiar', :chargen => true)

          expect(said).to start_with t('pf2e.familiar_gained')
          expect(said).to include t('pf2e.familiar_gained_chargen')
          expect(said).to end_with t('pf2e.familiar_gained_help_chargen')
        end

        it "should say a request opens at the end of a level" do
          said = gained('Familiar', :chargen => false)

          expect(said).to include t('pf2e.familiar_gained_advance')
          expect(said).to end_with t('pf2e.familiar_gained_help_advance')
        end

        # Witch Dedication's familiar comes from a patron, and the request at the end of the level approves both.
        it "should say a Witch Dedication familiar comes from a patron, and point at the Patron Template" do
          said = gained('Witch Dedication', :chargen => false)

          expect(said).to start_with t('pf2e.familiar_gained_witch')
          expect(said).to include t('pf2e.familiar_patron_request', :url => Familiar.patron_wiki_url)
          expect(said).to include 'wiki/mechanics:patrons'
          expect(said).not_to include t('pf2e.familiar_gained_advance')
          expect(said).to end_with t('pf2e.familiar_gained_help_advance')
        end

        it "should call a pet a pet, and ask for its two abilities" do
          said = gained('Pet', :chargen => true)

          expect(said).to start_with t('pf2e.familiar_gained_pet')
          expect(said).to include t('pf2e.familiar_gained_pet_abilities')
        end
      end

      it "should say a character has no familiar" do
        fighter = by_hand('Kor', :charclass => 'Fighter', :level => 1)

        expect(sheet(fighter)).to include "doesn't have a familiar or pet"
      end
    end
  end
end
