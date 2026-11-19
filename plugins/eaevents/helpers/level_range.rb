module AresMUSH
  module EaEvents

    # ---- The level range ------------------------------------------------------------------------
    #
    # An event can name the levels its organizer is looking for, stored as min_level and max_level.
    # The range is informational: anyone can sign up, but a character outside it gets a note when
    # they do, the roster marks them, and a change to the range tells the sign-ups it leaves out.
    #
    # The range is always stored as levels. Tiers (game/config/eaevents.yml) are only how it is
    # typed and shown, so moving a tier boundary relabels events without touching them.

    # [{ name: "T1", min: 1, max: 4 }, ...] in config order.
    def self.level_tiers
      (Global.read_config("eaevents", "level_tiers") || []).map do |tier|
        { name: "#{tier['name']}", min: tier['min'].to_i, max: tier['max'].to_i }
      end
    end

    # The highest level a range can reach: the top of the highest tier.
    def self.level_cap
      EaEvents.level_tiers.map { |tier| tier[:max] }.max || 20
    end

    # [min, max], or nil when the event has no range.
    def self.level_range(event)
      min = event.min_level.to_i
      max = event.max_level.to_i
      min > 0 && max > 0 ? [ min, max ] : nil
    end

    # Reads "5-8", "7", "T2", "T2-T3", "any", or "none" (blank is none too). A reversed range is
    # put the right way round. Returns [[min, max] or nil, error or nil].
    def self.parse_level_range(value)
      text = "#{value}".downcase.gsub(/\s+/, "")
      return [ nil, nil ] if text.blank? || text == "none"
      return [ [ 1, EaEvents.level_cap ], nil ] if text == "any"

      parts = text.split("-", -1)
      bounds = parts.count <= 2 ? parts.map { |p| EaEvents.parse_level_bound(p) } : [ nil ]
      return [ nil, t('eaevents.invalid_level_range', :cap => EaEvents.level_cap) ] if bounds.include?(nil)

      [ [ bounds.map { |b| b[0] }.min, bounds.map { |b| b[1] }.max ], nil ]
    end

    # One end of a typed range: a level ("5" is [5, 5]) or a tier ("t2" is [5, 8]), or nil.
    def self.parse_level_bound(text)
      if (text =~ /\A\d+\z/)
        level = text.to_i
        return level >= 1 && level <= EaEvents.level_cap ? [ level, level ] : nil
      end
      tier = EaEvents.level_tiers.find { |candidate| candidate[:name].downcase == text }
      tier ? [ tier[:min], tier[:max] ] : nil
    end

    # The range in words, or "" for none. Forms:
    #   :full   - "T2 (Levels 5-8)", "T2-T3 (Levels 5-12)", "Any level (1-20)", "Levels 3-6"
    #   :short  - "T2", "T2-T3", "Any level", "Lv 3-6"
    #   :sr     - "T2, levels 5 to 8", "any level", "levels 3 to 6" (for screen readers)
    def self.level_range_label(range, form = :full)
      return "" if !range
      min, max = range
      cap = EaEvents.level_cap

      if (min == 1 && max == cap)
        return t("eaevents.level_any_#{form}", :cap => cap)
      end

      levels = min == max ? t("eaevents.level_one_#{form}", :level => min) :
        t("eaevents.level_span_#{form}", :min => min, :max => max)

      low = EaEvents.level_tiers.find { |tier| tier[:min] == min }
      high = EaEvents.level_tiers.find { |tier| tier[:max] == max }
      return levels if !low || !high

      tiers = low == high ? low[:name] : t("eaevents.tier_span_#{form}", :low => low[:name], :high => high[:name])
      form == :short ? tiers : t("eaevents.tiers_with_levels_#{form}", :tiers => tiers, :levels => levels)
    end

    def self.event_level_label(event, form = :full)
      EaEvents.level_range_label(EaEvents.level_range(event), form)
    end

    # The character's level, or nil for a character without a class (no sheet yet).
    def self.char_level(char)
      return nil if !char
      return nil if ((char.pf2_base_info || {})['charclass']).blank?
      level = char.pf2_level.to_i
      level > 0 ? level : nil
    end

    # :below or :above when the character is outside the event's range, otherwise nil (including
    # when the event has no range or the character has no level).
    def self.level_fit(event, char)
      range = EaEvents.level_range(event)
      level = EaEvents.char_level(char)
      return nil if !range || !level
      return :below if level < range[0]
      return :above if level > range[1]
      nil
    end

    # What a character outside the range is told when they sign up, or nil when they fit.
    def self.level_note(event, char)
      return nil if !EaEvents.level_fit(event, char)
      t('eaevents.level_signup_note', :title => event.title, :range => EaEvents.event_level_label(event),
        :name => char.name, :level => EaEvents.char_level(char), :organizer => event.organizer_name)
    end

    # Sets the range (nil for none). Sign-ups the change puts outside it get a notice; anyone who
    # was already outside it isn't told again. Returns the characters who were told.
    def self.set_level_range(event, range)
      already_out = event.signups.select { |s| EaEvents.level_fit(event, s.character) }.map { |s| s.id }
      event.update(min_level: range ? range[0] : 0, max_level: range ? range[1] : 0)

      newly_out = event.signups.to_a
        .select { |s| s.character && !already_out.include?(s.id) && EaEvents.level_fit(event, s.character) }
        .sort_by { |s| s.id.to_i }
        .map { |s| s.character }

      newly_out.each do |c|
        EaEvents.notify(c, event, t('eaevents.level_range_changed_notice', :title => event.title,
          :range => EaEvents.event_level_label(event), :name => c.name, :level => EaEvents.char_level(c),
          :organizer => event.organizer_name, :num => EaEvents.event_number(event)))
      end

      newly_out
    end
  end
end
