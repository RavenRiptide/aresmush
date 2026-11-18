module AresMUSH
  module Pf2e

    # Where a figure on the sheet came from.
    #
    # It opens with the sum written out - `+23 = 16 proficiency + 5 Dexterity + 2 item` - because the
    # question a player is usually asking is how much of a number is theirs and how much is their gear.
    # The rows under it say which item or effect each bonus came from.
    #
    # A modifier the stacking rule switched off is still shown, marked, because "you already have a
    # better item bonus" is the answer to the question a player is asking when they wonder why their
    # new ring changed nothing.
    #
    # A player with the screen reader setting gets the same content as sentences. Signs are words
    # there, because whether "+" and "-" are spoken depends on the reader's punctuation level, and a
    # penalty that is not spoken sounds like a bonus. Every row names its own type, since a blank
    # column that groups rows for the eye says nothing aloud.
    class PF2StatBreakdownTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      # Figures that are rolled, and so read as a modifier (`+12`). The rest - AC, a DC, hit points,
      # speed - are amounts, and print bare.
      SIGNED = %w{skill lore save perception attack spell_attack}.freeze

      # Figures whose base is a proficiency bonus and nothing else.
      PROFICIENT = %w{skill lore save perception attack spell_attack}.freeze

      # The order a type's rows are listed in, which is roughly how much of the figure is the
      # character's own.
      ORDER = %w{ability proficiency potency item status circumstance untyped}.freeze

      LABEL_WIDTH = 14
      WIDTH = 78

      def initialize(label, breakdown, kind = nil, client = nil)
        @label = label
        @breakdown = breakdown
        @kind = kind.to_s
        @client = client

        super File.dirname(__FILE__) + "/stat_breakdown.erb"
      end

      def screen_reader
        @client.respond_to?(:screen_reader) && @client.screen_reader
      end

      def title
        "#{@label} Breakdown"
      end

      # ------------------------------------------------------------------------------
      # The sum

      # `+23  =  16 proficiency  +  5 Dexterity  +  2 item`, wrapped under the `=` when it runs long.
      def equation
        terms = summed_terms.map { |value, word| "#{value.negative? ? '-' : '+'}  #{value.abs} #{word}" }
        lead = "  #{item_color}#{figure(@breakdown['total'])}%xn  =  "
        indent = ' ' * (strip(lead).length - 3)

        lines = [ lead + base_term ]

        terms.each do |term|
          if strip(lines.last).length + term.length + 5 > WIDTH - 2
            lines << "#{indent}#{term}"
          else
            lines[-1] = "#{lines.last}  #{term}"
          end
        end

        lines.join('%r')
      end

      # `Total plus 23: 16 proficiency, plus 5 Dexterity, plus 2 item.`
      def spoken_equation
        terms = summed_terms.map { |value, word| "#{spoken(value)} #{word}" }

        "Total #{spoken_figure(@breakdown['total'])}: #{([ base_term ] + terms).join(', ')}."
      end

      def base_term
        "#{@breakdown['base'].to_i} #{PROFICIENT.include?(@kind) ? 'proficiency' : 'base'}"
      end

      # [ value, word ] for each attribute by name, and each other type summed: only what counted.
      def summed_terms
        counted = @breakdown['modifiers'].select { |row| row['enabled'] && !row['value'].to_i.zero? }
        abilities, others = counted.partition { |row| type(row) == Modifiers::ABILITY }

        terms = abilities.map { |row| [ row['value'].to_i, row['source'].to_s ] }
        others.group_by { |row| type(row) }
              .sort_by { |kind, _| ORDER.index(kind) || ORDER.size }
              .each { |kind, group| terms << [ group.sum { |row| row['value'].to_i }, type_word(kind) ] }

        terms.reject { |value, _| value.zero? }
      end

      # ------------------------------------------------------------------------------
      # The rows

      # The base, then one row per modifier, grouped by type under the type's name.
      def rows
        shown = nil

        entries.map do |label, source, value, lost|
          text = [ source, value ? amount(value) : nil ].compact.join(' ')
          text = "#{text}  #{item_color}(not counted: #{lost})%xn" if lost
          heading = label == shown ? '' : label
          shown = label

          "  #{item_color}#{left(heading, LABEL_WIDTH)}%xn#{text}"
        end
      end

      # `Item: Clandestine Cloak, plus 1, not counted: Greater Shadow is better.`
      def spoken_rows
        entries.map do |label, source, value, lost|
          parts = [ spoken_text(source), value ? spoken(value) : nil, lost ? "not counted: #{lost}" : nil ].compact

          "#{label}: #{parts.join(', ')}."
        end
      end

      # [ label, source, value, why it was not counted ] for the base and each modifier. An attribute's
      # label is the attribute, so it has no source of its own; the base has no value, being the total's
      # starting point rather than something added to it.
      def entries
        found = []
        basis = @breakdown['basis']

        found << [ PROFICIENT.include?(@kind) ? 'Proficiency' : 'Base', initial(basis), nil, nil ] unless basis.to_s.empty?

        sorted = @breakdown['modifiers'].reject { |row| row['value'].to_i.zero? && row['enabled'] }
                                        .sort_by { |row| [ ORDER.index(type(row)) || ORDER.size, row['enabled'] ? 0 : 1 ] }

        sorted.each do |row|
          lost = row['enabled'] ? nil : why_not(row)

          found << if type(row) == Modifiers::ABILITY
                     [ row['source'].to_s, nil, row['value'], lost ]
                   else
                     [ type_name(row), initial(row['source']), row['value'], lost ]
                   end
        end

        found
      end

      # What a switched-off row lost to: the better bonus or worse penalty of its type that counts.
      def why_not(row)
        winner = @breakdown['modifiers'].find { |one| one['enabled'] && type(one) == type(row) }

        return 'a better one of its type applies' unless winner

        "#{winner['source']} is #{row['value'].to_i.negative? ? 'worse' : 'better'}"
      end

      # ------------------------------------------------------------------------------
      # What applies only sometimes

      # Bonuses that hold only while doing something in particular. Naming the circumstance is the point:
      # it is how a player learns that their Skeleton Key does nothing until they say they are picking a
      # lock.
      #
      #   Conditional bonuses/penalties
      #      Wary Disarmament: +2 circumstance bonus against traps or devices
      #      Supertaster: +2 circumstance bonus when you Recall Knowledge or Investigate (taste)
      #        (Roll command: roll cooking lore/recall knowledge/taste)
      #   Not applied
      #      Leather's armor check penalty (-1), because you meet its Strength requirement
      #
      # Each entry is one line however long, so a bonus is never split; the client wraps it if it must.
      # A penalty that is not counted is kept apart from the bonuses a player can claim, and says why, so
      # it does not read as something they have to do.
      ITEM_INDENT = 5
      HINT_INDENT = 7

      def conditional
        claimable, waived = shown_conditional.partition { |row| !waived?(row) }
        lines = []

        if claimable.any?
          lines << heading('Conditional bonuses/penalties')
          claimable.each do |row|
            lines << item("#{row['source']}: #{amount(row['value'])} #{bonus_words(row)}#{condition(row)}")
            lines << "#{' ' * HINT_INDENT}(Roll command: #{roll_hint(row)})" if roll_hint(row)
          end
        end

        if waived.any?
          lines << heading('Not applied')
          waived.each { |row| lines << item("#{possessive(row['source'])} #{penalty_name(row)} (#{amount(row['value'])})#{waiver(row)}") }
        end

        lines
      end

      def spoken_conditional
        claimable, waived = shown_conditional.partition { |row| !waived?(row) }
        lines = []

        if claimable.any?
          lines << 'Conditional bonuses and penalties:'
          claimable.each do |row|
            hint = roll_hint(row) ? " Roll command: #{roll_hint(row)}." : ''

            lines << "#{row['source']}: #{spoken(row['value'])} #{bonus_words(row)}#{condition(row)}.#{hint}"
          end
        end

        waived.each do |row|
          lines << "Not applied: #{possessive(row['source'])} #{penalty_name(row)}, #{spoken(row['value'])}#{waiver(row)}."
        end

        lines
      end

      def heading(text)
        "  #{item_color}#{text}%xn"
      end

      def item(text)
        "#{' ' * ITEM_INDENT}#{text}"
      end

      # `circumstance bonus`, `status penalty`.
      def bonus_words(row)
        "#{type_word(type(row))} #{row['value'].to_i.negative? ? 'penalty' : 'bonus'}"
      end

      # The conditional rows that can apply to this figure. A rule written against every skill check that
      # needs Recall Knowledge reaches Stealth too, but Stealth cannot be used to Recall Knowledge, so it
      # is left off Stealth's page. Where the actions config does not say which skill an action uses, the
      # row stays: better to show a bonus that might apply than hide one that does.
      def shown_conditional
        Array(@breakdown['conditional']).select { |row| waived?(row) || possible?(row) }
      end

      def possible?(row)
        known = parts(row['when'])['actions'].map { |slug| [ slug, action_statistics[slug] ] }
                                              .reject { |_slug, stats| stats.nil? }

        return true if known.empty?

        known.any? { |slug, stats| stats.include?(statistic) || (@kind == 'lore' && slug == 'recall-knowledge') }
      end

      # The figure as the actions config names a check's statistic: `stealth`, `reflex`, `perception`.
      def statistic
        Domains.slug(@label.to_s)
      end

      # action slug => the statistics its check may use, for every action in config that says.
      def action_statistics
        @action_statistics ||= (Global.read_config('pf2e_actions') || {}).each_with_object({}) do |(name, info), out|
          check = info.is_a?(Hash) ? info['check'] : nil
          stats = check.is_a?(Hash) ? Array(check['statistic']) : []

          out[Domains.slug(name)] = stats.map { |one| Domains.slug(one) } unless stats.empty?
        end
      end

      def waived?(row)
        row['slug'].to_s.start_with?('armor-') && row['value'].to_i.negative?
      end

      # Words a predicate uses that read better as a phrase of their own.
      PHRASES = { 'trap' => 'against traps or devices',
                  'attack' => 'against attacks',
                  'unarmed' => 'with unarmed attacks',
                  'area-effect' => 'against area effects',
                  'damaging-effect' => 'against damaging effects',
                  'scent' => 'using scent' }.freeze

      # Traits of what the check is against, or of the check itself: `fear` is a fear effect.
      TRAITS = %w{fear mental emotion visual auditory sonic magical spell illusion inhaled poison disease
                  curse affliction vitality void death linguistic olfactory}.freeze

      # Figures a player defends with, where a trait is the effect's rather than the check's.
      DEFENSES = %w{ac save}.freeze

      # ` when you Recall Knowledge or Investigate (taste)`, ` against fear effects`, or nothing at all
      # where the only requirement is the feat's own switch - Nimble Dodge's bonus is for when you use
      # Nimble Dodge, and its name says so.
      def condition(row)
        found = parts(row['when'])

        return ' in some circumstances' if found['unreadable']

        words = found['words'].reject { |word| own?(word, row) }
        phrased, plain = words.partition { |word| PHRASES[word] || TRAITS.include?(word) }
        said = phrased.map { |word| PHRASES[word] || trait_phrase(word) }

        said << "when you #{found['actions'].map { |slug| action_name(slug) }.join(' or ')}" if found['actions'].any?
        said << "(#{plain.map { |word| word.tr('-', ' ') }.join(', ')})" if plain.any?

        said.empty? ? '' : " #{said.join(' ')}"
      end

      def trait_phrase(word)
        DEFENSES.include?(@kind) ? "against #{word} effects" : "on #{word} checks"
      end

      # Whether a word is the source's own switch: `nimble-dodge` on Nimble Dodge.
      def own?(word, row)
        [ Domains.slug(row['source'].to_s), row['slug'].to_s ].include?(word)
      end

      # What a player types to count the bonus, as they would say it: the first action and any word it
      # also needs, with spaces for hyphens - `roll cooking lore/recall knowledge/taste`. The roll reads
      # each part after a slash as a circumstance, hyphenated or not.
      def roll_hint(row)
        found = parts(row['when'])

        return nil unless %w{skill lore perception}.include?(@kind)
        return nil if found['unreadable']

        typed = [ found['actions'].first ].compact + found['words'].reject { |word| own?(word, row) }

        return nil if typed.empty?

        "roll #{@label.downcase}/#{typed.map { |word| word.tr('-', ' ') }.join('/')}"
      end

      # A predicate taken apart into what a player can say: `actions` (`action:escape`, or an `or` of
      # actions), `words` a roll can name (`taste`, `visual`), and whether anything else is required that
      # a player cannot say - a fact about the target, say - in which case it is `unreadable`.
      def parts(statement)
        found = { 'actions' => [], 'words' => [], 'unreadable' => false }

        Array(statement).each do |one|
          if one.is_a?(String) && one.start_with?('action:')
            found['actions'] << one.delete_prefix('action:')
          elsif one.is_a?(String) && !one.include?(':')
            found['words'] << one
          elsif one.is_a?(Hash) && one.keys.map(&:to_s) == [ 'or' ] &&
                Array(one['or'] || one[:or]).all? { |each| each.is_a?(String) && each.start_with?('action:') }
            found['actions'] += Array(one['or'] || one[:or]).map { |each| each.delete_prefix('action:') }
          else
            found['unreadable'] = true
          end
        end

        found.merge('actions' => found['actions'].uniq)
      end

      WAIVED_BECAUSE = { 'strength' => ', because you meet its Strength requirement',
                         'flexible' => ', because the armor is flexible',
                         'ignored' => ', because a feat or ability ignores it' }.freeze

      def waiver(row)
        WAIVED_BECAUSE[row['waived_by']].to_s
      end

      def penalty_name(row)
        row['slug'].to_s == 'armor-speed-penalty' ? 'Speed penalty' : 'armor check penalty'
      end

      def possessive(name)
        name.to_s.end_with?('s') ? "#{name}'" : "#{name}'s"
      end

      # `pick-a-lock` as a player reads it: Pick a Lock.
      def action_name(slug)
        slug.split('-').each_with_index.map { |word, i|
          i.positive? && %w{a an the of to in on}.include?(word) ? word : word.capitalize
        }.join(' ')
      end

      # ------------------------------------------------------------------------------
      # Words and numbers

      def type(row)
        Modifiers.type_of(row)
      end

      def type_name(row)
        type_word(type(row)).capitalize
      end

      def type_word(kind)
        kind == Modifiers::UNTYPED ? 'other' : kind
      end

      def figure(value)
        signed_kind? ? signed(value) : value.to_i.to_s
      end

      def spoken_figure(value)
        signed_kind? ? spoken(value) : value.to_i.to_s
      end

      def signed_kind?
        SIGNED.include?(@kind) || @kind.empty?
      end

      # A penalty in red, so it stands out from the bonuses around it.
      def amount(value)
        value.to_i.negative? ? "%xr#{value.to_i}%xn" : signed(value)
      end

      def signed(value)
        value.to_i.negative? ? value.to_i.to_s : "+#{value.to_i}"
      end

      # `plus 2`, `minus 1`: a sign a screen reader says whatever its punctuation level.
      def spoken(value)
        "#{value.to_i.negative? ? 'minus' : 'plus'} #{value.to_i.abs}"
      end

      # A signed number inside some text said as words too: the AC base is `10, Leather +1, untrained`,
      # and an item may be named `Handwraps of Mighty Blows (+1)`.
      def spoken_text(text)
        text.nil? ? nil : text.to_s.gsub(/(?<![\w])([+-])(\d+)/) { "#{$1 == '-' ? 'minus' : 'plus'} #{$2}" }
      end

      # The first letter capitalised and the rest left alone, so `10, Leather +1` keeps its armour's name.
      def initial(text)
        text = text.to_s

        text.empty? ? text : text[0].upcase + text[1..]
      end

      # The text without its colour codes, for measuring it: `%xh` and `%xn`, and the 256-colour `%x229`.
      def strip(text)
        text.gsub(/%x(\d{1,3}|[a-z])/i, '')
      end
    end
  end
end
