module AresMUSH
  module Pf2e

    # A feat's rule that changes the other creature in an attack, for that attack alone: Foundry's
    # `EphemeralEffect`. Dread Striker makes a frightened target off-guard to its holder; Spirits'
    # Interference makes whoever shoots at its raging holder pass a flat check first.
    #
    #   - key: "EphemeralEffect"
    #     selectors: [ "strike-attack-roll", "spell-attack-roll" ]
    #     uuid: "Compendium.pf2e.conditionitems.Item.Off-Guard"
    #     predicate: [ "target:condition:frightened" ]
    #     affects: "origin"          # absent: the holder's target; origin: whoever attacks the holder
    #
    # Foundry lends the named effect's rules to the other creature for the roll. Nothing here can lend
    # rules across, so each effect a feat names has a row in EFFECTS saying what it does to the attack, and
    # one with no row is refused (`complain`) rather than half applied.
    #
    # The holder's side asks about its target (`target:condition:frightened`), the round, and the target's
    # cover; a word the holder said after the target meets a condition only they know of (`tumble-behind`
    # after a Tumble Through), and is refused from someone holding no feat that listens for it. The
    # attacked side asks about the holder itself (`self:effect:rage`).
    module Ephemeral

      KEY = 'EphemeralEffect'.freeze

      # What each effect a feat may name does to the attack.
      #
      #   off_guard    the target is off-guard to it
      #   cover        what cover counts for: `ignore` levels it is ignored at, or `less` taken from its bonus
      #   concealment  concealment the attack's flat check is not rolled for
      #   flat         a flat check the attacker must pass first
      #   panache      the holder gains panache on the outcomes the row's tags name
      EFFECTS = {
        'Off-Guard' => { 'off_guard' => true },
        # The effect suppresses lesser cover; the feat's text adds the prey's concealment.
        "Effect: Hunter's Aim" => { 'cover' => { 'ignore' => %w{lesser} }, 'concealment' => %w{concealed} },
        # The effect takes 1 from cover's bonus; the feat's text adds the flat check against concealment.
        'Effect: Uncanny Bombs' => { 'cover' => { 'less' => 1 }, 'concealment' => %w{concealed} },
        "Effect: Spirits' Interference" => { 'flat' => 5 },
        'Effect: Panache (Ephemeral Note)' => { 'panache' => 'Effect: Panache (Temporary)' }
      }.freeze

      # What a row's `failure-note` and `critical-failure-note` tags say the panache waits for.
      TAGS = { 'failure-note' => 1, 'critical-failure-note' => 0 }.freeze

      # Effects that last until the holder is next attacked: Flashy Dodge is for the triggering attack.
      ENDS_WHEN_ATTACKED = [ 'Effect: Flashy Dodge' ].freeze

      def self.effect_of(row)
        row['uuid'].to_s.split('.Item.').last.to_s
      end

      def self.complain(holder_name, row)
        return if EFFECTS.key?(effect_of(row))

        Global.logger.warn "#{holder_name} has an EphemeralEffect naming #{effect_of(row).inspect}, which nothing applies."
      end

      # The holder's rows, on the side asked for: :target (theirs when they attack) or :origin (theirs when
      # they are attacked).
      def self.rows(holder, side)
        Effects.sources(holder).flat_map do |source|
          Rules.of_kind(source, KEY).filter_map do |raw|
            row = Rules.resolved(raw, source, {})
            next nil unless row

            origin = row['affects'].to_s == 'origin'
            next nil unless origin == (side == :origin)

            complain(source['name'], row)
            EFFECTS.key?(effect_of(row)) ? row.merge('source' => source['name']) : nil
          end
        end
      end

      # What the holder's rules know of the attack: what they said, what they see of the target, the
      # round, and the target's cover. Built here rather than read from `Acting.options_for`, which asks
      # this module whether the target is off-guard.
      def self.options(scene, said, cover = nil)
        target = scene.target
        seen = target ? Resolve.seen_as(target.holder, 'target') + Marks.seen(scene.actor.holder, target, 'target') : []
        round = scene.encounter ? [ "encounter:round:#{scene.encounter.round.to_i}" ] : []
        covered = cover ? [ "target:cover-level:#{cover}" ] : []

        Array(said['options']) + seen + round + covered
      end

      # The holder's effects on their target for an attack answering to these domains.
      def self.on_target(scene, said, domains, cover = nil)
        return [] unless scene.actor && scene.target

        held = options(scene, said, cover) + Effects.options(scene.actor.holder, domains)

        rows(scene.actor.holder, :target).select do |row|
          Domains.matches?(Rules.selectors_of(row), domains) && Predicate.test(row['predicate'], held)
        end
      end

      def self.doing(scene, said, domains, what, cover = nil)
        on_target(scene, said, domains, cover).filter_map { |row| EFFECTS[effect_of(row)][what] }
      end

      # Whether the holder's target is off-guard to their attacks.
      ATTACKS = %w{strike-attack-roll spell-attack-roll}.freeze

      def self.off_guard?(scene, said)
        doing(scene, said, ATTACKS, 'off_guard').any?
      end

      # Cover's modifier as this attack faces it, or nil once nothing is left of it.
      def self.cover(scene, said, domains, modifier)
        return modifier unless modifier

        level = modifier['source'].to_s.split(' ').first

        doing(scene, said, domains, 'cover', level).reduce(modifier) do |held, change|
          next nil if held.nil? || Array(change['ignore']).include?(level)

          value = held['value'].to_i - change['less'].to_i
          value.positive? ? held.merge('value' => value) : nil
        end
      end

      # The concealment this attack rolls a flat check for, or nil where it ignores it.
      def self.concealment(scene, said, domains, concealment)
        return concealment unless concealment

        ignored = doing(scene, said, domains, 'concealment').flatten

        ignored.include?(concealment.to_s) ? nil : concealment
      end

      # ------------------------------------------------------------------------------
      # When the holder is attacked

      # The attacked holder's effects on whoever attacks them, for an attack answering to these domains.
      def self.on_attacker(scene, domains)
        return [] unless scene.target

        holder = scene.target.holder
        held = Effects.options(holder, domains)

        rows(holder, :origin).select do |row|
          Domains.matches?(Rules.selectors_of(row), domains) && Predicate.test(row['predicate'], held)
        end
      end

      # The flat check the attacker must pass before this attack, as [ DC, the feat asking ], or nil.
      def self.flat_check(scene, domains)
        asked = on_attacker(scene, domains).select { |row| EFFECTS[effect_of(row)]['flat'] }
        row = asked.max_by { |one| EFFECTS[effect_of(one)]['flat'] }

        row ? [ EFFECTS[effect_of(row)]['flat'], row['source'] ] : nil
      end

      # The attack has been rolled at the holder: panache for a miss the holder's rules name, and the end of
      # what lasts only until they are attacked.
      def self.attacked(scene, domains, degree, out)
        return unless scene.target

        holder = scene.target.holder

        on_attacker(scene, domains).each do |row|
          gained = EFFECTS[effect_of(row)]['panache']
          next unless gained && degree && outcomes(row).include?(degree)

          applied = ActiveEffects.apply(holder, gained, :applied_by => scene.target.label, :encounter => scene.encounter)
          next if applied.err?

          out['lines'] << Telling.event('pf2e.act_now_under', :target => scene.target.label, :effect => gained,
                                                            :lasts => ActiveEffects.remaining(applied.state))
        end

        ENDS_WHEN_ATTACKED.each do |name|
          ActiveEffects.named_on(holder, name).each(&:delete)
        end
      end

      # The degrees a panache row waits for, from the tags its alterations add.
      def self.outcomes(row)
        Array(row['alterations']).filter_map { |one| TAGS[one['value'].to_s] if one['property'].to_s == 'other-tags' }
      end

      # ------------------------------------------------------------------------------
      # Words

      # Words a feat's row listens for: the plain options in a holder's-side predicate, which nothing but a
      # word said after the target or the feat's own action can meet.
      def self.words_of(rows)
        rows.flat_map { |row| Array(row['predicate']) }
            .select { |one| one.is_a?(String) && !one.include?(':') }.uniq
      end

      def self.listened_for
        @listened_for ||= {}
        @listened_for[Global.read_config('pf2e_feats').object_id] ||= words_of(
          (Global.read_config('pf2e_feats') || {}).values.select { |info| info.is_a?(Hash) }.flat_map do |info|
            Array(info['rules']).select { |row| row['key'] == KEY && row['affects'].to_s != 'origin' }
          end
        )
      end

      # A word said for a feat they don't hold, as a refusal.
      def self.word_refusal(scene, said)
        asked = Array(said['words']).map { |word| Domains.slug(word) } & listened_for
        return nil if asked.empty?

        theirs = words_of(rows(scene.actor.holder, :target))
        stray = asked - theirs

        stray.empty? ? nil : Err.new(:not_yours, 'pf2e.ephemeral_word_not_yours', 'word' => stray.first, 'actor' => scene.actor.label)
      end
    end
  end
end
