module AresMUSH
  module Pf2e

    # A ranger's Hunt Prey in an encounter (Player Core p. 160): the creature designated is marked on their
    # `Effect: Hunt Prey` as `hunted-prey`, which is what the action's own bonuses and their hunter's edge
    # (Flurry, Outwit, Precision) read (`target:mark:hunted-prey`). One prey at a time, so a new Hunt Prey moves
    # the mark.
    #
    # With Animal Companion (Ranger), their companion gains the action's benefits and their hunter's edge: the
    # "Share Hunter's Edge" effect for that edge, marked on the same creature as `share-hunters-edge`, or its
    # Masterful version with Masterful Companion.
    #
    # Precision's extra damage waits on a toggle Foundry leaves to the player. Here it is switched on for the
    # first Strike each round that hits the prey, or the second and third where a Masterful version allows them.
    module HuntPrey

      NAME = 'Hunt Prey'.freeze
      EFFECT = 'Effect: Hunt Prey'.freeze
      SLUG = 'hunted-prey'.freeze
      SHARE = "Effect: Share Hunter's Edge".freeze
      SHARE_SLUG = 'share-hunters-edge'.freeze
      SLUGS = [ SLUG, SHARE_SLUG ].freeze
      COMPANION_FEAT = 'Animal Companion (Ranger)'.freeze
      MASTERFUL_FEAT = 'Masterful Companion'.freeze
      PRECISION = 'precision-hunters-edge'.freeze
      HITS = %w{first-hit second-hit third-hit}.freeze
      MASTERFUL_PRECISION = "#{SHARE} (Precision, Masterful)".freeze

      # The action, taken: nil while exploring with no creature named, where it is only the effect, as before.
      def self.act(scene, name, entry, risked)
        return nil if scene.target.nil? && (scene.encounter.nil? || Exploration.exploring?(scene.encounter))
        return Err.new(:no_prey, 'pf2e.hunt_prey_needs_target', 'actor' => scene.actor.label) unless scene.target

        out = Acting.report
        out['lines'].concat(risked['lines']) if risked

        marked = mark!(scene.actor.holder, EFFECT, SLUG, scene.target.label, scene.actor.label, scene.encounter,
                       :origin => Acting.action_origin(scene, name, entry))
        return marked if marked.err?

        out['lines'] << Telling.event('pf2e.hunt_prey_marked', :actor => scene.actor.label, :target => scene.target.label,
                                                               :cost => Actions.cost(name))
        shared = share!(scene.encounter, scene.actor, scene.target.label)
        out['lines'] << shared if shared
        Acting.spend(scene, name, entry, out)

        Ok.new(:state => out)
      end

      # `name` on the holder, alone of its kind, marking `label`. `kind` is the start of the effects it
      # replaces.
      def self.mark!(holder, name, slug, label, by, encounter, kind: name, origin: nil)
        ActiveEffects.on(holder).select { |effect| effect.name.start_with?(kind) }.each { |effect| ActiveEffects.remove(holder, effect) }

        applied = ActiveEffects.apply(holder, name, :applied_by => by, :encounter => encounter, :origin => origin)
        return applied if applied.err?

        applied.state.update(:mark => { 'label' => label, 'slug' => slug })
        applied
      end

      # The creature this holder hunts, by its label, or nil.
      def self.prey(holder)
        effect = ActiveEffects.named_on(holder, EFFECT).find { |one| (one.mark || {})['slug'] == SLUG }
        effect ? effect.mark['label'] : nil
      end

      # The Share Hunter's Edge effect a ranger's companion gains: their edge's, Masterful with Masterful
      # Companion. Nil without Animal Companion (Ranger), or for an edge with no such effect.
      def self.shared_effect(char)
        return nil unless char && Pf2e.has_feat?(char, COMPANION_FEAT)

        edge = (char.pf2_base_info || {})['specialize'].to_s
        name = "#{SHARE} (#{edge}#{Pf2e.has_feat?(char, MASTERFUL_FEAT) ? ', Masterful' : ''})"
        ActiveEffects.catalogue.key?(name) ? name : nil
      end

      # Their companion in the encounter gains the shared effect on their prey. Answers what the room is told.
      def self.share!(encounter, actor, label)
        state = actor.holder
        char = state.respond_to?(:character) ? state.character : nil
        name = shared_effect(char)
        row = name && encounter ? Combatants.minions_of(encounter, actor.number, 'companion').first : nil
        npc = row ? Combatants.holder_of(row) : nil
        return nil unless npc

        given = mark!(npc, name, SHARE_SLUG, label, actor.label, encounter, :kind => SHARE)
        return nil if given.err?

        Telling.event('pf2e.hunt_prey_shared', :name => npc.name, :target => label, :effect => name)
      end

      # A companion joining a ranger who already hunts a prey here gains the shared effect too. True when it did.
      def self.joined!(encounter, char, state, npc)
        label = prey(state)
        name = label ? shared_effect(char) : nil
        return false unless name

        mark!(npc, name, SHARE_SLUG, label, char.name, encounter, :kind => SHARE).ok?
      end

      # The options that switch on Precision's extra damage for a Strike against the holder's marked prey: the
      # first hit on it this round, or the second and third where a Masterful version allows them. `earlier` is
      # the turn's Strikes so far.
      def self.precision_options(holder, target, earlier)
        return [] unless target && marked?(holder, target.label)

        hits = Array(earlier).count { |one| one['hit'] && one['target'] == target.label }
        hits < precision_limit(holder) ? [ PRECISION, "#{PRECISION}:#{HITS[hits]}" ] : []
      end

      def self.marked?(holder, label)
        ActiveEffects.on(holder).any? { |effect| (effect.mark || {})['label'] == label && SLUGS.include?(effect.mark['slug']) }
      end

      def self.precision_limit(holder)
        return 1 unless ActiveEffects.active?(holder, MASTERFUL_PRECISION)

        holder.pf2_level.to_i >= 19 ? 3 : 2
      end
    end
  end
end
