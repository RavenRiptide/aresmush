module AresMUSH
  module Pf2e

    # Things a character can do: Take Cover, Rage, a monk's stance.
    #
    # The catalogue (`pf2e_actions.yml`, from Foundry's actions pack and the feats that are actions) says
    # what each costs and what it puts on whoever uses it - Foundry's `selfEffect`. Using one that has
    # an effect puts the character under it, through `ActiveEffects` like any other effect, so everything
    # the effect does and how long it lasts is already handled.
    module Actions

      # What an action costs, as a sheet says it.
      COSTS = { 1 => 'one action', 2 => 'two actions', 3 => 'three actions' }.freeze
      TYPES = { 'reaction' => 'reaction', 'free' => 'free action', 'passive' => 'passive' }.freeze

      def self.catalogue
        Global.read_config('pf2e_actions') || {}
      end

      def self.info(name)
        catalogue[name] || {}
      end

      # The action a player means, by the name they typed.
      def self.find(term)
        wanted = Domains.slug(term)
        names = catalogue.keys

        exact = names.find { |name| Domains.slug(name) == wanted }

        return Ok.new(:state => exact) if exact

        close = names.select { |name| Domains.slug(name).include?(wanted) }

        return Ok.new(:state => close.first) if close.size == 1
        return Err.new(:not_found, 'pf2e.action_not_found', 'action' => term) if close.empty?

        Err.new(:ambiguous, 'pf2e.action_ambiguous', 'action' => term, 'options' => close.first(8).join(', '))
      end

      def self.cost(name)
        entry = info(name)

        TYPES[entry['type']] || COSTS[entry['cost'].to_i] || 'one action'
      end

      # ------------------------------------------------------------------------------
      # Whose it is

      # Whether the character can use an action. The basic, skill, exploration and downtime actions are
      # everyone's. Anything else - a class's, an archetype's, a heritage's - and any feat that is an
      # action, is theirs if a feat or feature of theirs has its name: the Rage class feature is what gives
      # a barbarian Rage, at the level the class grants it and not before.
      def self.usable(char, name)
        entry = info(name)

        return Ok.new(:state => name) if entry['for'] == 'everyone' || owned?(char, name)

        Err.new(:not_yours, 'pf2e.action_not_yours', 'action' => name)
      end

      def self.owned?(char, name)
        wanted = Domains.slug(name)
        held = (char.pf2_feats || {}).values.flatten + (char.pf2_features || {}).values.flatten

        held.any? { |one| Domains.slug(one) == wanted }
      end

      # ------------------------------------------------------------------------------
      # Using one

      # The character uses an action. Where it puts an effect on them, they are now under it; `options` are
      # what they say about that effect, as `ActiveEffects.apply` takes them.
      #
      #   Ok state: { 'action' => name, 'effect' => the effect put on them, or nil }
      def self.use(char, term, options: [], encounter: nil)
        found = find(term)

        return found if found.err?

        name = found.state
        allowed = usable(char, name)

        return allowed if allowed.err?

        effect_name = info(name)['self_effect']

        return Ok.new(:state => { 'action' => name, 'effect' => nil }) unless effect_name

        applied = ActiveEffects.apply(char, effect_name, :options => options, :applied_by => char.name,
                                                         :encounter => encounter)

        return applied if applied.err?

        Ok.new(:state => { 'action' => name, 'effect' => applied.state })
      end
    end
  end
end
