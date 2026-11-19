require "plugin_test_loader"

module AresMUSH
  module EaEvents

    # The player limit, the waitlist it makes, and the death-consent flag. The roster is the first
    # max_players sign-ups and the rest wait, so the specs sign people up in order and check who
    # lands where as the limit and the sign-ups change.
    describe "event limits and waitlists", :dbtest => true do
      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        allow(Login).to receive(:notify)
        allow(Login).to receive(:emit_ooc_if_logged_in)

        tag = rand(1000000)
        @gm = Character.create(:name => "Organizer#{tag}")
        @event = Event.create(:title => "Sunken Archive #{tag}", :starts => Time.now + 86400, :character => @gm)
        @chars = (1..4).map do |i|
          Character.create(:name => "Player#{i}x#{tag}", :pf2_level => i + 1,
            :pf2_base_info => { 'charclass' => 'Wizard' })
        end
        @chars.each { |c| EventSignup.create(:event => @event, :character => c) }
      end

      after(:each) do
        @event.delete if @event
        @chars.each { |c| c.delete }
        @gm.delete if @gm
      end

      def event
        Event[@event.id]
      end

      def names(signups)
        signups.map { |s| s.character.name }
      end

      it "should put everyone on the roster when there is no limit" do
        expect(EaEvents.max_players(event)).to be_nil
        expect(names(EaEvents.roster(event))).to eq @chars.map { |c| c.name }
        expect(EaEvents.waitlist(event)).to eq []
        expect(EaEvents.is_full?(event)).to eq false
      end

      it "should wait the sign-ups past the limit, in sign-up order" do
        event.update(max_players: 2)

        expect(names(EaEvents.roster(event))).to eq @chars.first(2).map { |c| c.name }
        expect(names(EaEvents.waitlist(event))).to eq @chars.drop(2).map { |c| c.name }
        expect(EaEvents.waitlist_position(event, @chars[3])).to eq 2
        expect(EaEvents.is_waitlisted?(event, @chars[0])).to eq false
        expect(EaEvents.is_full?(event)).to eq true
      end

      it "should tell a late sign-up their place on the waitlist" do
        event.update(max_players: 3)

        expect(EaEvents.signup_message(event, @chars[0])).to eq t('events.signed_up')
        expect(EaEvents.signup_message(event, @chars[3])).to include("#1 on the waitlist")
      end

      it "should move the most recent sign-ups to the waitlist when the limit drops" do
        promoted, demoted = EaEvents.set_max_players(event, 2)

        expect(promoted).to eq []
        expect(demoted.map { |c| c.name }).to eq @chars.drop(2).map { |c| c.name }
        expect(Login).to have_received(:notify).twice
      end

      it "should move the top of the waitlist up when the limit rises" do
        event.update(max_players: 1)
        promoted, demoted = EaEvents.set_max_players(event, 3)

        expect(promoted.map { |c| c.name }).to eq [ @chars[1].name, @chars[2].name ]
        expect(demoted).to eq []
      end

      it "should move everyone onto the roster when the limit is removed" do
        event.update(max_players: 1)
        promoted, demoted = EaEvents.set_max_players(event, nil)

        expect(promoted.count).to eq 3
        expect(EaEvents.waitlist(event)).to eq []
      end

      it "should promote and notify the first person waiting when someone cancels" do
        event.update(max_players: 2)

        error = Events.cancel_signup(event, @chars[0], @gm)

        expect(error).to be_nil
        expect(names(EaEvents.roster(event))).to eq [ @chars[1].name, @chars[2].name ]
        expect(Login).to have_received(:notify).with(@chars[2], :event, anything, @event.id).once
      end

      it "should not notify anyone when someone cancels and nobody is waiting" do
        Events.cancel_signup(event, @chars[0], @gm)

        expect(Login).not_to have_received(:notify)
      end

      it "should invite only the roster to the event scene" do
        event.update(max_players: 2)

        expect(EaEvents.roster(event).map { |s| s.character }).to eq @chars.first(2)
      end

      it "should notify everyone signed up when death consent is turned on, and no one when it is turned off" do
        EaEvents.set_death_consent(event, true)
        expect(event.death_consent).to eq true
        expect(Login).to have_received(:notify).exactly(4).times

        EaEvents.set_death_consent(event, false)
        expect(event.death_consent).to eq false
        expect(Login).to have_received(:notify).exactly(4).times
      end

      it "should not notify again when death consent is already on" do
        event.update(death_consent: true)
        EaEvents.set_death_consent(event, true)

        expect(Login).not_to have_received(:notify)
      end

      it "should summarize the player count" do
        expect(EaEvents.players_summary(event)).to eq "4 signed up"
        event.update(max_players: 6)
        expect(EaEvents.players_summary(event)).to eq "4/6"
        event.update(max_players: 4)
        expect(EaEvents.players_summary(event)).to eq "4/4 (Full)"
        event.update(max_players: 3)
        expect(EaEvents.players_summary(event)).to eq "3/3 (Full) - 1 on the waitlist"
        expect(EaEvents.screen_reader_players(event)).to eq "3 of 3, full, 1 on the waitlist"
      end

      it "should count players in words for screen readers" do
        expect(EaEvents.screen_reader_players(event)).to eq "4 signed up, no limit"
        event.update(max_players: 6)
        expect(EaEvents.screen_reader_players(event)).to eq "4 of 6"
        event.update(max_players: 4)
        expect(EaEvents.screen_reader_players(event)).to eq "4 of 4, full"
      end

      it "should label a sign-up with level and class, and leave it blank without a class" do
        expect(EaEvents.class_label(@chars[0])).to eq "Lvl 2 Wizard"
        expect(EaEvents.class_label(@gm)).to eq ""
      end

      it "should split the portal's sign-ups into a numbered roster and waitlist" do
        event.update(max_players: 3)
        # The stock handler's list, deliberately out of order.
        signups = EaEvents.ordered_signups(event).reverse.map { |s| { char: { name: s.char_name } } }

        fields = EaEvents.event_web_fields(event, signups)

        expect(fields[:roster].map { |s| s[:char][:name] }).to eq @chars.first(3).map { |c| c.name }
        expect(fields[:roster].map { |s| s[:position] }).to eq [ "1.", "2.", "3." ]
        expect(fields[:waitlist].map { |s| s[:position] }).to eq [ "W1" ]
        expect(fields[:is_full]).to eq true
      end

      # Rendered for real: ERB runs inside Erubis's namespace, so a template that calls this
      # plugin by its short name fails only when it is drawn.
      it "should lay the events list out in the portal's columns, two lines per event" do
        event.update(max_players: 3, death_consent: true)

        output = EaEvents::EventsListTemplate.new([ event ], "Events", @chars[3]).render

        expect(output).to match(/#\s+Title\s+Organizer\s+Date\/Time\s+Players/)
        expect(output).to match(/1\.\s+.*#{@event.title[0, 10]}.*#{@gm.name[0, 10]}.*3 \/ 3 Full/)
        expect(output).to match(/\[W\].*\[DC\].*server|\[W\].*\[DC\]/m)
        expect(output).to include("1 waitlisted")
        expect(output).to include(t('eaevents.list_legend'))
      end

      it "should show 'signed up' and 'No limit' for an event without a limit" do
        output = EaEvents::EventsListTemplate.new([ event ], "Events", @chars[0]).render

        expect(output).to include("4 signed up")
        expect(output).to include("No limit")
        expect(output).to include("[*]")
      end

      it "should say so when there are no events" do
        output = EaEvents::EventsListTemplate.new([], "Events", @gm).render

        expect(output).to include(t('eaevents.no_events'))
      end

      it "should give a screen reader one sentence per event, with words in place of symbols" do
        event.update(max_players: 3, death_consent: true)
        @chars[3].update(screen_reader: true)

        output = EaEvents::EventsListTemplate.new([ event ], "Events", Character[@chars[3].id]).render

        expect(output).to include("1. #{@event.title}. Death Consent. Organizer: #{@gm.name}.")
        expect(output).to include("Players: 3 of 3, full, 1 on the waitlist. You're on the waitlist.")
        expect(output).to include("server time).")
        expect(output).not_to include("[W]")
        expect(output).not_to include("[DC]")
        expect(output).not_to include(t('eaevents.list_legend'))
      end

      it "should show the player count, death consent, roster, and waitlist on the event page" do
        event.update(max_players: 3, death_consent: true)

        output = EaEvents::EventDetailTemplate.new(event, @gm).render

        expect(output).to include("3/3 (Full) - 1 on the waitlist")
        expect(output).to include(EaEvents.death_consent_line(false))
        expect(output).to include("/wiki/plots:dc-prps")
        expect(output).to include(t('eaevents.waitlist_title'))
        expect(output).to match(/1\.\s+#{@chars[0].name}\s+Lvl 2 Wizard/)
        expect(output).to match(/W1\s+#{@chars[3].name}\s+Lvl 5 Wizard/)
      end

      it "should give a screen reader each sign-up on the event page as a sentence" do
        event.update(max_players: 3, death_consent: true)
        EventSignup.find(character_id: @chars[0].id).first.update(comment: "Bringing a lantern")
        @gm.update(screen_reader: true)

        output = EaEvents::EventDetailTemplate.new(event, Character[@gm.id]).render

        expect(output).to include("Players: 3 of 3, full, 1 on the waitlist.")
        expect(output).to include("Death Consent (DC): Yes. Characters in this event can die, and what happens in it")
        expect(output).to include("see Death Consent Player-Run Plots: #{Game.web_portal_url}/wiki/plots:dc-prps")
        expect(output).to include("1. #{@chars[0].name}, Level 2 Wizard: Bringing a lantern")
        expect(output).to include("2. #{@chars[1].name}, Level 3 Wizard.")
        expect(output).to include("Waitlist 1. #{@chars[3].name}, Level 5 Wizard.")
        expect(output).not_to include("Lvl")
      end

      it "should save the portal form's limit and flag" do
        expect(EaEvents.check_web_fields('max_players' => 'lots')).not_to be_nil
        expect(EaEvents.check_web_fields('max_players' => '0')).not_to be_nil
        expect(EaEvents.check_web_fields('max_players' => '')).to be_nil

        EaEvents.save_web_fields(event, 'max_players' => '2', 'death_consent' => true)
        expect(EaEvents.max_players(event)).to eq 2
        expect(event.death_consent).to eq true

        EaEvents.save_web_fields(event, 'max_players' => nil, 'death_consent' => false)
        expect(EaEvents.max_players(event)).to be_nil
        expect(event.death_consent).to eq false
      end

      # ---- The level range. The four players are levels 2 to 5. ----

      it "should notify only the sign-ups a range change puts outside it" do
        told = EaEvents.set_level_range(event, [3, 4])

        expect(told).to eq [ @chars[0], @chars[3] ]
        expect(Login).to have_received(:notify).with(@chars[0], :event,
          t('eaevents.level_range_changed_notice', :title => @event.title, :range => "Levels 3-4",
            :name => @chars[0].name, :level => 2, :organizer => @gm.name, :num => EaEvents.event_number(event)),
          @event.id)

        # Player 1 was already outside and isn't told again; player 4 is back inside.
        told = EaEvents.set_level_range(event, [4, 5])
        expect(told).to eq [ @chars[1] ]
        expect(Login).to have_received(:notify).exactly(3).times
      end

      it "should notify no one when the range is cleared or widened" do
        event.update(min_level: 3, max_level: 4)

        expect(EaEvents.set_level_range(event, [1, 20])).to eq []
        expect(EaEvents.set_level_range(event, nil)).to eq []
        expect(EaEvents.level_range(event)).to be_nil
        expect(Login).not_to have_received(:notify)
      end

      it "should add a note to the sign-up message for a character outside the range" do
        event.update(min_level: 3, max_level: 4)

        expect(EaEvents.signup_message(event, @chars[1])).to eq t('events.signed_up')
        expect(EaEvents.signup_message(event, @chars[0])).to eq "You've signed up. " +
          "Note: #{@event.title} is for Levels 3-4, and #{@chars[0].name} is level 2. " +
          "Talk to #{@gm.name} to find out if you can still participate."
      end

      it "should put the level note after the waitlist message" do
        event.update(max_players: 3, min_level: 2, max_level: 4)

        message = EaEvents.signup_message(event, @chars[3])
        expect(message).to include("#1 on the waitlist")
        expect(message).to include("%rNote: #{@event.title} is for Levels 2-4")
      end

      it "should leave out characters without a level" do
        event.update(min_level: 3, max_level: 4)

        expect(EaEvents.level_fit(event, @gm)).to be_nil
        expect(EaEvents.level_note(event, @gm)).to be_nil
      end

      it "should show the level range and mark sign-ups outside it on the event page" do
        event.update(min_level: 3, max_level: 4)

        output = EaEvents::EventDetailTemplate.new(event, @gm).render

        expect(output).to include("Level Range:%xn Levels 3-4")
        expect(output).to match(/1\.\s+#{@chars[0].name}\s+Lvl 2 Wizard\s+\(below range\)/)
        expect(output).to match(/2\.\s+#{@chars[1].name}\s+Lvl 3 Wizard$/)
        expect(output).to match(/4\.\s+#{@chars[3].name}\s+Lvl 5 Wizard\s+\(above range\)/)
      end

      it "should leave the level range off the event page when there is none" do
        output = EaEvents::EventDetailTemplate.new(event, @gm).render

        expect(output).not_to include("Level Range:")
        expect(output).not_to include("range)")
      end

      it "should give a screen reader the level range and range marks in words" do
        event.update(min_level: 5, max_level: 8)
        @gm.update(screen_reader: true)

        output = EaEvents::EventDetailTemplate.new(event, Character[@gm.id]).render

        expect(output).to include("Level Range: T2, levels 5 to 8.")
        expect(output).to include("1. #{@chars[0].name}, Level 2 Wizard, below the level range.")
        expect(output).to include("4. #{@chars[3].name}, Level 5 Wizard.")
      end

      it "should show the level range in the events list" do
        event.update(min_level: 5, max_level: 12, death_consent: true)

        output = EaEvents::EventsListTemplate.new([ event ], "Events", @gm).render
        expect(output).to include("T2-T3 %xh%xr[DC]%xn")

        @gm.update(screen_reader: true)
        output = EaEvents::EventsListTemplate.new([ event ], "Events", Character[@gm.id]).render
        expect(output).to include("Death Consent. For T2 to T3, levels 5 to 12. Organizer:")
      end

      it "should save the portal form's level range and send it to the event page" do
        expect(EaEvents.check_web_fields('min_level' => '3', 'max_level' => '30')).not_to be_nil

        EaEvents.save_web_fields(event, 'min_level' => '4', 'max_level' => '3')
        expect(EaEvents.level_range(event)).to eq [3, 4]
        expect(Login).to have_received(:notify).twice

        signup = EaEvents.ordered_signups(event).first
        expect(EaEvents.signup_web_fields(signup)[:level_fit]).to eq "below range"
        fields = EaEvents.event_web_fields(event, [])
        expect(fields[:level_range]).to eq "Levels 3-4"
        expect(fields[:min_level]).to eq 3
        expect(EaEvents.event_list_web_fields(event, @gm)[:level_range]).to eq "Lv 3-4"

        EaEvents.save_web_fields(event, 'min_level' => '', 'max_level' => '')
        expect(EaEvents.level_range(event)).to be_nil
      end
    end
  end
end
