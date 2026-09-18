module AresMUSH
  module Pf2e

    # What happens as a turn in an encounter starts or ends.
    #
    # Everything that keeps time with the order happens here, and each thing that happens is answered as
    # an event - a locale key and its arguments - so whoever tells the room decides how. Nothing here
    # emits anything.
    #
    #   as a turn starts   effects timed to it end; temporary hit points refresh; fast healing and
    #                      regeneration heal
    #   as a turn ends     effects timed to it end; a sustained effect nobody sustained ends; persistent
    #                      damage is dealt and its flat check rolled
    module Turns

      def self.event(key, args = {})
        { 'key' => key, 'args' => args }
      end

      # The order has moved on: one turn ended and the next began.
      def self.advanced(encounter, ending, ending_round, starting, starting_round)
        ended = ending ? turn_ended(encounter, ending, ending_round) : []

        ended + turn_started(encounter, starting, starting_round)
      end

      def self.turn_started(encounter, participant, round)
        events = ActiveEffects.expire(encounter, 'turn-start', participant, round)
        char = Character.named(participant)

        return events unless char

        ActiveEffects.on(char).each { |effect| ActiveEffects.give_temp_hp(char, effect, 'on_turn_start') }

        events + heal(char)
      end

      def self.turn_ended(encounter, participant, round)
        events = ActiveEffects.expire(encounter, 'turn-end', participant, round) +
                 ActiveEffects.unsustained(encounter, participant, round)
        char = Character.named(participant)

        return events unless char

        events + PersistentDamage.end_of_turn(char)
      end

      # ------------------------------------------------------------------------------
      # Fast healing and regeneration

      # What heals the character as their turn starts, from any source: a spell's effect, a feat, an
      # item. Regeneration does nothing on a turn after damage of a kind that switches it off.
      def self.healing(char)
        context = Effects.context(char)
        options = Effects.options(char)

        Effects.sources(char).flat_map do |source|
          Rules.of_kind(source, 'FastHealing').select { |row| Predicate.test(row['predicate'], options) }
                                              .map { |row| Rules.contribute(row, source, context.merge('item' => source['item'] || {})) }
                                              .compact
        end
      end

      def self.heal(char)
        off = (char.pf2_turn_state || {})['regeneration_off']
        char.update(:pf2_turn_state => (char.pf2_turn_state || {}).except('regeneration_off'))

        healing(char).map do |one|
          next nil if one['type'] == 'regeneration' && off
          next nil unless one['value'].positive?

          Pf2eHP.modify_damage(char, one['value'], true)
          event('pf2e.fast_healing', 'name' => char.name, 'amount' => one['value'], 'source' => one['source'])
        end.compact
      end

      # Damage of a kind that switches regeneration off does so until the character's next turn.
      def self.damaged(char, kind)
        return unless kind

        stops = healing(char).select { |one| one['type'] == 'regeneration' }
                             .flat_map { |one| one['deactivated_by'] }.map { |one| Domains.slug(one) }

        return unless stops.include?(Domains.slug(kind))

        char.update(:pf2_turn_state => (char.pf2_turn_state || {}).merge('regeneration_off' => true))
      end
    end
  end
end
