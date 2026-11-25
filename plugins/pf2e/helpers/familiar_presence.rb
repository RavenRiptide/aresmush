module AresMUSH
  module Pf2e
    module Familiar

      # Patron's Presence (witch, 14th): the familiar extends a 15-foot emanation until the end of its master's
      # next turn, which it can Sustain up to 1 minute. An enemy that enters it or starts its turn in it
      # attempts a Will save against the master's spell DC, or is stupefied 2 (3 on a critical failure) while
      # it remains in it.
      #
      # Using the activity puts `Aura: Patron's Presence` on the familiar. `e/enter patron's presence=<enemy>`
      # (through `e/as`) marks an enemy inside with `Effect: Patron's Presence (Inside)` and rolls the save
      # (`PF2EncounterAuraCmd`); a Stupefied the save leaves is marked with the aura, so leaving it or the aura
      # ending takes it away (`Auras.leave`, `Auras.dispelled`). An enemy still inside rolls again as its turn
      # starts, while the aura hasn't already stupefied it.
      module Presence

        NAME = "Patron's Presence".freeze
        AURA = "Aura: Patron's Presence".freeze
        INSIDE = "Effect: Patron's Presence (Inside)".freeze
        SLUG = 'patron-s-presence'.freeze
        STUPEFIED = 'Stupefied'.freeze

        # MonsterAbilities' run: the aura goes up around the familiar.
        def self.start(use)
          familiar = use.actor.holder
          ActiveEffects.on(familiar).select { |one| one.name == AURA }.each { |one| ActiveEffects.remove(familiar, one) }

          applied = ActiveEffects.apply(familiar, AURA, :applied_by => use.actor.label, :encounter => use.scene.encounter)
          return use.out['lines'] << Telling.event(applied.key, applied.args) if applied.err?

          use.out['lines'] << Telling.event('pf2e.familiar_presence_started', :name => use.actor.label, :ref => use.actor.ref)
        end

        # After an aura save: a Stupefied it left or worsened is the aura's, to end when they leave it.
        def self.after_save(emitter, target, before)
          was = (before || {})[STUPEFIED]
          now = (target.pf2_conditions || {})[STUPEFIED]
          return unless now.is_a?(Hash)
          return if was.is_a?(Hash) && was['value'].to_i >= now['value'].to_i

          Acting.note_on(target, STUPEFIED, 'aura_of' => Auras.origin(emitter, 'slug' => SLUG))
        end

        # Whether this is the aura whose saves are Patron's Presence's.
        def self.aura?(slug)
          slug.to_s == SLUG
        end

        # As someone's turn starts: inside an aura that hasn't stupefied them, they attempt the save again.
        # Answers the lines for the room.
        def self.turn_started(holder)
          ActiveEffects.on(holder).select { |one| one.name == INSIDE && one.aura_of.present? }.flat_map do |inside|
            origin = inside.aura_of
            next [] if stupefied_by?(holder, origin)

            encounter = inside.encounter
            emitter = encounter && emitter_of(encounter, origin)
            target = encounter && Combatants.all(encounter).find { |one| one.holder && Pf2e.holder_key(one.holder) == Pf2e.holder_key(holder) }
            own = emitter && Actors.of(emitter.holder).own_ability(NAME)
            next [] unless emitter && target && own

            before = holder.pf2_conditions || {}
            out = Acting.report
            out['lines'] << Telling.event('pf2e.familiar_presence_turn_save', :target => target.label, :name => emitter.label)
            Acting.ability_saves(Acting::Scene.new(encounter, emitter, target, nil, true), own['name'], own, [ target ], out)
            after_save(emitter.holder, holder.class[holder.id], before)

            out['lines']
          end
        end

        def self.stupefied_by?(holder, origin)
          held = (holder.pf2_conditions || {})[STUPEFIED]

          held.is_a?(Hash) && held['aura_of'] == origin
        end

        # The combatant whose aura an origin names: `<holder key>:<slug>`.
        def self.emitter_of(encounter, origin)
          key = origin.to_s.delete_suffix(":#{SLUG}")

          Combatants.all(encounter).find { |one| one.holder && Pf2e.holder_key(one.holder) == key }
        end
      end
    end
  end
end
