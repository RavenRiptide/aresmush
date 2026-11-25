require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # sheet/companion, against a real druid of the animal order and the real command.
    describe "the animal companion sheet", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        allow(Jobs).to receive(:notify)
        allow(Login).to receive(:notify)

        @char = Character.create(:name => "Grove#{rand(1000000)}")
        @other = Character.create(:name => "Look#{rand(1000000)}")
        @client = AutoBuilder::CaptureClient.new

        builder = AutoBuilder.new(@char)
        builder.prefer.merge!('Animal Companion' => 'Wolf')
        builder.build_level_one('Druid', specialty: 'Animal')
        @char = Character[@char.id]
      end

      after(:each) do
        @char.delete if @char
        @other.delete if @other
      end

      def view
        Companion::SheetView.build(Character[@char.id])
      end

      def section(title_key)
        view['sections'].find { |one| one['title'] == t(title_key) }
      end

      def rows(title_key)
        found = section(title_key)
        found ? found['rows'] : nil
      end

      def show(text, who = @char)
        @client.clear
        PF2CompanionSheetCmd.new(@client, Command.new(text), Character[who.id]).on_command
        (@client.successes + @client.failures).join("\n")
      end

      def name_and_approve(name)
        Companion.set_name!(@char, name)
        @char = Character[@char.id]
        Companion.approve!(@char, :by => @other, :close => false)
        @char = Character[@char.id]
      end

      describe "an unnamed young wolf in chargen" do
        it "should open with what waits for approval" do
          expect(view['title']).to eq t('pf2e.companion_sheet_title_unnamed', :char => @char.name)
          expect(rows('pf2e.companion_sheet_section_waiting')).to eq [
            [ [ t('pf2e.companion_label_name'), t('pf2e.companion_name_unset') ] ],
            t('pf2e.companion_sheet_waiting_unnamed')
          ]
        end

        it "should show its type, source, level, stage, size, and capitalized traits" do
          expect(rows('pf2e.companion_sheet_section_basic')).to eq [
            [ [ 'Type', 'Wolf' ], [ 'Source', 'Animal Companion' ] ],
            [ [ 'Level', 1 ], [ 'Stage', 'Young' ] ],
            [ [ 'Size', 'Small' ], [ 'Traits', 'Animal, Minion' ] ]
          ]
        end

        it "should show its stats, its trained skills, and a sentence for the rest" do
          expect(rows('pf2e.companion_sheet_section_attributes')).to eq [ [ [ 'Str', '+2' ], [ 'Dex', '+3' ], [ 'Con', '+2' ] ],
                                                                         [ [ 'Int', '-4' ], [ 'Wis', '+1' ], [ 'Cha', '+0' ] ] ]
          expect(rows('pf2e.companion_sheet_section_stats').first(2)).to eq [ [ [ 'HP', 14 ], [ 'AC', 16 ] ],
                                                                             [ [ 'Perception', '+4' ], [ 'Speed', '40 feet' ] ] ]
          expect(rows('pf2e.companion_sheet_section_saves')).to eq [ [ [ 'Fortitude', '+5' ], [ 'Reflex', '+6' ], [ 'Will', '+4' ] ] ]
          expect(rows('pf2e.companion_sheet_section_skills')).to eq [
            [ [ 'Acrobatics', '+6' ], [ 'Athletics', '+5' ], [ 'Survival', '+4' ] ],
            t('pf2e.companion_sheet_other_skills', :subject => t('pf2e.companion_subject_unnamed'))
          ]
        end

        it "should show its jaws, its support benefit, and when it learns its maneuver" do
          expect(rows('pf2e.companion_sheet_section_attacks')).to eq [ 'Jaws: +6 (Finesse), 1d8+2 piercing' ]
          expect(rows('pf2e.companion_sheet_section_support').first).to include 'status penalty to its Speeds'
          expect(rows('pf2e.companion_sheet_section_maneuver')).to eq [
            t('pf2e.companion_sheet_maneuver_later', :subject => t('pf2e.companion_subject_unnamed'), :maneuver => 'Takedown')
          ]
        end

        it "should say how it acts, and leave out the independent action a young companion lacks" do
          notes = rows('pf2e.companion_sheet_section_notes').first

          expect(notes).to include t('pf2e.companion_sheet_note_command', :subject => t('pf2e.companion_subject_unnamed'))
          expect(notes).not_to include 'Even without a Command'
          expect(section('pf2e.companion_sheet_section_specializations')).to be_nil
        end
      end

      describe "named and approved" do
        before(:each) do
          Roles.add_role(@char, 'approved')
          @char = Character[@char.id]
          Ledger.commit_chargen!(@char)
          @char = Character[@char.id]
          name_and_approve('Ash')
        end

        it "should drop the waiting section and speak of it by name" do
          expect(view['title']).to eq t('pf2e.companion_sheet_title', :name => 'Ash', :char => @char.name)
          expect(section('pf2e.companion_sheet_section_waiting')).to be_nil
          expect(rows('pf2e.companion_sheet_section_skills').last).to eq t('pf2e.companion_sheet_other_skills', :subject => 'Ash')
        end

        it "should render through sheet/companion, for its master and for anyone else" do
          expect(show('sheet/companion')).to include('Ash', 'Jaws: +6 (Finesse), 1d8+2 piercing')
          expect(show("sheet/companion #{@char.name}", @other)).to include 'Ash'
        end
      end

      it "should say a character has no companion" do
        expect(show("sheet/companion #{@other.name}")).to eq t('pf2e.companion_none', :char => @other.name)
      end

      it "should show only how to choose a type before one is chosen, with the wiki page" do
        allow(Companion).to receive(:list).and_return([ { 'id' => 'animal-companion', 'source' => 'Animal Companion', 'type' => nil,
                                                          'size' => nil, 'mature' => false, 'path' => nil,
                                                          'specializations' => [], 'pending' => [], 'waiting' => {} } ])

        expect(rows('pf2e.companion_sheet_section_type')).to eq [
          t('pf2e.companion_sheet_choose_type', :command => 'cg/option', :feat => 'Animal Companion'),
          t('pf2e.companion_sheet_wiki', :url => Companion.wiki_url)
        ]
        expect(section('pf2e.companion_sheet_section_basic')).to be_nil
      end

      it "should add the independent action of a Mature feat, and a mount's line" do
        mature = Global.read_config('pf2e_feats', 'Mature Animal Companion (Druid)')
        companion = Companion.list(Character[@char.id]).first.merge('mature' => true)
        allow(Companion).to receive(:list).and_return([ companion ])
        allow(Companion).to receive(:held).and_call_original
        allow(Companion).to receive(:held).with(anything, :draft => true).and_return(
          Companion.held(Character[@char.id], :draft => false) + [ [ 'Mature Animal Companion (Druid)', mature ] ])
        allow(Companion).to receive(:merged_grants).and_return('skills' => {}, 'raise_with' => {}, 'mount' => [ 'Wolf' ])

        notes = rows('pf2e.companion_sheet_section_notes').first

        expect(notes).to include t('pf2e.companion_sheet_note_independent', :subject => t('pf2e.companion_subject_unnamed_mid'))
        expect(notes).to include t('pf2e.companion_sheet_note_mount', :subject => t('pf2e.companion_subject_unnamed'))
        expect(rows('pf2e.companion_sheet_section_basic')[1]).to eq [ [ 'Level', 1 ], [ 'Stage', 'Mature' ] ]
      end
    end
  end
end
