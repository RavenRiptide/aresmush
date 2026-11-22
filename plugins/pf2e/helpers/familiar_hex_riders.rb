module AresMUSH
  module Pf2e
    module Familiar

      # A witch patron's familiar ability (Player Core p. 211): "When you Cast or Sustain a hex", the familiar
      # does something more. Casting or Sustaining a hex, with the familiar in the encounter, readies its
      # rider for the rest of the witch's turn, once for each hex; the witch then uses it as a free action,
      # `e/act familiar of restored spirit=#4`. A rider about the map (ice, flanking) is only told.
      #
      #   Restored Spirit   a willing creature gains temporary Hit Points (its effect)
      #   Balanced Luck     a creature gets +1 or -1 status to AC (its effect, `/+1` or `/-1`)
      #   Keen Senses       the familiar gains a sense (its effect, `/scent`), and may Point Out
      #   Ongoing Misery    one timed condition on a creature ends a round later, once for each case of it
      #   Stalking Night    an enemy becomes Frightened 1
      module HexRiders

        HEX = 'hex'.freeze
        READY = 'hex_rider'.freeze
        PROLONGED = 'prolonged'.freeze

        RESTORED_SPIRIT = 'Familiar of Restored Spirit'.freeze
        BALANCED_LUCK = 'Familiar of Balanced Luck'.freeze
        KEEN_SENSES = 'Familiar of Keen Senses'.freeze
        ONGOING_MISERY = 'Familiar of Ongoing Misery'.freeze
        STALKING_NIGHT = 'Familiar of Stalking Night'.freeze

        # The riders the game runs, and the riders it only tells.
        RUN = [ RESTORED_SPIRIT, BALANCED_LUCK, KEEN_SENSES, ONGOING_MISERY, STALKING_NIGHT ].freeze
        TOLD = [ 'Familiar of Freezing Rime', 'Familiar of Flowing Script' ].freeze

        SENSES = %w{scent tremorsense wavesense}.freeze
        LUCK = { '+1' => '+1', '1' => '+1', '-1' => '-1' }.freeze

        def self.rider?(name)
          RUN.include?(name)
        end

        def self.hex?(spell)
          found = Pf2emagic.get_spell_details(spell.to_s)
          found.is_a?(Array) && Array(found[1]['traits']).map { |one| one.to_s.downcase }.include?(HEX)
        end

        # A hex was Cast or Sustained: the patron's rider is readied, or told where it only describes.
        def self.hexed!(scene, spell, out)
          return unless scene.encounter && hex?(spell)

          holder = scene.actor.holder
          patron = Stats.patron_ability(holder)
          familiar = patron ? familiar_here(scene) : nil
          return unless familiar

          if TOLD.include?(patron)
            out['lines'] << Telling.event('pf2e.hex_rider_told', :name => familiar.label, :ability => patron,
                                                                 :text => rider_text(patron))
            return
          end

          TurnState.write(holder, 'turn' => TurnState.turn(holder).merge(READY => patron))
          out['lines'] << Telling.event('pf2e.hex_rider_ready', :name => familiar.label, :ability => patron,
                                                                :command => "e/act #{patron.downcase}#{usage(patron)}")
        end

        def self.familiar_here(scene)
          row = Combatants.minions_of(scene.encounter, scene.actor.number).first
          row ? Combatants.combatant(row) : nil
        end

        def self.rider_text(name)
          (Daily.catalogue[name] || {})['shortdesc'].to_s.split('%r').first.to_s
        end

        def self.usage(name)
          case name
          when BALANCED_LUCK then '=<target>/+1 or -1'
          when KEEN_SENSES then '/scent, tremorsense or wavesense'
          when ONGOING_MISERY then '=<target>/<condition>'
          else '=<target>'
          end
        end

        # The witch uses the rider. Answers the report, or why it can't be used.
        def self.use(scene, name, words, out)
          holder = scene.actor.holder
          patron = Stats.patron_ability(holder)
          return Err.new(:not_your_rider, 'pf2e.hex_rider_not_yours', 'ability' => name) unless patron == name

          familiar = familiar_here(scene)
          return Err.new(:no_familiar_here, 'pf2e.familiar_lifelink_absent') unless familiar
          return Err.new(:no_hex, 'pf2e.hex_rider_no_hex', 'ability' => name) unless TurnState.turn(holder)[READY] == name

          done = case name
                 when RESTORED_SPIRIT then restored_spirit(scene, out)
                 when BALANCED_LUCK then balanced_luck(scene, words, out)
                 when KEEN_SENSES then keen_senses(scene, familiar, words, out)
                 when ONGOING_MISERY then ongoing_misery(scene, words, out)
                 else stalking_night(scene, out)
                 end
          return done if done.is_a?(Err)

          TurnState.write(holder, 'turn' => TurnState.turn(holder).merge(READY => nil))
          Ok.new(:state => out)
        end

        def self.needs_target(scene)
          scene.target ? nil : Err.new(:no_target, 'pf2e.act_needs_target')
        end

        def self.apply(scene, whom, effect, answers, out)
          applied = ActiveEffects.apply(whom.holder, effect, :options => answers, :applied_by => scene.actor.label,
                                                             :encounter => scene.encounter,
                                                             :origin => ActiveEffects.origin(:by => scene.actor.holder))
          return applied if applied.err?

          out['lines'] << Telling.event('pf2e.hex_rider_effect', :target => whom.label, :effect => ActiveEffects.bare_name(applied.state))
          nil
        end

        def self.restored_spirit(scene, out)
          needs_target(scene) || apply(scene, scene.target, "Effect: #{RESTORED_SPIRIT}", [], out)
        end

        def self.balanced_luck(scene, words, out)
          missing = needs_target(scene)
          return missing if missing

          luck = Array(words).map { |one| LUCK[one.to_s.strip] }.compact.first
          return Err.new(:which_luck, 'pf2e.hex_rider_luck') unless luck

          apply(scene, scene.target, "Effect: #{BALANCED_LUCK}", [ luck ], out)
        end

        def self.keen_senses(scene, familiar, words, out)
          sense = Array(words).map { |one| one.to_s.strip.downcase }.find { |one| SENSES.include?(one) }
          return Err.new(:which_sense, 'pf2e.hex_rider_sense') unless sense

          found = apply(scene, familiar, "Effect: #{KEEN_SENSES}", [ sense ], out)
          return found if found

          out['lines'] << Telling.event('pf2e.hex_rider_point_out', :name => familiar.label)
          nil
        end

        # One timed condition, a round longer, and marked so that case is never prolonged again.
        def self.ongoing_misery(scene, words, out)
          missing = needs_target(scene)
          return missing if missing

          holder = scene.target.holder
          held = holder.pf2_conditions || {}
          typed = Array(words).join(' ').strip
          name = held.keys.find { |one| one.casecmp?(typed) }
          return Err.new(:no_such_condition, 'pf2e.hex_rider_no_condition', 'target' => scene.target.label, 'condition' => typed) unless name

          info = held[name]
          ends = info.is_a?(Hash) ? info['expires'] : nil
          return Err.new(:untimed, 'pf2e.hex_rider_untimed', 'condition' => name) unless ends
          return Err.new(:prolonged, 'pf2e.hex_rider_prolonged', 'condition' => name) if info[PROLONGED]

          longer = info.merge('expires' => ends.merge('round' => ends['round'].to_i + 1), PROLONGED => true)
          holder.update(:pf2_conditions => held.merge(name => longer))
          out['lines'] << Telling.event('pf2e.hex_rider_prolonged_done', :target => scene.target.label, :condition => name)
          nil
        end

        def self.stalking_night(scene, out)
          missing = needs_target(scene)
          return missing if missing

          holder = scene.target.holder
          Pf2e.set_condition(holder, 'Frightened', [ Pf2e.condition_level(holder, 'Frightened'), 1 ].max)
          out['lines'] << Telling.event('pf2e.hex_rider_frightened', :target => scene.target.label)
          nil
        end
      end
    end
  end
end
