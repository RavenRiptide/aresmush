module AresMUSH
  module Pf2e

    # The formula language Foundry's pf2e system writes its effects in, read rather than reinvented.
    #
    # An effect says what it is worth as an expression: `@actor.level` for Toughness's hit points,
    # `ternary(gte(@actor.level,17),3,2)` for a rank that improves at 17th. We adopt the grammar so a
    # converted feat carries its formula across as data. Inventing our own shape would mean
    # hand-translating the two thousand formulas their data ships, and a wrong sign or a dropped floor
    # is a number that looks right and is not.
    #
    # Dentaku does the tokenising, the precedence and the tree. It is already a dependency - the `math`
    # command uses it - so what is left to us is only what Dentaku cannot know about:
    #
    #   * `@actor.level` and `{item|flags…}` are Foundry's reference syntax rather than arithmetic.
    #     They are rewritten to plain identifiers before Dentaku sees them, and resolved against a
    #     flattened context.
    #   * `ternary`, `gte`, `floor` and the rest are Foundry's names for things Dentaku spells
    #     differently or not at all, so they are registered as functions.
    #
    # Nothing here evaluates Ruby: Dentaku parses arithmetic over a fixed function set, so an
    # expression cannot reach the host, and a function we have not registered is refused rather than
    # guessed at.
    #
    # `formula_specs.rb` holds this against every formula in Foundry's shipped packs, from a corpus in
    # `specs/support/`. That corpus is the guard against having read the grammar wrongly: a construct
    # we misunderstand fails there, loudly, instead of quietly resolving to zero in front of a player.
    module Formula

      class Invalid < StandardError; end

      # A hyphen is subtraction to any arithmetic parser, and Foundry has path segments holding one -
      # `…attacks.advanced-firearms-crossbows.rank`. Both the formula and the context keys are
      # rewritten so a hyphen inside a path never reaches the parser.
      HYPHEN = '__h__'.freeze

      REFERENCE = /@(?:[A-Za-z0-9_\-]+|\{[^}]*\})(?:\.(?:[A-Za-z0-9_\-]+|\{[^}]*\}))*/
      INTERPOLATION = /\{[^}]*\}/

      # Foundry's function names, onto Ruby. Comparisons answer 1 and 0 because `ternary` takes its
      # test as a number. `clamped` is a misspelling of clamp appearing once in the shipped data;
      # accepting it costs nothing, and refusing it would fail an import over someone else's slip.
      FUNCTIONS = {
        :floor => [ :numeric, ->(value) { value.floor } ],
        :ceil => [ :numeric, ->(value) { value.ceil } ],
        :round => [ :numeric, ->(value) { value.round } ],
        :abs => [ :numeric, ->(value) { value.abs } ],
        :sign => [ :numeric, ->(value) { value <=> 0 } ],
        :gte => [ :numeric, ->(left, right) { left >= right ? 1 : 0 } ],
        :gt => [ :numeric, ->(left, right) { left > right ? 1 : 0 } ],
        :lte => [ :numeric, ->(left, right) { left <= right ? 1 : 0 } ],
        :lt => [ :numeric, ->(left, right) { left < right ? 1 : 0 } ],
        :eq => [ :numeric, ->(left, right) { left == right ? 1 : 0 } ],
        :ne => [ :numeric, ->(left, right) { left == right ? 0 : 1 } ],
        :ternary => [ :numeric, ->(test, yes, no) { test.zero? ? no : yes } ],
        :clamp => [ :numeric, ->(value, low, high) { value.clamp(low, high) } ],
        :clamped => [ :numeric, ->(value, low, high) { value.clamp(low, high) } ]
      }.freeze

      def self.value(formula, context = {})
        evaluate(formula, context).first
      end

      # The paths the formula asked for that the context did not hold. A reference resolving to nothing
      # counts as zero, which is what Foundry does - and is also how a mistyped path hides, so a caller
      # that wants to know can ask.
      def self.unresolved(formula, context = {})
        evaluate(formula, context).last
      end

      # Whether Dentaku can read it at all, without needing a context to resolve against.
      def self.parses?(formula)
        text, _missing, named = prepare(formula.to_s, {})
        ast = calculator.ast(text)
        strays = ast.dependencies.map { |name| name.to_s.downcase } - named

        strays.empty?
      rescue StandardError
        false
      end

      def self.evaluate(formula, context)
        flat = flatten(context)
        text, missing, named = prepare(formula.to_s, flat)
        bound = flat.each_with_object({}) { |(key, held), out| out[safe(key)] = held if held.is_a?(Numeric) }

        [ compute(text, bound, missing, named), missing.uniq ]
      end

      # ------------------------------------------------------------------------------

      # `named` is the set of identifiers this formula reached by way of a reference. Every other
      # identifier is a formula that does not say what it means: Foundry marks a reference with `@` or
      # an interpolation, always, so a bare word is malformed rather than merely unresolved. That
      # distinction is what keeps a nonsense formula loud - Dentaku reads `` `ls` `` as an identifier,
      # and binding it to zero would have swallowed it.
      def self.compute(text, bound, missing, named)
        normalise(calculator.evaluate!(text, bound))
      rescue ZeroDivisionError
        # Only a reference that resolved to nothing divides by zero here - no shipped formula divides
        # by a literal. `unresolved` already names it, and raising would take a whole sheet render down
        # over one bad path.
        0
      rescue Dentaku::UnboundVariableError => problem
        # An unknown identifier is a path the context did not hold. Bind it to zero and carry on, so
        # one bad path costs one term rather than the whole formula.
        names = Array(problem.unbound_variables).map { |name| name.to_s.downcase }
        stray = names.reject { |name| named.include?(name) }

        raise Invalid, "#{text.inspect} names #{stray.join(', ')}, which is not a reference" if stray.any?

        names.each { |name| missing << name.gsub(HYPHEN, '-') }

        compute(text, bound.merge(names.each_with_object({}) { |name, out| out[name] = 0 }), missing, named)
      rescue Invalid
        raise
      rescue StandardError => problem
        raise Invalid, "#{problem.class}: #{problem.message} in #{text.inspect}"
      end

      # Whole answers stay whole, so `18 + @actor.level` reads as an integer on a sheet and Dentaku's
      # BigDecimal does not leak out.
      def self.normalise(result)
        raise Invalid, "not a number: #{result.inspect}" unless result.is_a?(Numeric)

        whole = result.to_i

        whole == result ? whole : result.to_f
      end

      # Rewrites Foundry's reference syntax into identifiers Dentaku can read, resolving any
      # interpolation on the way: `@actor.skills.{item|…}.rank` resolves in two stages, the inner value
      # becoming a segment of the outer path.
      def self.prepare(formula, flat)
        missing = []
        named = []

        # References first, because an interpolation inside one is a path segment rather than a value
        # of its own. Whatever braces are left stand alone, and in a value field those name a path the
        # same way a reference does.
        text = formula.gsub(REFERENCE) do |reference|
          identifier = safe(reference[1..].gsub(INTERPOLATION) { |brace| interpolate(brace, flat, missing) })
          named << identifier

          identifier
        end

        text = text.gsub(INTERPOLATION) do |brace|
          source, _, inner = brace[1..-2].partition('|')
          identifier = safe("#{source}.#{inner}")
          named << identifier

          identifier
        end

        [ text, missing, named ]
      end

      def self.interpolate(brace, flat, missing)
        source, _, inner = brace[1..-2].partition('|')
        key = "#{source}.#{inner}"
        held = flat[key]

        return held.to_s unless held.nil?

        missing << key

        ''
      end

      # Dentaku folds identifier case, so a path is folded once here and every comparison and binding
      # against it is folded the same way. `sneakAttackDamage` and `sneakattackdamage` are one path.
      def self.safe(path)
        path.gsub('-', HYPHEN).downcase
      end

      # A nested context to the dotted keys a formula names: { 'actor' => { 'level' => 5 } } becomes
      # { 'actor.level' => 5 }.
      def self.flatten(context, prefix = nil, out = {})
        (context || {}).each_pair do |key, held|
          path = [ prefix, key ].compact.join('.')

          if held.is_a?(Hash)
            flatten(held, path, out)
          else
            out[path] = held
          end
        end

        out
      end

      def self.calculator
        @calculator ||= Dentaku::Calculator.new.tap do |calc|
          FUNCTIONS.each_pair { |name, (type, body)| calc.add_function(name, type, body) }
        end
      end
    end
  end
end
