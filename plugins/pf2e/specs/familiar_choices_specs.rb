require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # What a player picks for their familiar from closed lists: a specific familiar and its choices, a plain
    # Pet's two abilities, and Leshy Familiar's Plant or Fungus. Characters here are in chargen, so nothing
    # opens a request.
    describe "familiar choices", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = AutoBuilder::CaptureClient.new
        @staff = Character.create(:name => "Boss#{rand(1000000)}")
        @char = Character.create(:name => "Morwen#{rand(1000000)}")
        @combat = Pf2eCombat.create(:character => @char, :key_abil => 'Intelligence', :perception => 'trained',
                                    :armor_prof => { 'unarmored' => 'trained' })
        @char.update(:combat => @combat, :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {},
                     :pf2_lang => [ 'Kamin' ])
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14) }
        witch(6)
      end

      after(:each) do
        @abilities.each(&:delete)
        @combat.delete
        @char.delete
        @staff.delete
      end

      def char
        Character[@char.id]
      end

      def witch(level, feats = {})
        become(:charclass => 'Witch', :specialize => 'Night', :level => level, :feats => feats, :features => [ 'Familiar' ])
      end

      def become(charclass:, level: 1, feats: {}, features: [], specialize: nil)
        @char.update(:pf2_base_info => { 'charclass' => charclass, 'specialize' => specialize }.compact,
                     :pf2_level => level, :pf2_feats => feats, :pf2_features => { 'charclass_features' => features })
        Paths.apply_all!(char)
      end

      def run(klass, text)
        @client.clear
        klass.new(@client, Command.new(text), char).on_command
      end

      def set_details
        run(PF2FamiliarSetCmd, 'familiar/name Whisk')
        run(PF2FamiliarSetCmd, 'familiar/species pipefox')
        run(PF2FamiliarSetCmd, 'familiar/form land')
      end

      describe "a specific familiar" do
        it "should refuse a name that isn't one, and list them" do
          found = Familiar::Choices.specific(char, 'Imp')

          expect(found.code).to eq :familiar_specific_unknown
          expect(found.args['list']).to include 'Pipefox'
        end

        it "should match without regard to case and store the catalogue's spelling" do
          expect(Familiar::Choices.specific(char, 'poppet').state).to eq 'Poppet'
        end

        it "should refuse one that uses more abilities than the familiar has" do
          found = Familiar::Choices.specific(char, 'Pipefox')

          expect(found.code).to eq :familiar_specific_uses
          expect(found.args).to include('uses' => 5, 'count' => 4)
        end

        it "should allow it once the familiar has enough" do
          witch(6, 'charclass' => [ 'Enhanced Familiar' ])

          expect(Familiar::Choices.specific(char, 'Pipefox').state).to eq 'Pipefox'
        end

        it "should refuse a Spellslime to a master with no spell slots, and allow it to one with them" do
          expect(Familiar::Choices.top_slot_rank(char)).to eq 0
          expect(Familiar::Choices.specific(char, 'Spellslime').code).to eq :familiar_specific_slots

          allow(Familiar::Choices).to receive(:top_slot_rank).and_return(1)
          expect(Familiar::Choices.specific(char, 'Spellslime').state).to eq 'Spellslime'
        end

        it "should take none as no specific familiar" do
          expect(Familiar::Choices.specific(char, 'none').ok?).to be true
          expect(Familiar::Choices.specific(char, 'none').state).to be_nil
        end

        it "should refuse a familiar that is a particular creature" do
          { 'Rat Familiar' => { 'ancestry' => [ 'Rat Familiar' ] },
            'Alchemical Familiar' => { 'charclass' => [ 'Alchemical Familiar' ] },
            'Leshy Familiar' => { 'charclass' => [ 'Leshy Familiar' ] } }.each do |source, feats|
            become(:charclass => 'Fighter', :feats => feats)

            found = Familiar::Choices.specific(char, 'Poppet')
            expect(found.code).to eq :familiar_specific_fixed
            expect(found.args['source']).to eq source
          end
        end

        it "should refuse a plain pet" do
          become(:charclass => 'Fighter', :feats => { 'general' => [ 'Pet' ] })

          expect(Familiar::Choices.specific(char, 'Poppet').code).to eq :familiar_specific_fixed
        end

        it "should refuse one on an Alchemical Familiar merged into a witch's familiar" do
          become(:charclass => 'Alchemist', :level => 2,
                 :feats => { 'charclass' => [ 'Alchemical Familiar' ], 'dedication' => [ 'Witch Dedication' ] })

          expect(Familiar::Choices.specific(char, 'Poppet').code).to eq :familiar_specific_fixed
        end

        it "should refuse an aquatic familiar, and an aquatic form on a specific familiar" do
          run(PF2FamiliarSetCmd, 'familiar/form aquatic')
          expect(Familiar::Choices.specific(char, 'Poppet').code).to eq :familiar_specific_aquatic

          run(PF2FamiliarSetCmd, 'familiar/form land')
          run(PF2FamiliarSpecificCmd, 'familiar/specific Poppet')
          run(PF2FamiliarSetCmd, 'familiar/form aquatic')

          expect(@client.failures.first).to include 'Poppet'
          expect(Familiar.details(char)['form']).to eq 'land'
        end
      end

      describe "familiar/specific and familiar/choose" do
        before(:each) { witch(6, 'charclass' => [ 'Enhanced Familiar' ]) }

        it "should save the specific familiar and say which choices it has" do
          run(PF2FamiliarSpecificCmd, 'familiar/specific pipefox')

          expect(@client.failures).to be_empty
          expect(Familiar.details(char)['specific']).to eq 'Pipefox'
          expect(@client.oocs.first).to include('skill', 'language')
        end

        it "should store a choice as the list spells it" do
          run(PF2FamiliarSpecificCmd, 'familiar/specific Pipefox')
          run(PF2FamiliarChooseCmd, 'familiar/choose skill=arcana')

          expect(@client.failures).to be_empty
          expect(Familiar.details(char)['choices']).to eq('skill' => 'Arcana')
        end

        it "should refuse a skill Skilled can't raise, and save nothing" do
          run(PF2FamiliarSpecificCmd, 'familiar/specific Pipefox')
          run(PF2FamiliarChooseCmd, 'familiar/choose skill=Stealth')

          expect(@client.failures).not_to be_empty
          expect(Familiar.details(char)['choices']).to be_nil
        end

        it "should offer a Pipefox's extra language only from common languages the master doesn't know" do
          run(PF2FamiliarSpecificCmd, 'familiar/specific Pipefox')
          options = Familiar::Choices.open_choices(char)['language']['options']

          expect(options).to include 'Myrrish'
          expect(options).not_to include 'Kamin'
        end

        it "should offer a Fey Dragonet's Speech only from languages the master knows" do
          run(PF2FamiliarSpecificCmd, 'familiar/specific Fey Dragonet')

          expect(Familiar::Choices.open_choices(char)['language']['options']).to eq [ 'Kamin' ]
        end

        it "should refuse a choice the familiar doesn't have" do
          run(PF2FamiliarSpecificCmd, 'familiar/specific Pipefox')
          found = Familiar::Choices.choose(char, 'ability', 'Valet')

          expect(found.code).to eq :familiar_choice_word
        end

        it "should refuse familiar/choose for a familiar with no choices" do
          expect(Familiar::Choices.choose(char, 'skill', 'Arcana').code).to eq :familiar_choice_none
        end

        it "should start the choices again for another specific familiar" do
          run(PF2FamiliarSpecificCmd, 'familiar/specific Pipefox')
          run(PF2FamiliarChooseCmd, 'familiar/choose skill=Arcana')
          run(PF2FamiliarSpecificCmd, 'familiar/specific Homunculus')

          expect(Familiar.details(char)['choices']).to be_nil
          expect(Familiar::Choices.open_choices(char).keys).to eq [ 'ability' ]
        end

        it "should hold approval until every choice is made" do
          set_details
          run(PF2FamiliarSpecificCmd, 'familiar/specific Pipefox')

          expect(Familiar.missing(char)).to eq %w{skill language}
          expect(Familiar.approve!(char, :by => @staff).code).to eq :familiar_details_missing

          run(PF2FamiliarChooseCmd, 'familiar/choose skill=Arcana')
          run(PF2FamiliarChooseCmd, 'familiar/choose language=Myrrish')

          expect(Familiar.approve!(char, :by => @staff).ok?).to be true
        end

        it "should give the approved specific familiar's abilities, with its choices, to its stats" do
          set_details
          run(PF2FamiliarSpecificCmd, 'familiar/specific Pipefox')
          run(PF2FamiliarChooseCmd, 'familiar/choose skill=Arcana')
          run(PF2FamiliarChooseCmd, 'familiar/choose language=Myrrish')
          Familiar.approve!(char, :by => @staff)

          fixed = Familiar.fixed_abilities(char)

          expect(fixed).to include({ 'name' => 'Skilled', 'choice' => 'Arcana' }, { 'name' => 'Climber' })
          expect(fixed).to include({ 'name' => 'Familiar of Stalking Night' })
          expect(Familiar::Stats.of(char, fixed, :specific => 'Pipefox')['skills']['Arcana']).to eq 8
        end

        it "should give a Homunculus the Porter ability chosen" do
          set_details
          run(PF2FamiliarSpecificCmd, 'familiar/specific Homunculus')
          run(PF2FamiliarChooseCmd, 'familiar/choose ability=valet')
          Familiar.approve!(char, :by => @staff)

          expect(Familiar.fixed_abilities(char)).to include({ 'name' => 'Valet' })
          expect(Familiar.fixed_abilities(char)).not_to include({ 'name' => 'Item Delivery' })
        end

        it "should tell staff in app while a specific familiar's choices are unmade" do
          set_details
          run(PF2FamiliarSpecificCmd, 'familiar/specific Pipefox')
          expect(Familiar.app_review(char)).to include 'skill choice'

          run(PF2FamiliarChooseCmd, 'familiar/choose skill=Arcana')
          run(PF2FamiliarChooseCmd, 'familiar/choose language=Myrrish')
          expect(Familiar.app_review(char)).to include 'Familiar OK!'
        end
      end

      describe "a plain Pet's two abilities" do
        before(:each) { become(:charclass => 'Fighter', :level => 3, :feats => { 'general' => [ 'Pet' ] }) }

        it "should save two pet abilities" do
          run(PF2FamiliarPetCmd, 'familiar/pet darkvision, Tough')

          expect(@client.failures).to be_empty
          expect(Familiar.details(char)['pet_abilities']).to eq [ { 'name' => 'Darkvision' }, { 'name' => 'Tough' } ]
        end

        it "should refuse one, the same one twice, and one that isn't a pet ability" do
          expect(Familiar::Choices.pet_abilities(char, 'Darkvision').code).to eq :familiar_pet_two
          expect(Familiar::Choices.pet_abilities(char, 'Tough, tough').code).to eq :familiar_pet_twice
          expect(Familiar::Choices.pet_abilities(char, 'Tough, Speech').code).to eq :familiar_pet_unknown
          expect(Familiar::Choices.pet_abilities(char, 'Tough, (Darkvision').code).to eq :familiar_list_unreadable
        end

        it "should let Fast Movement raise only a Speed the pet has" do
          expect(Familiar::Choices.pet_abilities(char, 'Flier, Fast Movement (FLY)').state)
            .to eq [ { 'name' => 'Flier' }, { 'name' => 'Fast Movement', 'choice' => 'fly' } ]

          found = Familiar::Choices.pet_abilities(char, 'Tough, Fast Movement (fly)')
          expect(found.code).to eq :familiar_pet_choice
          expect(found.args['list']).to eq 'land'
        end

        it "should hold approval until both are chosen" do
          set_details
          expect(Familiar.missing(char)).to eq [ 'pet_abilities' ]

          run(PF2FamiliarPetCmd, 'familiar/pet Darkvision, Tough')
          expect(Familiar.missing(char)).to eq []
        end

        it "should give the approved pet abilities to its stats" do
          set_details
          run(PF2FamiliarPetCmd, 'familiar/pet Darkvision, Tough')
          Familiar.approve!(char, :by => @staff)

          expect(Familiar::Stats.of(char, Familiar.fixed_abilities(char))['hp']).to eq 21
        end

        it "should refuse familiar/pet for a familiar" do
          witch(6)

          expect(Familiar::Choices.pet_abilities(char, 'Darkvision, Tough').code).to eq :familiar_not_pet
        end

        it "should count Animal Accomplice's familiar as a familiar, though it brings the Pet feat" do
          become(:charclass => 'Rogue', :feats => { 'ancestry' => [ 'Animal Accomplice' ], 'general' => [ 'Pet' ] })

          expect(Familiar::Choices.plain_pet?(char)).to be false
        end
      end

      describe "a leshy familiar" do
        before(:each) do
          become(:charclass => 'Druid', :specialize => 'Leaf', :feats => { 'charclass' => [ 'Leshy Familiar' ] })
        end

        it "should ask for Plant or Fungus, and hold approval until it is chosen" do
          set_details
          expect(Familiar.missing(char)).to eq [ 'ability' ]

          run(PF2FamiliarChooseCmd, 'familiar/choose ability=fungus')

          expect(Familiar.details(char)['choices']).to eq('ability' => 'Fungus')
          expect(Familiar.missing(char)).to eq []
        end

        it "should give the chosen one to its stats" do
          set_details
          run(PF2FamiliarChooseCmd, 'familiar/choose ability=Plant')
          Familiar.approve!(char, :by => @staff)

          expect(Familiar.fixed_abilities(char)).to eq [ { 'name' => 'Plant' } ]
          expect(Familiar::Stats.of(char, Familiar.fixed_abilities(char))['traits']).to eq %w{minion plant}
        end
      end
    end
  end
end
