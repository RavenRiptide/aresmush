module AresMUSH
  module Pf2e

    # Devise a Stratagem: an investigator rolls a d20 ahead against a creature, then decides what the roll
    # is for. An attack stratagem stands in for the d20 of their first Strike at that creature this round,
    # with an agile or finesse weapon or a ranged one, and an investigator may add Intelligence to that
    # Strike in place of Strength or Dexterity. A skill or defensive stratagem gives up Striking the creature
    # until their next turn.
    #
    # The effect the action leaves carries the roll as its badge and marks the creature (`Pf2e::Marks`), so
    # the effect's own rules - the substituted roll, the skill and defensive bonuses - read from it. Which
    # stratagem it is lives in the effect's answers, which its `devise-a-stratagem` toggle selects from.
    module Stratagem

      NAME = 'Devise a Stratagem'.freeze
      EFFECT = 'Effect: Devise a Stratagem'.freeze
      SLUG = 'devise-a-stratagem'.freeze

      ATTACK = 'attack'.freeze
      KINDS = %w{attack skill defensive}.freeze

      # The feat that opens a defensive stratagem.
      DEFENSIVE = 'defensive'.freeze
      DEFENSIVE_FEAT = 'feat:defensive-stratagem'.freeze

      # `encounter/act devise a stratagem=<target>` rolls; with no target, `/skill` or `/defensive`
      # chooses another stratagem for the roll already made.
      def self.act(scene, name, entry, said, risked)
        kind = (said['words'] & KINDS).first

        return choose(scene, kind) unless scene.target

        out = Acting.report
        out['lines'].concat(risked['lines']) if risked

        refused = kind && kind_refusal(scene, kind)
        return refused if refused

        devise(scene, name, entry, kind || ATTACK, out)
        Acting.spend(scene, name, entry, out)

        Ok.new(:state => out)
      end

      def self.devise(scene, name, entry, kind, out)
        holder = scene.actor.holder
        face = Pf2e.roll_dice(1, 20).first

        ActiveEffects.named_on(holder, EFFECT).each { |effect| ActiveEffects.remove(holder, effect) }

        applied = ActiveEffects.apply(holder, EFFECT, :options => [ "value #{face}", kind ],
                                                      :applied_by => scene.actor.label, :encounter => scene.encounter,
                                                      :origin => Acting.action_origin(scene, name, entry))
        return out['lines'] << Telling.event(applied.key, applied.args) if applied.err?

        applied.state.update(:mark => { 'label' => scene.target.label, 'slug' => SLUG })

        out['lines'] << Telling.event('pf2e.stratagem_rolled', :actor => scene.actor.label, :target => scene.target.label,
                                                               :roll => face, :cost => Actions.cost(name))
        out['lines'] << Telling.event('pf2e.stratagem_how', :target => scene.target.label, :kinds => others(holder, kind))
      end

      # Another stratagem for the roll already made, which costs nothing: the choice is part of the action.
      def self.choose(scene, kind)
        holder = scene.actor.holder
        effect = ActiveEffects.named_on(holder, EFFECT).first

        return Err.new(:no_stratagem, 'pf2e.stratagem_none', 'actor' => scene.actor.label) unless effect
        return Err.new(:which_stratagem, 'pf2e.stratagem_which', 'kinds' => allowed(holder).join(', ')) unless kind

        refused = kind_refusal(scene, kind)
        return refused if refused

        effect.update(:answers => [ kind ])
        Paths.apply_all!(holder)

        out = Acting.report
        out['lines'] << Telling.event('pf2e.stratagem_chosen', :actor => scene.actor.label, :kind => kind,
                                                               :target => (effect.mark || {})['label'].to_s)
        Ok.new(:state => out)
      end

      def self.kind_refusal(scene, kind)
        return nil if allowed(scene.actor.holder).include?(kind)

        Err.new(:no_defensive, 'pf2e.stratagem_no_defensive', 'actor' => scene.actor.label)
      end

      def self.allowed(holder)
        Effects.facts(holder).include?(DEFENSIVE_FEAT) ? KINDS : KINDS - [ DEFENSIVE ]
      end

      def self.others(holder, kind)
        (allowed(holder) - [ kind ]).map { |one| "e/act devise a stratagem/#{one}" }.join(' or ')
      end

      # The stratagem `holder` has devised against `target`, a combatant, and which kind it is.
      def self.against(holder, target)
        effect = Marks.marking(holder, target, SLUG)

        effect ? [ effect, Array(effect.answers).find { |one| KINDS.include?(one) } || ATTACK ] : [ nil, nil ]
      end

      # A skill or defensive stratagem gives up Striking the creature until the start of the next turn.
      def self.strike_refusal(scene)
        effect, kind = against(scene.actor.holder, scene.target)

        return nil unless effect && kind != ATTACK

        Err.new(:stratagem_no_strike, 'pf2e.stratagem_no_strike', 'actor' => scene.actor.label,
                                                                   'target' => scene.target.label, 'kind' => kind)
      end

      # The attack's check with Intelligence among the attributes it may use, where the stratagem's roll
      # stands in for its d20 and the one Striking is an investigator. The Investigator archetype's
      # stratagem lends the roll without the Intelligence.
      def self.attack_check(scene, attack, check, options)
        found = check.substitution

        return check unless found && found['slug'] == SLUG
        return check unless Effects.facts(scene.actor.holder).include?('class:investigator')

        Check.of(scene.actor.holder, 'attack', attack.merge('stratagem' => true), options)
      end

      # An attack stratagem goes with the first Strike at the creature, whether the roll stood in for its
      # d20 or the weapon could not use it.
      def self.after_strike(scene, check, attack, out)
        effect, kind = against(scene.actor.holder, scene.target)

        return unless effect && kind == ATTACK
        return if check.substituted.to_s == SLUG

        ActiveEffects.remove(scene.actor.holder, effect)
        out['lines'] << Telling.event('pf2e.stratagem_lost', :actor => scene.actor.label, :weapon => attack['name'])
      end
    end
  end
end
