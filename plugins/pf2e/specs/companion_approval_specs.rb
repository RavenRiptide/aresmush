require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # An animal companion's name and staff approving it, against a real druid of the animal order and the real
    # commands.
    describe "animal companion approval", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Grove#{rand(1000000)}")
        # Letters only, so the name passes the name rules and is refused only for being taken.
        @staff = Character.create(:name => "Boss#{Array.new(8) { ('a'..'z').to_a.sample }.join}")
        Roles.add_role(@staff, 'admin')
        @staff = Character[@staff.id]
        @client = AutoBuilder::CaptureClient.new

        # Requests are real jobs; only the notices they send to connected players are left out.
        allow(Jobs).to receive(:notify)
        allow(Login).to receive(:notify)

        builder = AutoBuilder.new(@char)
        builder.prefer.merge!('Animal Companion' => 'Wolf')
        builder.build_level_one('Druid', specialty: 'Animal')
        @char = Character[@char.id]
      end

      after(:each) do
        @char.delete if @char
        @staff.delete if @staff
      end

      def approve_app
        Roles.add_role(@char, 'approved')
        @char = Character[@char.id]
        Ledger.commit_chargen!(@char)
        Companion.approve_with_app!(@char)
        @char = Character[@char.id]
      end

      def run(klass, text, who = @char)
        @client.clear
        klass.new(@client, Command.new(text), Character[who.id]).on_command
        @char = Character[@char.id]
      end

      it "should have a wolf waiting for a name" do
        expect(Companion.main(@char)['type']).to eq 'Wolf'
        expect(Companion.awaiting_approval?(@char)).to be true
        expect(Companion.missing(@char)).to eq [ 'name' ]
      end

      describe "in chargen" do
        it "should show the name as not yet set, and ask for one on cg/review" do
          lines = Companion.review_lines(@char)

          expect(lines.first).to eq [ t('pf2e.companion_label_name'), t('pf2e.companion_name_unset') ]
          expect(Companion.unfinished_name?(@char)).to be true
        end

        it "should leave its stats to sheet/companion, pointing to it from cg/review" do
          lines = Companion.review_lines(@char)

          expect(lines).to include [ t('pf2e.companion_label_type'), "Wolf (#{Companion.stats(@char, Companion.main(@char))['stage']})" ]
          expect(lines.last).to eq t('pf2e.companion_review_note')
          expect(lines.flatten.join).not_to include 'HP'
          expect(lines.flatten.join).not_to include 'Jaws'
        end

        it "should save a name without opening a request" do
          run(PF2CompanionNameCmd, 'companion/name Ash')

          expect(@client.failures).to be_empty
          expect(@client.successes.last).to eq t('pf2e.companion_name_set', :name => 'Ash')
          expect(Companion.name_of(@char)).to eq 'Ash'
          expect(Companion.job(@char)).to be_nil
          expect(Companion.review_lines(@char)).to include t('pf2e.companion_review_app', :name => 'Ash')
        end

        it "should refuse a name of two words, a character's name, and its familiar's name, saving nothing" do
          run(PF2CompanionNameCmd, 'companion/name Ash Grey')
          expect(@client.failures.last).to eq t('pf2e.companion_name_chars')

          run(PF2CompanionNameCmd, "companion/name #{@staff.name}")
          expect(@client.failures.last).to eq t('pf2e.companion_name_taken', :name => @staff.name)

          allow(Familiar).to receive(:main_source).and_return('name' => 'Pet', 'kind' => 'basic')
          allow(Familiar).to receive(:details).and_return('name' => 'Smudge')
          run(PF2CompanionNameCmd, 'companion/name Smudge')
          expect(@client.failures.last).to eq t('pf2e.companion_name_familiar', :name => 'Smudge')

          expect(Companion.name_of(@char)).to be_nil
        end

        it "should refuse a familiar named as the companion is" do
          run(PF2CompanionNameCmd, 'companion/name Ash')
          allow(Familiar).to receive(:main_source).and_return('name' => 'Pet', 'kind' => 'basic')
          run(PF2FamiliarSetCmd, 'familiar/name Ash')

          expect(@client.failures.last).to eq t('pf2e.familiar_name_companion', :name => 'Ash')
        end

        it "should say in app whether the companion is ready" do
          expect(Companion.app_review(@char)).to include t('pf2e.companion_app_missing', :missing => 'name')

          run(PF2CompanionNameCmd, 'companion/name Ash')
          expect(Companion.app_review(@char)).to include t('pf2e.companion_app_ok', :name => 'Ash', :type => 'wolf')
        end

        it "should approve a named companion with the application" do
          run(PF2CompanionNameCmd, 'companion/name Ash')
          approve_app

          expect(Companion.approved?(@char)).to be true
          expect(Companion.approved_record(@char)).to include('name' => 'Ash', 'source' => 'Animal Companion', 'type' => 'Wolf')
          expect(Companion.job(@char)).to be_nil
        end

        it "should open a request when the application is approved without a name" do
          approve_app

          expect(Companion.approved?(@char)).to be false
          expect(Companion.job(@char)).not_to be_nil
        end
      end

      describe "after approval" do
        before(:each) do
          run(PF2CompanionNameCmd, 'companion/name Ash')
          approve_app
        end

        it "should keep the approved name in force while a new one waits in a request" do
          run(PF2CompanionNameCmd, 'companion/name Bran')
          request = Companion.job(@char)

          expect(request).not_to be_nil
          expect(@client.successes.last).to eq t('pf2e.companion_name_set_request', :name => 'Bran', :number => request.id)
          expect(Companion.name_of(@char)).to eq 'Bran'
          expect(Companion.approved_record(@char)['name']).to eq 'Ash'
        end

        it "should let staff approve the new name, closing the request" do
          run(PF2CompanionNameCmd, 'companion/name Bran')
          request = Companion.job(@char)
          run(PF2CompanionApproveCmd, "companion/approve #{@char.name}", @staff)

          expect(@client.successes.last).to eq t('pf2e.companion_approved', :char => @char.name, :name => 'Bran')
          expect(Companion.approved_record(@char)['name']).to eq 'Bran'
          expect(Job[request.id].is_open?).to be false
        end

        it "should let staff send a name back, with the reason in the request" do
          run(PF2CompanionNameCmd, 'companion/name Bran')
          run(PF2CompanionRejectCmd, "companion/reject #{@char.name}=Try a wolfier name.", @staff)

          expect(@client.successes.last).to eq t('pf2e.companion_rejected', :char => @char.name)
          expect(Companion.job(@char).job_replies.to_a.map(&:message).join).to include 'Try a wolfier name.'
          expect(Companion.approved_record(@char)['name']).to eq 'Ash'
        end

        it "should refuse a player approving their own companion" do
          run(PF2CompanionApproveCmd, "companion/approve #{@char.name}")

          expect(@client.failures.last).to eq t('dispatcher.not_allowed')
        end

        it "should need nothing after a level once approved" do
          expect(Companion.after_level!(@char)).to be_nil
        end
      end

      it "should open a request after a level for a companion still waiting, and say so once" do
        Roles.add_role(@char, 'approved')
        @char = Character[@char.id]
        Ledger.commit_chargen!(@char)
        @char = Character[@char.id]

        said = Companion.after_level!(@char)
        request = Companion.job(@char)

        expect(said).to eq t('pf2e.companion_request_opened_unnamed', :number => request.id)
        expect(Companion.after_level!(Character[@char.id])).to be_nil
      end
    end
  end
end
