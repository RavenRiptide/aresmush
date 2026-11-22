require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # A familiar's abilities for the day, picked with prepare/familiar. The witch is level 6 with a Night
    # patron: 4 abilities a day besides the patron's.
    describe "a familiar's abilities for the day", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Morwen#{rand(1000000)}")
        @combat = Pf2eCombat.create(:character => @char, :key_abil => 'Intelligence', :perception => 'trained',
                                    :armor_prof => { 'unarmored' => 'trained' })
        @char.update(:combat => @combat, :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {},
                     :pf2_lang => [ 'Kamin' ], :pf2_daily_choices => {})
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14) }
        witch(6)
        approve('Familiar')
      end

      after(:each) do
        @abilities.each(&:delete)
        @combat.delete
        @char.delete
      end

      def char
        Character[@char.id]
      end

      def witch(level, feats = {})
        become(:charclass => 'Witch', :specialize => 'Night', :level => level, :feats => feats, :features => [ 'Familiar' ])
      end

      def become(charclass:, level: 1, feats: {}, features: [], specialize: nil)
        char.update(:pf2_base_info => { 'charclass' => charclass, 'specialize' => specialize }.compact,
                     :pf2_level => level, :pf2_feats => feats, :pf2_features => { 'charclass_features' => features })
        Paths.apply_all!(char)
      end

      # Approved details for the familiar's current source, as staff approving them leave. Written through a
      # fresh copy: Ohm's `update` saves every attribute, so a stale one would put back its old `pf2_derived`.
      def approve(source, extra = {})
        approved = { 'name' => 'Smudge', 'species' => 'black cat', 'form' => 'land', 'source' => source }.merge(extra)
        char.update(:pf2_familiar => { 'approved' => approved })
      end

      def answers(typed)
        Familiar::Daily.answers(char, DailyChoices.for_switch(char, 'familiar'), typed)
      end

      it "should be open to a witch, by their Familiar class feature" do
        expect(DailyChoices.for_switch(char, 'familiar')).not_to be_nil
        expect(Familiar::Daily.budget(char)).to eq 4
      end

      it "should refuse a familiar awaiting approval" do
        char.update(:pf2_familiar => {})

        expect(answers('Darkvision').code).to eq :familiar_daily_waiting
      end

      it "should refuse a plain pet, which has no daily abilities" do
        become(:charclass => 'Fighter', :feats => { 'general' => [ 'Pet' ] })
        approve('Pet')

        expect(answers('Darkvision').code).to eq :familiar_daily_pet
      end

      it "should refuse a list it can't read" do
        expect(answers('Skilled (Arcana').code).to eq :familiar_daily_unreadable
      end

      it "should refuse a name that isn't an ability, and a patron's ability" do
        expect(answers('Telekinesis').code).to eq :familiar_daily_unknown
        expect(answers('Familiar of Stalking Night').code).to eq :familiar_daily_patron
      end

      describe "how many" do
        it "should take as many as the count allows, master abilities included" do
          found = answers('Darkvision, Flier, Tough, Lifelink')

          expect(found.ok?).to be true
          expect(found.state['pick']).to eq 'Darkvision, Flier, Tough, Lifelink'
        end

        it "should refuse more" do
          found = answers('Darkvision, Flier, Tough, Lifelink, Scent')

          expect(found.code).to eq :familiar_daily_count
          expect(found.args).to include('count' => 4, 'picked' => 5)
        end

        it "should leave what a specific familiar uses out of the day's count" do
          witch(6, 'charclass' => [ 'Enhanced Familiar' ])
          approve('Familiar', 'specific' => 'Pipefox', 'choices' => { 'skill' => 'Arcana', 'language' => 'Myrrish' })

          expect(Familiar::Daily.budget(char)).to eq 1
          expect(answers('Tough').ok?).to be true
          expect(answers('Tough, Scent').code).to eq :familiar_daily_count
        end
      end

      describe "choices" do
        it "should store a choice as the catalogue spells it" do
          expect(answers('Skilled (arcana)').state['abilities']).to eq [ { 'name' => 'Skilled', 'choice' => 'Arcana' } ]
        end

        it "should ask for a choice an ability needs, and list what it can be" do
          found = answers('Skilled')

          expect(found.code).to eq :familiar_daily_choice
          expect(found.args['list']).to include 'Arcana'
          expect(found.args['list']).not_to include 'Stealth'
        end

        it "should take Resistance's two different kinds" do
          expect(answers('Resistance (fire and cold)').state['abilities'].first['choice']).to eq %w{fire cold}
          expect(answers('Resistance (fire and cold)').state['pick']).to eq 'Resistance (fire, cold)'
          expect(answers('Resistance (fire, cold)').state['abilities'].first['choice']).to eq %w{fire cold}
          expect(answers('Resistance (fire)').code).to eq :familiar_daily_choice
          expect(answers('Resistance (fire, fire)').code).to eq :familiar_daily_choice
        end

        it "should refuse a choice an ability doesn't take" do
          expect(answers('Darkvision (owl)').code).to eq :familiar_daily_no_choice
        end

        it "should let Fast Movement raise only a Speed the familiar has today" do
          expect(answers('Fast Movement (fly)').code).to eq :familiar_daily_choice
          expect(answers('Flier, Fast Movement (fly)').ok?).to be true
        end

        it "should offer Speech only a language the master knows" do
          expect(answers('Speech (Kamin)').ok?).to be true
          expect(answers('Speech (Myrrish)').code).to eq :familiar_daily_choice
        end

        it "should take Cantrip Connection without a choice, its cantrip being chosen later" do
          allow(Familiar::Daily).to receive(:casts_cantrips?).and_return(true)

          expect(answers('Cantrip Connection, Cantrip Connection').ok?).to be true
          expect(answers('Cantrip Connection (Shield)').code).to eq :familiar_daily_no_choice
        end
      end

      describe "repeats" do
        it "should take a repeatable ability twice with different choices" do
          expect(answers('Skilled (Arcana), Skilled (Nature)').ok?).to be true
        end

        it "should refuse it twice with the same choice, and any other ability twice" do
          expect(answers('Skilled (Arcana), Skilled (arcana)').code).to eq :familiar_daily_twice
          expect(answers('Darkvision, Darkvision').code).to eq :familiar_daily_twice
        end

        it "should refuse an ability the familiar already has from its details" do
          witch(6, 'charclass' => [ 'Enhanced Familiar' ])
          approve('Familiar', 'specific' => 'Pipefox', 'choices' => { 'skill' => 'Arcana', 'language' => 'Myrrish' })

          found = answers('Darkvision')
          expect(found.code).to eq :familiar_daily_twice
          expect(found.key).to eq 'pf2e.familiar_daily_has'
        end
      end

      describe "prerequisites" do
        it "should need the abilities an ability builds on, today or fixed" do
          expect(answers('Construct').code).to eq :familiar_daily_prereq
          expect(answers('Tough, Construct').ok?).to be true
        end

        it "should need the master's level" do
          found = answers('Resistance (fire, cold), Major Resistance')

          expect(found.code).to eq :familiar_daily_prereq
          expect(found.args['needs']).to include '8'
        end

        it "should need the familiar's trait" do
          expect(answers('Speech (Kamin), Kinspeech').ok?).to be true
          expect(answers('Plant Form').code).to eq :familiar_daily_prereq
        end

        it "should need spell slots of the rank, and a focus pool" do
          expect(answers('Spell Battery').code).to eq :familiar_daily_prereq
          expect(answers('Familiar Focus').code).to eq :familiar_daily_prereq
        end

        it "should need a Homunculus for Poison Reservoir" do
          expect(answers('Poison Reservoir').code).to eq :familiar_daily_prereq
        end

        it "should allow only one ability that replaces the animal trait" do
          expect(answers('Tough, Construct, Dragon').code).to eq :familiar_daily_trait
        end
      end

      describe "a leshy familiar's pool" do
        before(:each) do
          become(:charclass => 'Druid', :specialize => 'Leaf', :level => 4,
                 :feats => { 'charclass' => [ 'Leshy Familiar', 'Leshy Familiar Secrets' ] })
          approve('Leshy Familiar', 'choices' => { 'ability' => 'Plant' })
        end

        it "should fill Leshy Familiar Secrets' slot only with a leshy ability" do
          expect(Familiar::Daily.budget(char)).to eq 3
          expect(answers('Darkvision, Tough, Grasping Tendrils').ok?).to be true
          expect(answers('Darkvision, Tough, Scent').code).to eq :familiar_daily_count
        end

        it "should refuse a second leshy ability" do
          expect(answers('Darkvision, Grasping Tendrils, Purify Air').code).to eq :familiar_daily_pool
        end

        it "should refuse leshy abilities without Leshy Familiar Secrets" do
          become(:charclass => 'Druid', :specialize => 'Leaf', :level => 4, :feats => { 'charclass' => [ 'Leshy Familiar' ] })

          expect(answers('Grasping Tendrils').code).to eq :familiar_daily_pool
          expect(Familiar::Daily.offer(char)).not_to include 'Grasping Tendrils'
        end

        it "should allow Plant Form, which a leshy's plant trait opens" do
          expect(answers('Plant Form').ok?).to be true
        end

        it "should refuse another ability that replaces the animal trait" do
          expect(answers('Dragon').code).to eq :familiar_daily_trait
        end
      end

      describe "a poppet's reinforcement" do
        before(:each) { approve('Familiar', 'specific' => 'Poppet') }

        it "should spend one of the day's abilities and remove its weakness to fire" do
          expect(Familiar::Daily.budget(char)).to eq 3
          expect(answers('Reinforced, Darkvision, Tough, Flier').code).to eq :familiar_daily_count

          DailyChoices.pick!(char, 'familiar', 'Reinforced, Darkvision')
          stats = Familiar::Stats.of(char, Familiar::Daily.abilities_today(char), :specific => 'Poppet',
                                     :options => Familiar::Daily.options(char))

          expect(stats['weaknesses']).to eq []
          expect(Familiar::Daily.abilities_today(char)).not_to include({ 'name' => 'Reinforced' })
        end

        it "should refuse it to any other familiar" do
          approve('Familiar')

          expect(answers('Reinforced').code).to eq :familiar_daily_reinforce
        end
      end

      describe "the day's pick" do
        it "should lock until the next rest, and give the abilities to its stats" do
          DailyChoices.pick!(char, 'familiar', 'Darkvision, Skilled (Arcana)')

          expect(Familiar::Daily.today(char)).to eq [ { 'name' => 'Darkvision' }, { 'name' => 'Skilled', 'choice' => 'Arcana' } ]
          expect(DailyChoices.pick!(char, 'familiar', 'Tough').code).to eq :already_picked

          today = Familiar::Daily.abilities_today(char)
          expect(today).to include({ 'name' => 'Familiar of Stalking Night' })
          expect(Familiar::Stats.of(char, today)['senses']).to include 'darkvision'
        end

        it "should take the pick back" do
          DailyChoices.pick!(char, 'familiar', 'Darkvision')
          DailyChoices.unpick!(char, 'familiar')

          expect(Familiar::Daily.today(char)).to eq []
        end

        it "should keep a legal pick through a rest, unlocked, with its abilities" do
          DailyChoices.pick!(char, 'familiar', 'Darkvision, Skilled (Arcana)')
          DailyChoices.rested!(char)

          held = DailyChoices.picks(char)['familiar']
          expect(held['locked']).to be false
          expect(Familiar::Daily.today(char)).to eq [ { 'name' => 'Darkvision' }, { 'name' => 'Skilled', 'choice' => 'Arcana' } ]
        end

        it "should put back yesterday's abilities when today's are taken back" do
          DailyChoices.pick!(char, 'familiar', 'Darkvision')
          DailyChoices.rested!(char)
          DailyChoices.pick!(char, 'familiar', 'Tough')
          DailyChoices.unpick!(char, 'familiar')

          expect(Familiar::Daily.today(char)).to eq [ { 'name' => 'Darkvision' } ]
        end

        it "should drop a pick at a rest that is no longer legal" do
          DailyChoices.pick!(char, 'familiar', 'Darkvision, Flier, Tough, Lifelink')
          witch(5)

          dropped = DailyChoices.rested!(char)

          expect(dropped.map { |one| one['switch'] }).to eq [ 'familiar' ]
          expect(Familiar::Daily.today(char)).to eq []
        end

        it "should be made with prepare/familiar" do
          Roles.add_role(@char, 'approved')
          client = AutoBuilder::CaptureClient.new

          PF2PrepareDailyCmd.new(client, Command.new('prepare/familiar Darkvision, Tough'), char).on_command

          expect(client.failures).to be_empty
          expect(client.successes.first).to include 'Darkvision, Tough'
          expect(Familiar::Daily.today(char).size).to eq 2
        end
      end

      describe "the listing" do
        def listing
          Familiar::Daily.listing(char)
        end

        def everything
          shown = listing
          shown['familiar'] + shown['needs'].map(&:first) + shown['master'] + shown['leshy']
        end

        it "should leave out what the master's own prerequisites rule out" do
          expect(everything).not_to include('Extra Vial', 'Extra Alchemy', 'Major Resistance', 'Poison Reservoir',
                                            'Spell Battery', 'Familiar Focus')
          expect(everything.grep(/Spellcasting/)).to be_empty
          expect(everything).not_to include 'Familiar of Stalking Night'
        end

        it "should list an ability with what it needs picked with it" do
          needs = listing['needs'].to_h

          expect(needs['Construct']).to eq [ 'Tough' ]
          expect(needs["Master's Form"]).to eq [ 'Manual Dexterity', 'Speech' ]
          expect(needs['Kinspeech']).to eq [ 'Speech' ]
          expect(needs['Plant Form']).to eq [ 'Plant' ]
          expect(listing['familiar']).not_to include 'Construct'
        end

        it "should open a level prerequisite once the master reaches it" do
          witch(8)

          expect(listing['needs'].to_h['Major Resistance']).to eq [ 'Resistance' ]
        end

        it "should say what a choice asks for, by its label where it has one" do
          expect(listing['familiar']).to include('Damage Avoidance (save)', 'Resistance (two damage types)',
                                                 'Skilled (skill)', 'Speech (language)')
          expect(listing['needs'].to_h).to have_key 'Elemental (element)'
          expect(listing['master']).to include('Lifelink', 'Share Senses')
        end

        it "should leave out an ability the familiar's details already give it" do
          witch(6, 'charclass' => [ 'Enhanced Familiar' ])
          approve('Familiar', 'specific' => 'Pipefox', 'choices' => { 'skill' => 'Arcana', 'language' => 'Myrrish' })

          expect(everything).not_to include 'Darkvision'
        end

        it "should show the day's picks, and how many it can have" do
          DailyChoices.pick!(char, 'familiar', 'Tough, Resistance (fire, cold)')

          expect(listing['selected']).to eq [ 'Resistance (fire, cold)', 'Tough' ]
          expect(listing['budget']).to eq 4
          expect(listing['name']).to eq 'Smudge'
        end

        it "should give the flat offer as every ability listed" do
          expect(Familiar::Daily.offer(char)).to eq everything.sort
        end

        describe "for a leshy familiar" do
          before(:each) do
            become(:charclass => 'Druid', :specialize => 'Leaf', :level => 4,
                   :feats => { 'charclass' => [ 'Leshy Familiar', 'Leshy Familiar Secrets' ] })
            approve('Leshy Familiar', 'choices' => { 'ability' => 'Plant' })
          end

          it "should list Plant Form plainly, and no other ability that replaces the animal trait" do
            expect(listing['familiar']).to include 'Plant Form'
            expect(everything).not_to include('Dragon', 'Construct', 'Fungus', 'Plant')
          end

          it "should list the leshy abilities on their own" do
            expect(listing['leshy']).to include('Grasping Tendrils', 'Purify Air')
            expect(listing['pooled']).to eq 1
          end
        end

        it "should lay out the screen, picks first" do
          DailyChoices.pick!(char, 'familiar', 'Darkvision')
          shown = PF2FamiliarDailyTemplate.new(listing, AutoBuilder::CaptureClient.new).render

          expect(shown).to include "Smudge's Abilities"
          expect(shown.index('Selected Abilities')).to be < shown.index('Available Abilities')
          expect(shown).to include 'Needs Manual Dexterity and Speech'
          expect(shown).to include 'Your familiar can have 4 abilities today.'
        end

        it "should say when nothing is picked yet, and name no familiar it hasn't been approved" do
          char.update(:pf2_familiar => {})
          shown = PF2FamiliarDailyTemplate.new(listing, AutoBuilder::CaptureClient.new).render

          expect(shown).to include "Your Familiar's Abilities"
          expect(shown).to include 'None yet.'
        end

        it "should be shown by prepare/familiar" do
          Roles.add_role(@char, 'approved')
          client = AutoBuilder::CaptureClient.new

          PF2PrepareDailyCmd.new(client, Command.new('prepare/familiar'), char).on_command

          expect(client.failures).to be_empty
          expect(client.successes.first).to include 'Available Abilities'
        end

        # Building the listing is most of what the command costs, and the database cache hides a second build
        # from a count of database commands, so count the builds.
        it "should build the listing once for prepare/familiar" do
          Roles.add_role(@char, 'approved')
          expect(Familiar::Daily).to receive(:listing).once.and_call_original

          PF2PrepareDailyCmd.new(AutoBuilder::CaptureClient.new, Command.new('prepare/familiar'), char).on_command
        end
      end
    end
  end
end
