module AresMUSH
  module Pf2e

    # Mutagens: alchemical elixirs with the polymorph trait, each a benefit and a drawback in one effect.
    #
    # **The polymorph rule.** A creature benefits from one polymorph at a time. Drinking a mutagen ends the
    # benefits of the mutagen already in effect, and a battle form beginning ends every mutagen's; the
    # drawbacks stay until each runs out. Battle forms already keep to one at a time (`BattleForms`), so
    # this is the rule as it touches mutagens.
    #
    # **The Mutagenist** (an alchemist's research field):
    #
    # - Greater Field Discovery (13th): two mutagens at once, benefits and drawbacks. A third ends the
    #   benefits of the older of the two, and keeps every drawback.
    # - Field vials: drinking a versatile vial suppresses one mutagen's drawbacks for 1 minute - the newest
    #   mutagen whose benefits they still have.
    #
    # Which rows of a mutagen's rules are its drawback is read from what they do, since the effects are
    # imported: anything that lowers a number, caps one, costs Hit Points, adds a weakness, or takes away a
    # proficiency. Everything else is a benefit. A spec holds every stocked mutagen to that.
    module Mutagens

      # A minute of rounds, which is how long a field vial's suppression lasts.
      SUPPRESS_ROUNDS = 10

      LOWERING = %w{subtract remove downgrade}.freeze

      # The effects the stocked mutagens leave. Asked of every effect a sheet reads, so worked out once for
      # each catalogue it is asked of.
      def self.effect_names
        catalogue = Global.read_config('pf2e_consumables') || {}

        return @names if @names && @names_of == catalogue.object_id

        @names_of = catalogue.object_id
        @names = catalogue.filter_map do |_name, info|
          next nil unless info.is_a?(Hash) && Array(info['traits']).map(&:to_s).include?('mutagen')

          info['effect']
        end.uniq
      end

      def self.mutagen?(effect)
        name = effect.respond_to?(:name) ? effect.name : effect

        effect_names.include?(name.to_s)
      end

      def self.drawback?(row)
        case row['key'].to_s
        when 'FlatModifier' then Paths.number(row['value']).to_f.negative?
        when 'DexterityModifierCap', 'LoseHitPoints', 'Weakness' then true
        when 'ActiveEffectLike'
          LOWERING.include?(row['mode'].to_s) ||
            (row['mode'].to_s == 'override' && row['path'].to_s.end_with?('.rank') && row['value'].to_i.zero?)
        else false
        end
      end

      # A mutagen's rules as they stand: without its benefits once a later polymorph has ended them, and
      # without its drawbacks while a field vial suppresses them.
      def self.rules_of(effect, rules)
        return rules unless effect && mutagen?(effect)

        lost = effect.benefits_lost
        quiet = suppressed?(effect)

        Array(rules).select do |row|
          drawback?(row) ? !quiet : !lost
        end
      end

      def self.round_of(effect)
        encounter = effect.respond_to?(:encounter) ? effect.encounter : nil

        encounter ? encounter.round.to_i : 0
      end

      def self.suppressed?(effect)
        effect.drawbacks_until.to_i.positive? && round_of(effect) < effect.drawbacks_until.to_i
      end

      def self.on(holder)
        ActiveEffects.on(holder).select { |effect| mutagen?(effect) }
      end

      # How many mutagens' benefits they may hold at once.
      def self.room(holder)
        ResearchField.ability?(holder, 'Mutagenist', ResearchField::GREATER_FIELD_DISCOVERY) ? 2 : 1
      end

      # A polymorph has begun: a mutagen ends the benefits of the ones before it past what they may hold,
      # oldest first; a battle form ends them all.
      def self.began!(holder, effect)
        others = on(holder).reject { |one| one.id == effect.id || one.benefits_lost }.sort_by { |one| one.id.to_i }

        if mutagen?(effect)
          others.first([ others.size - (room(holder) - 1), 0 ].max).each { |one| one.update(:benefits_lost => true) }
        elsif battle_form?(effect)
          others.each { |one| one.update(:benefits_lost => true) }
        end
      end

      def self.battle_form?(effect)
        Array(ActiveEffects.info(effect.name)['rules']).any? { |row| row['key'].to_s == 'BattleForm' }
      end

      # A Mutagenist drinks a field vial: the newest mutagen whose benefits they still have keeps its
      # drawbacks quiet for a minute. Answers it, or nil when there is none.
      def self.suppress!(holder, encounter)
        found = on(holder).reject(&:benefits_lost).max_by { |one| one.id.to_i }

        return nil unless found

        found.update(:drawbacks_until => (encounter ? encounter.round.to_i : 0) + SUPPRESS_ROUNDS)
        found
      end

      # Whether a field vial's suppression holds for them now: what Advanced Vials' resistance lasts for.
      def self.suppressing?(holder)
        on(holder).any? { |effect| suppressed?(effect) }
      end

      # Persistent Mutagen: once a day, the mutagen they have just drunk lasts until their next daily
      # preparations instead. The newest mutagen on them is the one; the day's use comes back at a rest.
      PERSISTENT = 'Persistent Mutagen'.freeze

      def self.persist!(holder)
        return Err.new(:no_feat, 'pf2e.persistent_mutagen_no_feat') unless Pf2e.has_feat?(holder, PERSISTENT)
        return Err.new(:used, 'pf2e.persistent_mutagen_used') if TurnState.used(holder, PERSISTENT).positive?

        found = on(holder).max_by { |one| one.id.to_i }

        return Err.new(:no_mutagen, 'pf2e.persistent_mutagen_none') unless found

        found.update(:unit => 'days', :duration => 1, :rests_left => 1)

        uses = TurnState.of(holder)['uses'] || {}
        TurnState.write(holder, 'uses' => uses.merge(PERSISTENT => { 'count' => 1, 'period' => 'rest' }))

        Ok.new(:state => found)
      end
    end
  end
end
