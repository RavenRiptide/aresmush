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
      def conditional
        Array(@breakdown['conditional']).map do |row|
          case conditional_kind(row)
          when :waived
            "  #{item_color}Waived:%xn #{row['source']} #{amount(row['value'])} armor penalty"
          when :vague
            "  #{item_color}In some circumstances:%xn #{conditional_what(row) { |v| amount(v) }}"
          else
            hint = roll_hint(row) ? "   (#{roll_hint(row)})" : ''

            "  #{item_color}Also, when you #{action_names(row)}:%xn  #{conditional_what(row) { |v| amount(v) }}#{hint}"
          end
        end
      end

      def spoken_conditional
        Array(@breakdown['conditional']).map do |row|
          case conditional_kind(row)
          when :waived
            "Waived: #{row['source']} armor penalty, #{spoken(row['value'])}."
          when :vague
            "In some circumstances: #{conditional_what(row, ', ') { |v| spoken(v) }}."
          else
            hint = roll_hint(row) ? " To use it, #{roll_hint(row)}." : ''

            "Also, when you #{action_names(row)}: #{conditional_what(row, ', ') { |v| spoken(v) }}.#{hint}"
          end
        end
      end

      def conditional_kind(row)
        return :waived if row['slug'].to_s.start_with?('armor-') && row['value'].to_i.negative?

        actions_in(row['when']).empty? ? :vague : :action
      end

      # `Slick +1 item`, or `Slick, plus 1 item` aloud.
      def conditional_what(row, joiner = ' ')
        "#{row['source']}#{joiner}#{yield(row['value'])} #{type_word(type(row))}"
      end

      def roll_hint(row)
        return nil unless %w{skill lore}.include?(@kind)

        "roll #{@label.downcase}/#{actions_in(row['when']).first}"
      end

      def action_names(row)
        actions_in(row['when']).map { |slug| action_name(slug) }.join(' or ')
      end

      # The actions a circumstance names, as their slugs: `action:pick-a-lock` is `pick-a-lock`, and an
      # `or` of actions is each of them. Anything else is not an action, and is described more vaguely.
      def actions_in(statement)
        Array(statement).flat_map do |one|
          case one
          when String then one.start_with?('action:') ? [ one.delete_prefix('action:') ] : []
          when Hash then one.keys.map(&:to_s) == [ 'or' ] ? actions_in(one['or'] || one[:or]) : []
          else []
          end
        end.uniq
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

      # The text without its colour codes, for measuring it.
      def strip(text)
        text.gsub(/%x./i, '')
      end
    end
  end
end
