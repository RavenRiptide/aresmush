require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # A familiar's details and staff approval, against a real witch and the real commands.
    describe "familiar approval", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Witchy#{rand(1000000)}")
        @staff = Character.create(:name => "Boss#{rand(1000000)}")
        Roles.add_role(@staff, 'admin')
        @staff = Character[@staff.id]
        @client = AutoBuilder::CaptureClient.new

        # Requests are real jobs; only the notices they send to connected players are left out.
        allow(Jobs).to receive(:notify)
        allow(Login).to receive(:notify)

        AutoBuilder.new(@char).build_level_one('Witch')
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
        Familiar.approve_with_app!(@char)
        @char = Character[@char.id]
      end

      def run(klass, text, who = @char)
        @client.clear
        klass.new(@client, Command.new(text), Character[who.id]).on_command
        @char = Character[@char.id]
      end

      def set_all
        run(PF2FamiliarSetCmd, 'familiar/name Smudge')
        run(PF2FamiliarSetCmd, 'familiar/species black cat')
        run(PF2FamiliarSetCmd, 'familiar/form land')
      end

      it "should know a witch has a familiar, from their class feature" do
        expect(Familiar.main_source(@char)).to include('name' => 'Familiar', 'kind' => 'spellbook')
        expect(Familiar.awaiting_approval?(@char)).to be true
      end

      describe "in chargen" do
        it "should save details without opening a request" do
          set_all

          expect(@client.failures).to be_empty
          expect(Familiar.details(@char)).to eq('name' => 'Smudge', 'species' => 'black cat', 'form' => 'land')
          expect(Familiar.job(@char)).to be_nil
        end

        it "should refuse a bad name and save nothing" do
          run(PF2FamiliarSetCmd, 'familiar/name Smudge%r%rInky')

          expect(@client.failures).not_to be_empty
          expect(Familiar.details(@char)['name']).to eq ''
        end

        it "should show staff the familiar in app, and what it's missing" do
          run(PF2FamiliarSetCmd, 'familiar/name Smudge')

          expect(Familiar.app_review(@char)).to include 'Familiar missing species, form'
          set_all
          expect(Familiar.app_review(@char)).to include 'Familiar OK!'
        end

        it "should show the familiar in app's character sheet section, not Miscellaneous" do
          set_all

          expect(Pf2e.app_review(@char)).to include Familiar.app_review(@char)
          expect(AresMUSH::Chargen.custom_app_review(@char)).not_to include 'Familiar'
        end

        it "should approve complete details with the application" do
          set_all
          approve_app

          expect(Familiar.awaiting_approval?(@char)).to be false
          expect(Familiar.job(@char)).to be_nil
        end

        it "should open a request when the application is approved with details missing" do
          approve_app

          expect(Familiar.awaiting_approval?(@char)).to be true
          expect(Familiar.job(@char)).not_to be_nil
        end
      end

      describe "advancing" do
        it "should hold advance/done until the familiar's details are set" do
          expect(Array(Pf2e.advancement_messages(@char))).to include I18n.t('pf2e.familiar_review_setup')

          set_all

          expect(Array(Pf2e.advancement_messages(@char))).not_to include I18n.t('pf2e.familiar_review_setup')
        end

        it "should show advance/review the familiar while it waits for approval, and not once approved" do
          review = PF2AdvanceReviewTemplate.new(@char, @client)

          expect(review.show_familiar).to be true
          expect(review.familiar_title).to eq 'Familiar'
          expect(review.familiar.join).to include 'Specific familiar (optional)'

          set_all
          approve_app

          expect(PF2AdvanceReviewTemplate.new(@char, @client).show_familiar).to be false
        end
      end

      describe "after approval" do
        before(:each) { approve_app }

        it "should refuse to advance while the familiar waits" do
          @char.update(:pf2_xp => 5000)
          run(PF2ADvancementStartCmd, 'advance')

          expect(@client.failures).to eq [ I18n.t('pf2e.familiar_blocks_advance') ]
          expect(Character[@char.id].advancing).to be_falsey
        end

        it "should refuse approval while details are missing, and say which" do
          run(PF2FamiliarApproveCmd, "familiar/approve #{@char.name}", @staff)

          expect(@client.failures.first).to include 'species'
          expect(Familiar.awaiting_approval?(@char)).to be true
        end

        it "should approve the details, close the request, and let them advance" do
          set_all
          job = Familiar.job(@char)

          run(PF2FamiliarApproveCmd, "familiar/approve #{@char.name}", @staff)

          expect(@client.failures).to be_empty
          expect(Familiar.awaiting_approval?(@char)).to be false
          expect(Job[job.id].is_open?).to be false

          blocked = Advancement::Plan.can_advance(CharState.of(@char).merge('xp' => 5000),
                                                  'familiar_waiting' => Familiar.awaiting_approval?(@char))
          expect(blocked).to be_nil
        end

        it "should send details back in the request, which stays open" do
          set_all
          run(PF2FamiliarRejectCmd, "familiar/reject #{@char.name}=Pick a name that fits the setting.", @staff)

          job = Familiar.job(@char)
          expect(job).not_to be_nil
          expect(job.job_replies.to_a.map(&:message).last).to include 'Pick a name that fits the setting.'
        end

        it "should refuse familiar/approve to anyone without the permission" do
          set_all
          run(PF2FamiliarApproveCmd, "familiar/approve #{@char.name}")

          expect(@client.failures).to eq [ I18n.t('dispatcher.not_allowed') ]
        end

        describe "a change to approved details" do
          before(:each) do
            set_all
            run(PF2FamiliarApproveCmd, "familiar/approve #{@char.name}", @staff)
          end

          it "should open a request and keep the approved details in force" do
            run(PF2FamiliarSetCmd, 'familiar/name Inky')

            expect(Familiar.job(@char)).not_to be_nil
            expect(Familiar.awaiting_approval?(@char)).to be false
            expect(Familiar.approved_record(@char)['name']).to eq 'Smudge'
            expect(Familiar.details(@char)['name']).to eq 'Inky'
          end
        end

        describe "a new source taking over" do
          before(:each) do
            set_all
            run(PF2FamiliarApproveCmd, "familiar/approve #{@char.name}", @staff)

            # What taking Witch Dedication over another familiar leaves: approved details for the old source.
            held = Familiar.record(@char)
            held['approved']['source'] = 'Rat Familiar'
            @char.update(:pf2_familiar => held)
          end

          it "should wait for approval again, starting from the old details" do
            expect(Familiar.awaiting_approval?(@char)).to be true
            expect(Familiar.details(@char)['name']).to eq 'Smudge'
          end

          it "should open one request after the level, and say so once" do
            first = Familiar.after_level!(@char)
            second = Familiar.after_level!(Character[@char.id])

            expect(first).to include "##{Familiar.job(Character[@char.id]).id}"
            expect(second).to be_nil
          end

          # A witch's request approves their patron too, and points at the template to describe one with.
          it "should ask for the patron with the Patron Template, in the notice and the request" do
            said = Familiar.after_level!(@char)
            job = Familiar.job(Character[@char.id])

            expect(said).to include Familiar.patron_wiki_url
            expect(said).to include 'Patron Template'
            expect(job.description).to include t('pf2e.familiar_request_patron', :url => Familiar.patron_wiki_url)
          end

          it "should leave the patron out of a request for a familiar no patron sent" do
            allow(Familiar).to receive(:patron?).and_return(false)

            said = Familiar.after_level!(@char)

            expect(said).not_to include 'patron'
            expect(Familiar.job(Character[@char.id]).description).not_to include 'Patron Template'
          end
        end
      end
    end
  end
end
