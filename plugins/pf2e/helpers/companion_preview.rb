module AresMUSH
  module Pf2e
    module Companion

      # What a level does to a companion, for advance/review and advance/done: the companion as committed
      # against the companion as drafted. A level that only raises its level shows nothing, because the Hit
      # Points and bonuses every level brings aren't news; a level that gives it, advances it or specializes
      # it shows what changed.
      module Preview

        ATTRIBUTES = { 'Strength' => 'Str', 'Dexterity' => 'Dex', 'Constitution' => 'Con', 'Intelligence' => 'Int',
                       'Wisdom' => 'Wis', 'Charisma' => 'Cha' }.freeze

        # The ranks worth saying, in the order said.
        RANKED = [ 'attack', 'unarmored', 'perception', 'Fortitude', 'Reflex', 'Will', 'Acrobatics', 'Athletics',
                   'Intimidation', 'Religion', 'Stealth', 'Survival' ].freeze

        # Whether a level changed the companion beyond its level.
        def self.changed?(before, after)
          return false unless after
          return true unless before

          shape = ->(one) { one.slice('type', 'size', 'mature', 'path', 'specializations', 'pending') }
          shape.call(before) != shape.call(after)
        end

        # The rows for the companion as the level leaves it, as advance/review lists them under "Options So
        # Far": [ label, value ] for each thing that changed, or [ label, [ [ label, value ], ... ] ] for a
        # group (saves, skills), giving only the new value. `before` and `after` are Companion.list entries
        # (before nil when the level gives it), and `then_stats` and `now_stats` their Stats.of results (nil
        # before a type is chosen). A nimble, savage or specialization choice still open shows nothing here:
        # it is listed with the level's other options. Hit Points rise every level, so they aren't listed,
        # as the character's own aren't.
        def self.lines(before, after, then_stats, now_stats)
          return [] unless changed?(before, after)

          return [ [ label('type'), gained_type(after, now_stats) ] ] if before.nil?
          return [] unless then_stats && now_stats

          rows = []
          if !Array(after['pending']).empty?
            # The stage waits on the choice.
          elsif Stats.stage_name(before) != now_stats['stage']
            rows << [ label('stage'), now_stats['stage'].to_s.capitalize ]
          end

          specializations(before, after).each { |one| rows << [ label('specialization'), one ] }
          rows << [ label('size'), now_stats['size'] ] if then_stats['size'] != now_stats['size']
          rows.concat(attributes(then_stats, now_stats))
          rows.concat(ranks(then_stats, now_stats))
          rows.concat(attacks(then_stats, now_stats))
          if now_stats['maneuver'] && !then_stats['maneuver']
            rows << [ label('maneuver'), now_stats['maneuver']['name'] ]
          end
          rows
        end

        # "Wolf (Young)", or "Not chosen yet" until its type is chosen.
        def self.gained_type(after, now_stats)
          return t('pf2e.companion_type_unchosen') unless after['type'] && now_stats

          "#{after['type']} (#{now_stats['stage'].to_s.capitalize})"
        end

        # A companion label in title case, as Options So Far's headings are: "Advanced Maneuver".
        def self.label(key)
          title(t("pf2e.companion_label_#{key}"))
        end

        def self.title(text)
          text.to_s.split.map { |word| word =~ /\A\d/ ? word : word.capitalize }.join(' ')
        end

        # The specializations the level adds: "Racer (Land)".
        def self.specializations(before, after)
          had = Array((before || {})['specializations']).map { |one| one['name'] }

          Array(after['specializations']).reject { |one| had.include?(one['name']) }.map do |one|
            one['choice'] ? "#{one['name']} (#{title(one['choice'])})" : one['name']
          end
        end

        def self.attributes(then_stats, now_stats)
          moved = ATTRIBUTES.filter_map do |name, short|
            from = then_stats['attributes'][name]
            to = now_stats['attributes'][name]
            from == to ? nil : "#{short} #{Companion.signed(to)}"
          end

          moved.empty? ? [] : [ [ label('attributes'), moved.join(', ') ] ]
        end

        SAVES = [ 'Fortitude', 'Reflex', 'Will' ].freeze

        # Attack, defense and Perception ranks on rows of their own, then saves and skills in groups.
        def self.ranks(then_stats, now_stats)
          raised = RANKED.reject { |key| (then_stats['ranks'][key] || 'untrained') == (now_stats['ranks'][key] || 'untrained') }
          rank = ->(key) { now_stats['ranks'][key].to_s.capitalize }

          own, grouped = raised.partition { |key| key[0] =~ /[a-z]/ }
          saves, skills = grouped.partition { |key| SAVES.include?(key) }

          rows = own.map { |key| [ label("rank_#{key}"), rank.call(key) ] }
          rows << [ t('pf2e.companion_sheet_section_saves'), saves.map { |key| [ key, rank.call(key) ] } ] unless saves.empty?
          rows << [ t('pf2e.companion_sheet_section_skills'), skills.map { |key| [ key, rank.call(key) ] } ] unless skills.empty?
          rows
        end

        def self.attacks(then_stats, now_stats)
          now_stats['attacks'].filter_map do |attack|
            was = then_stats['attacks'].find { |one| one['name'] == attack['name'] }
            next nil unless was

            from = Companion.damage(was)
            to = Companion.damage(attack)
            magical = attack['traits'].include?('magical') && !was['traits'].include?('magical')
            next nil if from == to && !magical

            [ attack['name'], "#{title(to)}#{magical ? t('pf2e.companion_level_magical') : ''}" ]
          end
        end

        # What advance/review shows for a character mid-level: { 'heading', 'rows', 'notes' }, or nil when
        # the level leaves their companion as it was. The rows go under "Options So Far"; the notes, which
        # don't hold up the level, go with its messages.
        def self.for(char)
          after = Companion.list(char).first
          before = Companion.list(char, :draft => false).first
          return nil unless changed?(before, after)

          then_stats = Companion.stats(char, before, :draft => false)
          now_stats = Companion.stats(char, after)
          name = Companion.name_of(char, after)
          heading = name ? t('pf2e.companion_level_heading_named', :name => name) : t('pf2e.companion_level_heading')

          notes = Gear.coming_off_at_level(char).map do |item|
            t('pf2e.companion_level_comes_off', :subject => name || t('pf2e.companion_subject_unnamed'), :item => item)
          end
          notes << t('pf2e.companion_level_unnamed') unless name

          { 'heading' => heading, 'rows' => lines(before, after, then_stats, now_stats), 'notes' => notes }
        end

        # What advance/done says once the level is in, worked out before it commits: nil when nothing changed.
        def self.closing_line(char)
          after = Companion.list(char).first
          before = Companion.list(char, :draft => false).first
          return nil unless changed?(before, after) && after['type']

          now = Companion.stats(char, after)
          return t('pf2e.companion_done_gained', :type => after['type'].downcase) unless before

          subject = Companion.subject(char, after)
          added = specializations(before, after)
          unless added.empty?
            return t('pf2e.companion_done_specialization', :subject => subject, :specialization => added.first)
          end

          t('pf2e.companion_done_stage', :subject => subject, :stage => now['stage'])
        end
      end
    end
  end
end
