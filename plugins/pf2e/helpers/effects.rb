module AresMUSH
  module Pf2e

    # What a feat, an item or a condition does, gathered from whatever carries it.
    #
    # `grants:` already lets a feat declare what it gives you - a further feat, a training slot, a
    # proficiency. `rules:` is the same idea for the numbers: a list of rule elements in Foundry's own
    # vocabulary, described in `Pf2e::Rules`. The thing with the effect carries the effect, so nothing
    # in the engine has to know that Toughness exists.
    #
    # Two roots are available to a formula on a rule, and both are Foundry's. `@actor` is the
    # character - level and attribute modifiers, the facts that cannot themselves be modified without
    # circularity. `@item` is the thing carrying the rule: `@item.badge.value` is a condition's value,
    # which is how Frightened 3 is the same row as Frightened 1, and `@item.level` an item's level.
    #
    # An item may also declare circumstances of its own, with `grants_options:`, taken from its
    # RollOption rules. A Clandestine Cloak predicates its bonuses on `clandestine-cloak` and declares
    # that option itself, so wearing the cloak is enough and a player has nothing to say. What stays
    # conditional is what depends on the player: the action they are taking, or a fact about the check.
    module Effects

      # Foundry writes a selector that names the item itself by interpolating its id, as in
      # `{item|id}-damage`. The domain a statistic declares for that weapon is the resolved one, so the
      # selector is resolved the same way before it is matched.
      SELF_REFERENCE = /\{item\|_?id\}/

      def self.modifiers(sources, domains, context = {}, options = [])
        rows_of(sources, domains, context, options, 'FlatModifier')
      end

      def self.damage_dice(sources, domains, context = {}, options = [])
        rows_of(sources, domains, context, options, 'DamageDice')
      end

      # Every contribution of one kind that reaches a statistic with these domains, each carrying
      # whether its circumstances were met. An unmet row is reported rather than dropped, because
      # "you have a +2 here but only while picking a lock" is what a player wants to know.
      def self.rows_of(sources, domains, context, options, key)
        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])
          own = context.merge('item' => source['item'] || {})

          Rules.of_kind(source, key).each_with_object([]) do |row, out|
            next unless reaches?(row, source, domains)

            contribution = Rules.contribute(row, source, own)

            next unless contribution

            out << contribution.merge('when' => row['predicate'],
                                      'met' => Predicate.test(row['predicate'], held))
          end
        end
      end

      def self.reaches?(row, source, domains)
        selectors = Array(row['selector']).map { |named| resolve(named, source) }

        Domains.matches?(selectors, domains)
      end

      def self.resolve(selector, source)
        selector.to_s.gsub(SELF_REFERENCE, source['id'].to_s)
      end

      # ------------------------------------------------------------------------------

      def self.sources(char)
        SheetReads.memo(char, :effect_sources) { conditions(char) + feats(char) + items(char) }
      end

      # A source, with its rules held against what we implement. Checked here rather than where a row
      # is applied, because a kind nothing applies would otherwise never be looked at: the reader
      # filters to the kind it wants first, and a rule nobody wants is exactly the one to complain
      # about. Sources are assembled once per read block, so this says it once.
      def self.source(name, rules, extras = {})
        Array(rules).each { |row| Rules.complain(name, row) }

        { 'name' => name, 'rules' => rules }.merge(extras)
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

      # A condition's value is its badge, which is Foundry's word for the number a condition carries.
      def self.conditions(char)
        (char.pf2_conditions || {}).map do |name, _held|
          info = Global.read_config('pf2e_conditions', name)

          next nil unless info && info['rules']

          source(name, info['rules'],
                 'id' => Domains.slug(name),
                 'item' => { 'badge' => { 'value' => Pf2e.condition_level(char, name) },
                             'level' => char.pf2_level.to_i })
        end.compact
      end

      def self.feats(char)
        (char.pf2_feats || {}).values.flatten.uniq.map do |name|
          info = Global.read_config('pf2e_feats', name)

          next nil unless info && info['rules']

          source(name, info['rules'],
                 'id' => Domains.slug(name), 'item' => { 'level' => char.pf2_level.to_i })
        end.compact
      end

      # An item's effects come from the catalogue, the same way a feat's do, and only while the item is
      # doing something: worn or held, and invested if it wants investing.
      #
      # Its id is its own, because a rule may name it - a rune that adds fire damage to *this* sword
      # says `{item|id}-damage`, and the sword's damage domains include exactly that.
      def self.items(char)
        Pf2egear.effective_items(char).map do |category, item|
          info = Pf2egear.catalogue_entry(category, item) || {}

          next nil unless info['rules']

          source(Pf2egear.get_item_name(item), info['rules'],
                 'id' => item.id.to_s,
                 'item' => { 'level' => item_level(item) },
                 'options' => item_options(item) + Array(info['grants_options']))
        end.compact
      end

      def self.item_level(item)
        item.respond_to?(:level) ? item.level.to_i : 0
      end

      def self.item_options(item)
        traits = item.respond_to?(:traits) ? Array(item.traits) : []

        [ "item:level:#{item_level(item)}" ] + traits.map { |trait| "item:trait:#{Domains.slug(trait)}" }
      end

      def self.context(char)
        SheetReads.memo(char, :effect_context) { build_context(char) }
      end

      # What a formula on a rule may read about the character. Deliberately small: a figure that could
      # itself be modified has no place here, because reading it while assembling another one is how a
      # sheet render comes to depend on the order it happened to run in.
      def self.build_context(char)
        mods = Pf2e::ABILITIES.each_with_object({}) do |ability, out|
          out[Domains.abbreviation(ability)] = { 'mod' => Pf2e.ability_mod(char, ability) }
        end

        { 'actor' => { 'level' => char.pf2_level.to_i, 'abilities' => mods } }
      end

      def self.for_stat(char, kind, name = nil, ability = nil, options = [])
        modifiers(sources(char), Domains.for(kind, name, ability), context(char),
                  options(char) + Array(options))
      end
    end
  end
end
