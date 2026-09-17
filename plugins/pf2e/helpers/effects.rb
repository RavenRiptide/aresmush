module AresMUSH
  module Pf2e

    # How a feat, an item or a condition says that it changes a number.
    #
    # `grants:` already lets a feat declare what it gives you - a further feat, a training slot, a
    # proficiency. `modifies:` is the same idea for the figures on the sheet: the thing that has the
    # effect carries the effect, so nothing in the engine has to know that Toughness exists.
    #
    #   modifies:
    #     - domain: hp                     # or a list of them
    #       type: untyped                  # which stacking rule it obeys
    #       value: "@actor.level"          # a number, or Foundry's formula language
    #       when: [ action:pick-a-lock ]   # optional: only in these circumstances
    #
    # `domain` is a `Pf2e::Domains` selector, so a row reaches every statistic in a group rather than
    # naming statistics one at a time. `value` is read by `Pf2e::Formula` and `when` by
    # `Pf2e::Predicate`, so a row lifted out of Foundry's data keeps both verbatim.
    #
    # An item may also declare circumstances of its own, with `grants_options:`. A Clandestine Cloak
    # predicates its bonuses on `clandestine-cloak` and declares that option itself, so wearing the
    # cloak is enough - a player has nothing to say. What stays conditional is what depends on the
    # player: the action they are taking, or a fact about the check.
    #
    # A row whose `when` is unmet is reported rather than dropped: `Pf2e::Stat` lists it as conditional,
    # because "you have a +2 here but only while picking a lock" is the answer a player wants. It is
    # kept out of the stacking, so an unmet row cannot override a met one.
    #
    # Two roots are available to a formula here. `@actor` is the character - level and attribute
    # modifiers, the facts that cannot themselves be modified without circularity. `@source` is the
    # thing carrying the row: `@source.value` is a condition's value, which is how Frightened 3 is the
    # same row as Frightened 1.
    module Effects

      KEYS = %w{domain type value when}.freeze

      # Spelled out rather than taken from `Modifiers`, which the plugin loader may not have reached
      # yet when this file is read.
      DEFAULT_TYPE = 'untyped'.freeze

      # Every modifier from these sources that reaches a statistic with these domains.
      #
      # A source is a hash of a name, the rows it carries, and whatever `@source` should resolve to -
      # `Effects.sources` builds them from the character, and a spec builds them from literals.
      def self.modifiers(sources, domains, context = {}, options = [])
        Array(sources).flat_map { |source| rows_of(source, domains, context, options) }
      end

      def self.rows_of(source, domains, context, options)
        name = source['name']
        held = Array(options) + Array(source['options'])

        Array(source['modifies']).each_with_object([]) do |row, out|
          complain(name, row)

          next unless Domains.matches?(row['domain'], domains)

          out << { 'source' => name,
                   'type' => (row['type'] || DEFAULT_TYPE).to_s.downcase,
                   'value' => Formula.value(row['value'], context.merge('source' => source['source'] || {})),
                   'when' => row['when'],
                   'met' => Predicate.test(row['when'], held) }
        end
      end

      # A key nobody reads is a rule that silently does nothing, which is the failure this vocabulary
      # exists to avoid - so an unknown one says so rather than being skipped in silence.
      def self.complain(name, row)
        strays = row.keys.map(&:to_s) - KEYS

        return if strays.empty?

        Global.logger.warn "PF2e modifies row on #{name.inspect} has keys nothing reads: #{strays.join(', ')}."
      end

      # ------------------------------------------------------------------------------

      # Everything the character carries that could modify a figure.
      def self.sources(char)
        SheetReads.memo(char, :effect_sources) { conditions(char) + feats(char) + items(char) }
      end

      # What is true about the character, as the options a predicate is tested against. Foundry's own
      # spelling, so a predicate lifted from their data reads the same facts.
      def self.options(char)
        SheetReads.memo(char, :effect_options) { build_options(char) }
      end

      def self.build_options(char)
        [ "self:level:#{char.pf2_level.to_i}" ] +
          (char.pf2_conditions || {}).keys.map { |name| "self:condition:#{Domains.slug(name)}" } +
          Array(char.pf2_traits).map { |trait| "self:trait:#{Domains.slug(trait)}" }
      end

      def self.conditions(char)
        (char.pf2_conditions || {}).map do |name, held|
          info = Global.read_config('pf2e_conditions', name)

          next nil unless info && info['modifies']

          { 'name' => name,
            'modifies' => info['modifies'],
            'source' => { 'value' => Pf2e.condition_level(char, name) } }
        end.compact
      end

      def self.feats(char)
        (char.pf2_feats || {}).values.flatten.uniq.map do |name|
          info = Global.read_config('pf2e_feats', name)

          next nil unless info && info['modifies']

          { 'name' => name, 'modifies' => info['modifies'], 'source' => {} }
        end.compact
      end

      # An item's effects come from the catalogue, the same way a feat's do, and only while the item is
      # doing something: worn or held, and invested if it wants investing. An item in a backpack
      # modifies nothing.
      #
      # The item contributes its own facts as options too, because a predicate on an item's own rule
      # often asks about that item - `item:trait:visual` for a lens that helps you see.
      def self.items(char)
        Pf2egear.effective_items(char).map do |category, item|
          info = Pf2egear.catalogue_entry(category, item) || {}
          rows = info['modifies']

          next nil unless rows

          { 'name' => Pf2egear.get_item_name(item), 'modifies' => rows,
            'source' => { 'level' => item_level(item) },
            'options' => item_options(item) + Array(info['grants_options']) }
        end.compact
      end

      def self.item_level(item)
        item.respond_to?(:level) ? item.level.to_i : 0
      end

      def self.item_options(item)
        traits = item.respond_to?(:traits) ? Array(item.traits) : []

        [ "item:level:#{item_level(item)}" ] + traits.map { |trait| "item:trait:#{Domains.slug(trait)}" }
      end

      # What a formula on a `modifies` row may read about the character. Deliberately small: a figure
      # that could itself be modified has no place here, because reading it while assembling another
      # one is how a sheet render comes to depend on the order it happened to run in.
      def self.build_context(char)
        mods = Pf2e::ABILITIES.each_with_object({}) do |ability, out|
          out[Domains.abbreviation(ability)] = { 'mod' => Pf2e.ability_mod(char, ability) }
        end

        { 'actor' => { 'level' => char.pf2_level.to_i, 'abilities' => mods } }
      end

      def self.context(char)
        SheetReads.memo(char, :effect_context) { build_context(char) }
      end

      def self.for_stat(char, kind, name = nil, ability = nil, options = [])
        modifiers(sources(char), Domains.for(kind, name, ability), context(char),
                  options(char) + Array(options))
      end
    end
  end
end
