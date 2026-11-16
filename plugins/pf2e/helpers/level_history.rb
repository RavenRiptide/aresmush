module AresMUSH
  module Pf2e

    # A character's build, level by level, read from the grant ledger: what `sheet/history`,
    # `sheet/feats` and `sheet/features` show.
    #
    # Pure: it takes ledger rows (plain hashes) and the character's level, and returns plain data.
    # The template colors and lays it out.
    #
    # A row's level is the level it took effect at. Two kinds of row don't have a real one:
    #
    # - a grant with no level (a formula bought, a spell learned from a scroll, a staff correction)
    #   applies at every level, and is grouped as :global
    # - a character made before the ledger was seeded as one transaction stamped level 1, because the
    #   old stores couldn't say which level gave what. Those rows are grouped as :before rather than
    #   presented as level 1 picks.
    module LevelHistory

      # The bucket a feat is filed in, as the word a player knows its slot by.
      FEAT_TYPES = {
        'charclass' => 'class',
        'ancestry' => 'ancestry',
        'dedication' => 'archetype',
        'skill' => 'skill',
        'general' => 'general'
      }.freeze

      # What a history shows, one row per grant kind. A kind not listed here is left out: class
      # features, proficiencies, traits and focus spells follow from the class table and from feats,
      # not from anything the player chose.
      #
      #   order    - where its line sits within a level
      #   category - the singular label for its line; the plural adds an s
      #   item     - how one grant reads on that line
      #   latest   - only the latest grant per key counts within a level (a rank, a score)
      KINDS = {
        'grant_feat' => {
          'order' => lambda { |p| 1 + FEAT_TYPES.keys.index(bucket(p)).to_i },
          'category' => lambda { |p| "#{feat_type(p).capitalize} feat" },
          'item' => lambda { |p| p['feat'].to_s }
        },
        'make_choice' => {
          'order' => lambda { |_p| 10 },
          'category' => lambda { |_p| 'Choice' },
          'item' => lambda { |p| "#{p['choice']}: #{p['label']}" }
        },
        'boost_ability' => {
          'order' => lambda { |_p| 11 },
          'category' => lambda { |_p| 'Attribute boost' },
          'item' => lambda { |p| p['ability'].to_s },
          'count' => 'boosts'
        },
        'flaw_ability' => {
          'order' => lambda { |_p| 12 },
          'category' => lambda { |_p| 'Attribute flaw' },
          'item' => lambda { |p| p['ability'].to_s }
        },
        'set_ability_score' => {
          'order' => lambda { |_p| 13 },
          'category' => lambda { |_p| 'Attribute score' },
          'item' => lambda { |p| "#{p['ability']} #{p['to']}" },
          'latest' => 'ability'
        },
        'raise_skill' => {
          'order' => lambda { |_p| 14 },
          'category' => lambda { |_p| 'Skill' },
          'item' => lambda { |p| "#{p['skill']} (#{p['to']})" },
          'latest' => 'skill'
        },
        'add_lore' => {
          'order' => lambda { |_p| 15 },
          'category' => lambda { |_p| 'Lore' },
          'item' => lambda { |p| "#{p['lore']} (#{p['to']})" },
          'latest' => 'lore'
        },
        'add_language' => {
          'order' => lambda { |_p| 16 },
          'category' => lambda { |_p| 'Language' },
          'item' => lambda { |p| p['language'].to_s }
        },
        'spell_access' => {
          'order' => lambda { |_p| 17 },
          'category' => lambda { |_p| 'Spell' },
          'item' => lambda { |p| p['rank'].to_i.zero? ? "#{p['spell']} (cantrip)" : "#{p['spell']} (rank #{p['rank']})" }
        },
        'spell_unlock' => {
          'order' => lambda { |_p| 18 },
          'category' => lambda { |_p| 'Unlocked spell' },
          'item' => lambda { |p| p['spell'].to_s }
        },
        'grant_formula' => {
          'order' => lambda { |_p| 19 },
          'category' => lambda { |_p| 'Formula' },
          'item' => lambda { |p| p['formula'].to_s }
        }
      }.freeze

      # A grant that came from somewhere other than building the character says where. Level-ups,
      # chargen and imports say nothing: the level heading already places them.
      SOURCE_WORDS = {
        'bought' => 'bought',
        'learned' => 'learned',
        'staff' => 'staff',
        'boon' => 'boon',
        'feat' => 'from a feat'
      }.freeze

      # The sources a character was built from before the ledger knew them level by level.
      CREATION_SOURCES = %w(chargen imported).freeze

      def self.bucket(payload)
        (payload['bucket'] || 'charclass').to_s
      end

      def self.feat_type(payload)
        FEAT_TYPES[bucket(payload)] || bucket(payload)
      end

      # Whether the rows stamped level 1 really were taken at level 1. They were for a character made
      # through chargen since the ledger: their first level-up is level 2, or they have none and are
      # still level 1. A character made earlier was seeded at level 1 whatever level they were.
      def self.trusted_creation?(live, level)
        ups = live.select { |row| row['source_type'] == 'level_up' && !Ledger.global?(row) }
                  .map { |row| row['effective_level'].to_i }

        ups.empty? ? level.to_i <= 1 : ups.min == 2
      end

      # :before, :global, or the level the row took effect at.
      def self.group_for(row, trusted)
        return :global if Ledger.global?(row)

        at = row['effective_level'].to_i
        return :before if !trusted && at <= 1 && CREATION_SOURCES.include?(row['source_type'])

        at
      end

      # One hash per grant the history shows, oldest first. `kinds` narrows it - `sheet/feats` wants
      # only feats - and `extra` adds kinds the history leaves out, as `sheet/features` does.
      def self.entries(rows, level, kinds: nil, extra: {})
        specs = KINDS.merge(extra)
        specs = specs.slice(*kinds) if kinds

        live = Ledger.applicable(Array(rows), level)
        trusted = trusted_creation?(live, level)

        live.filter_map do |row|
          spec = specs[row['kind']]
          next unless spec

          payload = row['payload'] || {}
          source = SOURCE_WORDS[row['source_type'].to_s]

          {
            'group' => group_for(row, trusted),
            'kind' => row['kind'],
            'order' => spec['order'].call(payload),
            'category' => spec['category'].call(payload),
            'item' => spec['item'].call(payload),
            'source' => source,
            'key' => spec['latest'] && payload[spec['latest']].to_s.downcase,
            'count' => spec['count'],
            'payload' => payload
          }
        end
      end

      # Feature rows, for `sheet/features`. Not in KINDS, because the history leaves them out.
      FEATURE_KIND = {
        'grant_feature' => {
          'order' => lambda { |_p| 0 },
          'category' => lambda { |_p| 'Feature' },
          'item' => lambda { |p| p['feature'].to_s }
        }
      }.freeze

      # The groups in reading order: anything from before level tracking, then each level, then what
      # is tied to no level. A range keeps only the levels in it.
      def self.ordered_groups(entries, range: nil)
        grouped = entries.group_by { |e| e['group'] }

        keys = grouped.keys.select { |k| k.is_a?(Integer) }.sort
        keys = keys.select { |k| range.cover?(k) } if range
        keys = [ :before ] + keys + [ :global ] unless range

        keys.select { |k| grouped[k] }.map { |k| [ k, grouped[k] ] }
      end

      # The history: [ [ group, [ [ label, [ item, ... ] ], ... ] ], ... ]. A feat's choice is named
      # beside the feat rather than again as a choice of its own.
      def self.groups(rows, level, range: nil)
        ordered_groups(entries(rows, level), range: range).map do |group, held|
          held = latest_only(held)
          feats, rest = held.partition { |e| e['kind'] == 'grant_feat' }
          choices = rest.select { |e| e['kind'] == 'make_choice' }

          named = name_choices(feats, choices)
          rest -= named[:used]

          lines = (named[:feats] + rest).group_by { |e| [ e['order'], e['category'] ] }
                                        .sort_by { |(order, _category), _| order }
                                        .map { |(_order, category), list| line(category, list) }

          [ group, lines ]
        end
      end

      # `sheet/feats`: [ [ group, [ "Battle Medicine (skill feat)", ... ] ], ... ].
      def self.feats_by_level(rows, level)
        all = entries(rows, level, :kinds => %w(grant_feat make_choice))

        ordered_groups(all).map do |group, held|
          choices = held.select { |e| e['kind'] == 'make_choice' }
          feats = name_choices(held.select { |e| e['kind'] == 'grant_feat' }, choices)[:feats]

          [ group, feats.map { |e| with_source("#{e['item']} (#{feat_type(e['payload'])} feat)", e) } ]
        end
      end

      # `sheet/features`: [ [ group, [ "Divine Access", ... ] ], ... ]. A feature held both bare and
      # as a specialty's version of it ("Fifth Doctrine" and "Fifth Doctrine (Cloistered)") is named
      # once, as the specialty's.
      def self.features_by_level(rows, level)
        all = entries(rows, level, :kinds => %w(grant_feature), :extra => FEATURE_KIND)
        names = all.map { |e| e['item'] }

        kept = all.reject { |e| names.any? { |other| other.start_with?("#{e['item']} (") } }

        ordered_groups(kept).map { |group, held| [ group, held.map { |e| with_source(e['item'], e) }.uniq ] }
      end

      # Within a level, a rank or score granted twice counts once: the later one.
      def self.latest_only(held)
        keyed = held.select { |e| e['key'] }
        last = keyed.group_by { |e| [ e['kind'], e['key'] ] }.transform_values(&:last).values

        held.reject { |e| e['key'] } + last
      end

      # Puts each feat's choice beside it - Assurance (Medicine) - using the choices made at the
      # same level under the feat's name. Returns the feats with their items rewritten, and the
      # choices used up.
      def self.name_choices(feats, choices)
        pool = choices.group_by { |c| c['payload']['choice'].to_s.downcase }
        used = []

        named = feats.map do |feat|
          picked = (pool[feat['item'].downcase] || []).shift
          next feat unless picked

          used << picked
          feat.merge('item' => "#{feat['item']} (#{picked['payload']['label']})")
        end

        { :feats => named, :used => used }
      end

      def self.line(category, list)
        items = list.group_by { |e| [ e['item'], e['source'] ] }.map do |(_item, _source), same|
          shown = with_source(same.first['item'], same.first)
          next shown if same.size == 1

          same.first['count'] ? "#{shown} (#{same.size} #{same.first['count']})" : "#{shown} (#{same.size} times)"
        end

        label = list.size == 1 ? category : "#{category}s"

        [ label, items ]
      end

      def self.with_source(text, entry)
        entry['source'] ? "#{text} (#{entry['source']})" : text
      end

      # A level range a player typed: "5" or "3-7". Nil if it isn't one.
      def self.parse_range(text)
        found = text.to_s.strip.match(/\A(\d+)\s*(?:-\s*(\d+))?\z/)
        return nil unless found

        from = found[1].to_i
        to = (found[2] || found[1]).to_i
        return nil if from < 1 || to < from

        from..to
      end
    end
  end
end
