module AresMUSH
  module Pf2e

    # A feat's `triggers`: what happens when something the encounter already sees happens to its holder.
    # Each row names its event with `event`, what must be true of it, and what it does:
    #
    #   { event: action_used, actions: [ Retributive Strike ], self_condition: Quickened, until: own-next-turn-end }
    #   { event: strike_hit, action: Reactive Strike, target_condition: Off-Guard, until: own-next-turn-start }
    #   { event: hit_by_attack, attacker_damage: 3d6, damage_type: spirit }
    #   { event: target_dropped, traits: [ finisher ], self_effect: "Effect: Panache" }
    #
    # `per: round` lets it fire only once between the holder's turns. Who the holder is depends on the
    # event: the one acting, except for `hit_by_attack`, whose holder is the one hit.
    module FeatTriggers

      # What each event asks of a row, beyond the holder having it: the action's name or traits.
      EVENTS = {
        'action_used' => ->(row, about) { named?(row, about) && traits?(row, about) },
        'strike_hit' => ->(row, about) { named?(row, about) },
        'hit_by_attack' => ->(_row, _about) { true },
        'target_dropped' => ->(row, about) { named?(row, about) && traits?(row, about) }
      }.freeze

      def self.named?(row, about)
        wanted = Array(row['actions'] || row['action']).map { |one| Domains.slug(one) }

        wanted.empty? || wanted.include?(Domains.slug(about['action']))
      end

      def self.traits?(row, about)
        (Array(row['traits']).map(&:to_s) - Array(about['traits']).map(&:to_s)).empty?
      end

      # An event has happened. `about` holds the action's name and traits where the event has them.
      def self.fire(event, scene, out, about = {})
        test = EVENTS[event.to_s]

        return Global.logger.warn("Feat trigger event #{event} has no row in FeatTriggers::EVENTS.") unless test

        whom, other = event.to_s == 'hit_by_attack' ? [ scene.target, scene.actor ] : [ scene.actor, scene.target ]

        return unless whom

        FeatKeys.rows(whom.holder, 'triggers').each do |feat, row|
          next unless row['event'].to_s == event.to_s && test.call(row, about)
          next if row['per'] && !first_this_round?(whom.holder, feat)

          does(scene, whom, other, feat, row, out)
        end
      end

      # Out of Hit Points, or dead.
      def self.down?(holder)
        counts = Actors.of(holder).hit_point_counts

        Pf2e.dead?(holder) || (!counts.nil? && counts.first.to_i <= 0)
      end

      def self.first_this_round?(holder, feat)
        return false if TurnState.used(holder, feat).positive?

        TurnState.count_use(holder, feat, 'round')
        true
      end

      # `holder` is whoever has the feat, whose turn an `own-` time is counted from; `other` is the one
      # across from them.
      def self.does(scene, holder, other, feat, row, out)
        condition(scene, holder, holder, feat, row['self_condition'], row['until'], out) if row['self_condition']
        condition(scene, holder, other, feat, row['target_condition'], row['until'], out) if row['target_condition'] && other
        effect(scene, holder, feat, row['self_effect'], out) if row['self_effect']
        damage(scene, other, feat, row, out) if row['attacker_damage'] && other
      end

      def self.condition(scene, holder, whom, feat, name, until_when, out)
        name = Pf2e.canonical_condition(name)
        set = Pf2e.set_condition(whom.holder, name, Pf2e.default_condition_value(name))

        return out['lines'] << Telling.event(set.key, set.args) if set.err?

        ends = scene.encounter && until_when ? Turns.expiry_for(until_when, scene.encounter, holder.label, whom.label) : nil
        Acting.expire_at(whom.holder, name, ends) if ends
        out['lines'] << Telling.event('pf2e.feat_triggered', 'feat' => feat, 'target' => whom.label, 'result' => name)
      end

      def self.effect(scene, whom, feat, name, out)
        return if ActiveEffects.active?(whom.holder, name)

        applied = ActiveEffects.apply(whom.holder, name, :applied_by => scene.actor.label, :encounter => scene.encounter)

        return out['lines'] << Telling.event(applied.key, applied.args) if applied.err?

        out['lines'] << Telling.event('pf2e.feat_triggered', 'feat' => feat, 'target' => whom.label, 'result' => name)
      end

      def self.damage(scene, whom, feat, row, out)
        formula = row['attacker_damage'].to_s
        out['lines'] << Telling.event('pf2e.feat_triggered', 'feat' => feat, 'target' => whom.label,
                                                              'result' => "#{formula} #{row['damage_type']}")
        Acting.deal(scene, whom, [ { 'amount' => Pf2e.roll_formula(formula), 'type' => row['damage_type'].to_s,
                                     'formula' => formula } ], out)
      end

      # ------------------------------------------------------------------------------
      # An effect a feat lifts as its action is used

      # A feat's `lifts_effect` for this action and the words said: the effect it lifts is taken away
      # before the action's own effect lands, and what that effect leaves when it ends is answered.
      #
      #   { action: Rage, word: second-wind, effect: "Effect: Rage Temporary Hit Points Immunity", after: Fatigued }
      def self.lifted(holder, action, words)
        said = Array(words).map { |word| Domains.slug(word) }

        FeatKeys.rows(holder, 'lifts_effect').select do |_feat, row|
          Domains.slug(row['action']) == Domains.slug(action) && said.include?(Domains.slug(row['word']))
        end
      end

      # Answers the rows that lifted something; a word said with nothing to lift costs nothing.
      def self.lift!(holder, action, words)
        lifted(holder, action, words).select do |_feat, row|
          held = ActiveEffects.named_on(holder, row['effect'])
          held.each { |one| ActiveEffects.remove(holder, one) }
          held.any?
        end
      end
    end
  end
end
