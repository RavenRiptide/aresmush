require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # A companion's death and its replacement, against a real druid of the animal order: raised exactly as it
    # was, a new animal of the same build, and a different companion whose choices are rewritten at their
    # levels and survive a rollback and a redo as those levels' own.
    describe "replacing an animal companion", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        allow(Jobs).to receive(:notify)
        allow(Login).to receive(:notify)

        @char = Character.create(:name => "Grove#{rand(1000000)}")
        @staff = Character.create(:name => "Boss#{rand(1000000)}")
        Roles.add_role(@staff, 'admin')
        @staff = Character[@staff.id]
        @client = AutoBuilder::CaptureClient.new

        @builder = AutoBuilder.new(@char)
        @builder.prefer.merge!('Animal Companion' => 'Wolf', 'Incredible Companion (Druid)' => 'Savage')
        @builder.build_level_one('Druid', specialty: 'Animal')
        @char = Character[@char.id]
      end

      after(:each) do
        @char.delete if @char
        @staff.delete if @staff
      end

      def approve_app
        run(PF2CompanionNameCmd, 'companion/name Ash')
        Roles.add_role(@char, 'approved')
        @char = Character[@char.id]
        Ledger.commit_chargen!(@char)
        Companion.approve_with_app!(@char)
        @char = Character[@char.id]
        @builder.instance_variable_set(:@char, @char)
      end

      def run(klass, text, who = @char)
        @client.clear
        klass.new(@client, Command.new(text), Character[who.id]).on_command
        @char = Character[@char.id]
      end

      def companion
        Companion.main(Character[@char.id])
      end

      def choices(name)
        Pf2e.recorded_choices(Character[@char.id]).select { |choice, _label, _level| choice == name }
                                                     .map { |_choice, label, level| [ label, level ] }
      end

      def history
        char = Character[@char.id]
        LevelHistory.groups(Ledger.rows(char), char.pf2_level).flat_map { |_group, lines| lines }
      end

      it "should refuse to replace a companion in chargen" do
        run(PF2CompanionReplaceCmd, 'companion/replace')

        expect(@client.failures.last).to eq t('pf2e.companion_replace_chargen')
      end

      describe "an approved young wolf" do
        before(:each) { approve_app }

        it "should let staff mark it dead and alive again, saying so on its sheet" do
          run(PF2CompanionDeadCmd, "companion/dead #{@char.name}", @staff)
          expect(@client.successes.last).to eq t('pf2e.companion_marked_dead', :char => @char.name, :name => 'Ash')
          expect(Companion.dead?(@char)).to be true
          status = Companion::SheetView.build(@char)['sections'].first

          expect(status['rows']).to eq [ t('pf2e.companion_sheet_dead', :subject => 'Ash') ]

          run(PF2CompanionDeadCmd, "companion/revive #{@char.name}", @staff)
          expect(@client.successes.last).to eq t('pf2e.companion_revived', :char => @char.name, :name => 'Ash')
          expect(Companion.dead?(@char)).to be false
          expect(Companion.approved_record(@char)['name']).to eq 'Ash'
        end

        it "should replace it with a new wolf, leaving the ledger's choices alone and recording it in sheet/history" do
          run(PF2CompanionReplaceCmd, 'companion/replace')
          request = Companion.job(@char)

          expect(@client.successes.last).to start_with t('pf2e.companion_replace_started', :old => 'Ash', :type => 'wolf')
          expect(Companion.approved_record(@char)['name']).to eq 'Ash'

          run(PF2CompanionNameCmd, 'companion/name Bran')
          expect(@client.successes.last).to eq t('pf2e.companion_name_set_replacement', :name => 'Bran')

          run(PF2CompanionApproveCmd, "companion/approve #{@char.name}", @staff)

          expect(@client.successes.last).to eq t('pf2e.companion_approved_replacement', :char => @char.name, :name => 'Bran')
          expect(Companion.approved_record(@char)).to include('name' => 'Bran', 'type' => 'Wolf')
          expect(choices('Animal Companion')).to eq [ [ 'Wolf', 1 ] ]
          expect(Job[request.id].is_open?).to be false
          expect(history).to include [ 'Companion', [ 'Ash, wolf companion, replaced by Bran' ] ]
        end

        it "should replace it with a bear, rewriting the type at level 1" do
          run(PF2CompanionReplaceCmd, 'companion/replace Bear')
          run(PF2CompanionNameCmd, 'companion/name Bruin')
          run(PF2CompanionApproveCmd, "companion/approve #{@char.name}", @staff)

          expect(companion['type']).to eq 'Bear'
          expect(choices('Animal Companion')).to eq [ [ 'Bear', 1 ] ]
          expect(Companion.approved_record(@char)).to include('name' => 'Bruin', 'type' => 'Bear')
          expect(history).to include [ 'Companion', [ 'Ash, wolf companion, replaced by Bruin, bear companion' ] ]
        end

        it "should refuse a type its feat can't have, listing what it can" do
          run(PF2CompanionReplaceCmd, 'companion/replace Riding Drake')

          expect(@client.failures.last).to start_with "You can't choose Riding Drake with Animal Companion."
          expect(Companion.replacement(@char)).to be_nil
        end

        it "should refuse approval until the new companion has a name" do
          run(PF2CompanionReplaceCmd, 'companion/replace Bear')
          run(PF2CompanionApproveCmd, "companion/approve #{@char.name}", @staff)

          expect(@client.failures.last).to eq t('pf2e.companion_replace_incomplete', :char => @char.name, :missing => 'name')
          expect(companion['type']).to eq 'Wolf'
        end

        it "should withdraw a replacement, keeping the old companion and closing the request" do
          run(PF2CompanionReplaceCmd, 'companion/replace Bear')
          request = Companion.job(@char)
          run(PF2CompanionNameCmd, 'companion/name Bruin')
          run(PF2CompanionReplaceCancelCmd, 'companion/replace/cancel')

          expect(@client.successes.last).to eq t('pf2e.companion_replace_cancelled', :old => 'Ash')
          expect(Companion.replacement(@char)).to be_nil
          expect(Companion.name_of(@char)).to eq 'Ash'
          expect(Job[request.id].is_open?).to be false
        end

        it "should refuse to start a second replacement, and to replace mid-level" do
          run(PF2CompanionReplaceCmd, 'companion/replace')
          run(PF2CompanionReplaceCmd, 'companion/replace Bear')
          expect(@client.failures.last).to eq t('pf2e.companion_replace_busy')

          run(PF2CompanionReplaceCancelCmd, 'companion/replace/cancel')
          Pf2e.award_xp(@char, 1000, 'spec', 'level')
          @builder.instance_variable_set(:@char, Character[@char.id])
          @builder.run('advance')
          run(PF2CompanionReplaceCmd, 'companion/replace')

          expect(@client.failures.last).to eq t('pf2e.companion_replace_advancing')
        end

        it "should say a young companion has nothing to choose again" do
          run(PF2CompanionReplaceCmd, 'companion/replace Bear')
          run(PF2CompanionReplaceOptionCmd, 'companion/replace/option Incredible Companion (Druid)=Nimble')

          expect(@client.failures.last).to eq t('pf2e.companion_replace_same_build', :old => 'Ash')
        end
      end

      describe "a savage wolf at level 9" do
        before(:each) do
          approve_app
          Pf2e.award_xp(@char, 11000, 'spec', 'level')
          @char = Character[@char.id]
          @builder.instance_variable_set(:@char, @char)

          (2..9).each do |level|
            @builder.clear
            @builder.run('advance')
            @builder.run('advance/feat charclass=Mature Animal Companion (Druid)') if level == 4
            @builder.run('advance/feat charclass=Incredible Companion (Druid)') if level == 8
            6.times { break if @builder.resolve_outstanding(:advance).zero? }
            @builder.run('advance/done')
            expect(@builder.failures).to be_empty
          end

          @char = Character[@char.id]
        end

        it "should start at 9 with a savage wolf chosen at 8" do
          expect(@char.pf2_level).to eq 9
          expect(choices('Incredible Companion (Druid)')).to eq [ [ 'Savage', 8 ] ]
        end

        it "should ask a bear for nimble or savage again, refusing anything else, then rewrite it at level 8" do
          run(PF2CompanionReplaceCmd, 'companion/replace Bear')
          expect(@client.successes.last).to include t('pf2e.companion_replace_choose', :feats => 'Incredible Companion (Druid)')

          run(PF2CompanionReplaceOptionCmd, 'companion/replace/option Incredible Companion (Druid)=Swift')
          expect(@client.failures.last).to eq t('pf2e.companion_replace_bad_choice', :choice => 'Swift',
                                                :feat => 'Incredible Companion (Druid)', :options => 'Nimble, Savage')

          run(PF2CompanionReplaceOptionCmd, 'companion/replace/option Incredible Companion (Druid)=Nimble')
          expect(@client.successes.last).to eq t('pf2e.companion_replace_option_set', :feat => 'Incredible Companion (Druid)', :choice => 'Nimble')

          run(PF2CompanionNameCmd, 'companion/name Bruin')
          run(PF2CompanionApproveCmd, "companion/approve #{@char.name}", @staff)

          expect(companion.values_at('type', 'path')).to eq [ 'Bear', 'nimble' ]
          expect(choices('Incredible Companion (Druid)')).to eq [ [ 'Nimble', 8 ] ]
          expect(choices('Animal Companion')).to eq [ [ 'Bear', 1 ] ]
        end

        it "should take the rewritten choice back with level 8, and bring it back with a redo" do
          run(PF2CompanionReplaceCmd, 'companion/replace Bear')
          run(PF2CompanionReplaceOptionCmd, 'companion/replace/option Incredible Companion (Druid)=Nimble')
          run(PF2CompanionNameCmd, 'companion/name Bruin')
          run(PF2CompanionApproveCmd, "companion/approve #{@char.name}", @staff)

          expect(Pf2e.rollback_to_level(Character[@char.id], 8, @staff)).to be_nil
          expect(choices('Incredible Companion (Druid)')).to eq []
          expect(choices('Animal Companion')).to eq [ [ 'Bear', 1 ] ]

          expect(Pf2e.redo_rollback(Character[@char.id], @staff)).to be_nil
          expect(choices('Incredible Companion (Druid)')).to eq [ [ 'Nimble', 8 ] ]
        end
      end
    end
  end
end
