module AresMUSH
  module EaEvents

    # ---- The limit, the roster, and the waitlist ------------------------------------------------
    #
    # Nothing records who is on the roster. The first `max_players` sign-ups, by the time they
    # signed up, are the roster and the rest are the waitlist, so a cancellation or a change to the
    # limit moves people between the two without anything else being written. Changing a sign-up's
    # comment keeps its place, because the stock plugin updates the comment on the existing record.

    # The player limit, or nil for none.
    def self.max_players(event)
      limit = event.max_players.to_i
      limit > 0 ? limit : nil
    end

    # Sign-ups in the order they were made. The stock ordered_signups sorts by created_at, which
    # is whole seconds, so two sign-ups in the same second could swap places between one look and
    # the next - and swap who is on the roster. Record ids only go up, so they break the tie.
    def self.ordered_signups(event)
      event.signups.to_a.sort_by { |s| s.id.to_i }
    end

    def self.roster(event)
      limit = EaEvents.max_players(event)
      signups = EaEvents.ordered_signups(event)
      limit ? signups.first(limit) : signups
    end

    def self.waitlist(event)
      limit = EaEvents.max_players(event)
      limit ? EaEvents.ordered_signups(event).drop(limit) : []
    end

    def self.is_full?(event)
      limit = EaEvents.max_players(event)
      !!limit && event.signups.count >= limit
    end

    def self.roster_ids(event)
      EaEvents.roster(event).map { |s| s.id }
    end

    # 1 for the first person waiting, or nil when the character isn't on the waitlist.
    def self.waitlist_position(event, char)
      index = EaEvents.waitlist(event).index { |s| s.character == char }
      index ? index + 1 : nil
    end

    def self.is_waitlisted?(event, char)
      !!EaEvents.waitlist_position(event, char)
    end

    # Whether any of the player's characters is waiting, the way the stock is_signed_up? counts
    # sign-ups across alts.
    def self.any_alt_waitlisted?(event, char)
      return false if !char
      AresCentral.alts(char).any? { |alt| EaEvents.is_waitlisted?(event, alt) }
    end

    # ---- Changing the limit and the flag --------------------------------------------------------

    # Sets the limit (nil for none) and tells everyone it moved. Returns the characters who moved
    # onto the roster and the ones who moved to the waitlist, in that order.
    def self.set_max_players(event, limit)
      before = EaEvents.roster_ids(event)
      event.update(max_players: limit)

      after = EaEvents.roster(event)
      promoted = after.reject { |s| before.include?(s.id) }.map { |s| s.character }.compact
      demoted = EaEvents.ordered_signups(event).select { |s| before.include?(s.id) && !after.include?(s) }
                     .map { |s| s.character }.compact

      promoted.each { |c| EaEvents.notify_promoted(event, c) }
      demoted.each do |c|
        EaEvents.notify(c, event, t('eaevents.moved_to_waitlist_notice', :title => event.title,
          :limit => limit, :position => EaEvents.waitlist_position(event, c)))
      end

      [ promoted, demoted ]
    end

    # Sets the death-consent flag. Turning it on tells everyone signed up or waiting, since they
    # signed up for an event that didn't carry that risk; turning it off tells no one.
    def self.set_death_consent(event, on)
      was_on = !!event.death_consent
      event.update(death_consent: on)
      return if !on || was_on

      event.signups.each do |s|
        next if !s.character
        EaEvents.notify(s.character, event, t('eaevents.death_consent_added_notice',
          :title => event.title, :num => EaEvents.event_number(event)))
      end
    end

    # Notifies whoever moved onto the roster since `roster_before` (from roster_ids) was taken.
    # The stock cancel_signup calls this after it deletes a sign-up.
    def self.notify_promotions(event, roster_before)
      EaEvents.roster(event).each do |s|
        next if roster_before.include?(s.id) || !s.character
        EaEvents.notify_promoted(event, s.character)
      end
    end

    def self.notify_promoted(event, char)
      EaEvents.notify(char, event, t('eaevents.promoted_notice', :title => event.title, :name => char.name))
    end

    # A notice on the web portal, and the same line in game if the character is connected.
    def self.notify(char, event, message)
      Login.notify(char, :event, message, event.id)
      Login.emit_ooc_if_logged_in(char, message)
    end

    # The event's number in the `events` list, which is what event commands take.
    def self.event_number(event)
      index = Event.sorted_events.index(event)
      index ? index + 1 : "?"
    end

    # ---- What players see -----------------------------------------------------------------------

    # What the game says to someone who just signed up (or changed their comment).
    def self.signup_message(event, char)
      position = EaEvents.waitlist_position(event, char)
      return t('events.signed_up') if !position
      t('eaevents.signed_up_waitlisted', :title => event.title, :position => position)
    end

    # "Lvl 5 Wizard" (or "Level 5 Wizard" in the :long form screen readers get), or blank for a
    # character without a class (no sheet yet).
    def self.class_label(char, form = :short)
      return "" if !char
      charclass = (char.pf2_base_info || {})['charclass']
      return "" if charclass.blank?
      key = form == :long ? 'eaevents.class_label_long' : 'eaevents.class_label'
      t(key, :level => char.pf2_level, :charclass => charclass)
    end

    # The player count in words: "5 of 5, full, 2 on the waitlist", "3 of 6", or
    # "4 signed up, no limit".
    def self.screen_reader_players(event)
      count = event.signups.count
      limit = EaEvents.max_players(event)
      return t('eaevents.sr_players_no_limit', :count => count) if !limit

      waiting = EaEvents.waitlist(event).count
      if (waiting > 0)
        t('eaevents.sr_players_waitlist', :count => limit, :limit => limit, :waiting => waiting)
      elsif (count >= limit)
        t('eaevents.sr_players_full', :count => count, :limit => limit)
      else
        t('eaevents.sr_players_open', :count => count, :limit => limit)
      end
    end

    # "5/5 (Full) - 2 on the waitlist", "3/6", or "4 signed up" with no limit.
    def self.players_summary(event)
      count = event.signups.count
      limit = EaEvents.max_players(event)
      return t('eaevents.players_no_limit', :count => count) if !limit

      waiting = EaEvents.waitlist(event).count
      if (waiting > 0)
        t('eaevents.players_waitlist', :count => [count, limit].min, :limit => limit, :waiting => waiting)
      elsif (count >= limit)
        t('eaevents.players_full', :count => count, :limit => limit)
      else
        t('eaevents.players_open', :count => count, :limit => limit)
      end
    end

    # ---- The web portal -------------------------------------------------------------------------

    # Added to each sign-up the event page shows.
    def self.signup_web_fields(signup)
      char = signup.character
      {
        level: char ? char.pf2_level : nil,
        charclass: char ? ((char.pf2_base_info || {})['charclass'] || "") : "",
        class_label: EaEvents.class_label(char)
      }
    end

    # Added to the event page. `signups` is the list the stock handler built; it is put back in
    # this plugin's order (see ordered_signups) by character name, which is unique within an
    # event, and split at the limit into the roster and the waitlist. Each entry also gets its
    # place ("1.", or "W1" on the waitlist), since the portal has no arithmetic helper to number them.
    def self.event_web_fields(event, signups)
      limit = EaEvents.max_players(event)
      order = EaEvents.ordered_signups(event).map { |s| s.char_name }
      signups = signups.sort_by { |h| order.index(h[:char][:name]) || order.count }
      roster = limit ? signups.first(limit) : signups
      waitlist = limit ? signups.drop(limit) : []
      {
        max_players: limit,
        death_consent: !!event.death_consent,
        is_full: EaEvents.is_full?(event),
        players_summary: EaEvents.players_summary(event),
        roster_count: roster.count,
        roster: roster.each_with_index.map { |s, i| s.merge(position: "#{i + 1}.") },
        waitlist: waitlist.each_with_index.map { |s, i| s.merge(position: "W#{i + 1}") }
      }
    end

    # Added to each row of the events list.
    def self.event_list_web_fields(event, enactor)
      limit = EaEvents.max_players(event)
      waiting = EaEvents.waitlist(event).count
      {
        death_consent: !!event.death_consent,
        is_waitlisted: EaEvents.any_alt_waitlisted?(event, enactor),
        players: limit ? "#{[event.signups.count, limit].min} / #{limit}#{EaEvents.is_full?(event) ? ' · Full' : ''}" : t('eaevents.players_no_limit', :count => event.signups.count),
        players_note: !limit ? t('eaevents.no_limit') : (waiting > 0 ? t('eaevents.waiting_count', :waiting => waiting) : "")
      }
    end

    # Checks the portal's create and edit forms. Returns an error message, or nil.
    def self.check_web_fields(args)
      EaEvents.parse_limit(args['max_players'])[1]
    end

    # Saves the portal form's limit and flag. Run after check_web_fields passes.
    def self.save_web_fields(event, args)
      limit, error = EaEvents.parse_limit(args['max_players'])
      return if error

      EaEvents.set_max_players(event, limit) if limit != EaEvents.max_players(event)
      EaEvents.set_death_consent(event, "#{args['death_consent']}".downcase == "true")
    end

    # Blank or "none" is no limit. Returns [limit or nil, error or nil].
    def self.parse_limit(value)
      text = "#{value}".strip.downcase
      return [ nil, nil ] if text.blank? || text == "none"
      return [ text.to_i, nil ] if text =~ /\A\d+\z/ && text.to_i > 0
      [ nil, t('eaevents.invalid_limit') ]
    end
  end
end
