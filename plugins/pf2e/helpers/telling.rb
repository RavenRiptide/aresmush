module AresMUSH
  module Pf2e

    # What the engine tells, rendered.
    #
    # The engine answers what happened as events - a locale key and its arguments, as `Turns.event` does
    # - and leaves the wording to whoever tells it: the room gets MUSH text, the portal plain text, and a
    # spec can assert on the event itself. An argument may be a value this renders rather than a word:
    #
    #   an event        rendered in its place: ` until the end of Aria's next turn`
    #   a roll          `23 (15 +8)`, `23 (fortune: 15, 7 +8)`, `18 (Assurance 10 +8)`
    #   a degree        a coloured word: a critical hit, a failure
    #   a list          its items rendered and joined
    module Telling

      def self.event(key, args = {})
        { 'key' => key, 'args' => args.each_with_object({}) { |(name, held), out| out[name.to_s] = held } }
      end

      def self.roll(result)
        { 'roll' => result.slice('total', 'die', 'dice', 'kept', 'modifier', 'substitution') }
      end

      def self.degree(degree, attack = false)
        { 'degree' => degree, 'attack' => attack }
      end

      def self.render(event)
        args = (event['args'] || {}).each_with_object({}) { |(name, held), out| out[name.to_sym] = value(held) }

        t(event['key'], **args)
      end

      def self.lines(events)
        Array(events).map { |event| value(event) }
      end

      def self.value(held)
        case held
        when Array then held.map { |one| value(one) }.join(', ')
        when Hash
          return render(held) if held.key?('key') && held.key?('args')
          return degree_word(held['degree'], held['attack']) if held.key?('degree')
          return rolled(held['roll']) if held.key?('roll')

          held.to_s
        when nil then ''
        else held.to_s
        end
      end

      DEGREE_COLORS = [ '%xr', '%xy', '%xg', '%xh%xm' ].freeze
      HIT_WORDS = [ 'critical miss', 'miss', 'hit', 'critical hit' ].freeze

      def self.degree_word(degree, attack)
        return '' unless degree

        "#{DEGREE_COLORS[degree]}#{(attack ? HIT_WORDS : Resolve::WORDS)[degree]}%xn"
      end

      def self.rolled(result)
        modifier = result['modifier'].to_i
        sign = modifier.negative? ? '' : '+'

        face = if result['substitution']
                 "#{result['substitution']['label'] || result['substitution']['slug']} #{result['total'] - modifier}"
               elsif result['kept']
                 "#{result['kept'] == 'keep-higher' ? 'fortune' : 'misfortune'}: #{Array(result['dice']).join(', ')}"
               else
                 result['die'].to_s
               end

        "#{result['total']} (#{face} #{sign}#{modifier})"
      end
    end
  end
end
