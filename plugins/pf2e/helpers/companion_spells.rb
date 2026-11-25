module AresMUSH
  module Pf2e
    module Companion

      # Spells cast on an animal companion. A spell whose target reads "your animal companion" (Heal Companion,
      # Magic Hide, Enlarge Companion, Spirit of the Beast), "animal companion in your service" (Apex Companion)
      # or "yourself or your animal companion" (Canopy Crawler) reaches only the caster's own companion, or the
      # caster where it says so. The GM may force it. Its effect lands on the companion's record as any spell's
      # does.
      #
      # Instinctive Support (druid 6, a free action): right after a non-cantrip spell cast only at one's own
      # companion, the companion gains its actions for the turn as if Commanded, and one of them must be Support.
      # Support follows no other action, so it must come first.
      module Spells

        OWN_ONLY = /\b(your animal companion|animal companion in your service)\b/i
        SELF_TOO = /\byourself or your animal companion\b/i
        INSTINCTIVE = 'Instinctive Support'.freeze

        def self.own?(actor, target)
          !target.nil? && Riding.companion?(target.holder) && target.master.to_i == actor.number.to_i
        end

        # The refusal of a companion spell aimed at anything but the caster's own companion, or at nothing.
        def self.refusal(scene, spell, targets, words)
          name, mechanics = Acting.spell_mechanics(spell)
          text = (mechanics || {})['target'].to_s
          return nil unless text.match?(OWN_ONLY) || text.match?(SELF_TOO)
          return nil if Acting.forced?(scene, words)

          self_too = text.match?(SELF_TOO)
          if targets.empty?
            return nil if self_too

            return Err.new(:companion_spell_untargeted, 'pf2e.companion_spell_needs_companion', 'spell' => name)
          end

          wrong = targets.find do |target|
            !(own?(scene.actor, target) || (self_too && target.holder.id.to_s == scene.actor.holder.id.to_s &&
                                            target.holder.class == scene.actor.holder.class))
          end
          return nil unless wrong

          Err.new(:companion_spell_not_own, 'pf2e.companion_spell_own_only', 'spell' => name, 'target' => wrong.label)
        end

        # ------------------------------------------------------------------------------
        # Instinctive Support

        # A spell was cast: one that may trigger Instinctive Support marks the caster's turn with the companion's
        # id, until anything else is done. Called once the spell is spent.
        def self.cast!(scene, spell, targets)
          holder = scene.actor.holder
          _name, mechanics = Acting.spell_mechanics(spell)
          cantrip = Array((mechanics || {})['traits']).map(&:to_s).include?('cantrip')
          one = targets.size == 1 && !cantrip && own?(scene.actor, targets.first) ? targets.first.number : nil
          return if one.nil? && TurnState.turn(holder)['instinctive'].nil?

          TurnState.write(holder, 'turn' => TurnState.turn(holder).merge('instinctive' => one))
        end

        # `e/act instinctive support`: the companion the spell was cast at gains 2 actions, Support first.
        def self.instinctive(scene, name)
          holder = scene.actor.holder
          number = TurnState.turn(holder)['instinctive']
          row = number && scene.encounter ? Combatants.rows(scene.encounter).find { |one| one['id'].to_i == number.to_i } : nil
          npc = row ? Combatants.holder_of(row) : nil
          return Err.new(:no_instinctive, 'pf2e.companion_instinctive_none', 'actor' => scene.actor.label) unless npc

          refused = Minion.command_refusal(npc, row['name'], Minion::COMMAND, 1)
          return refused if refused

          Minion.command!(npc, Minion::COMMANDED)
          TurnState.write(npc, 'turn' => TurnState.turn(npc).merge('must_support' => true))

          out = Acting.report
          out['lines'] << Telling.event('pf2e.companion_instinctive_gained', :name => row['name'], :ref => "##{row['id']}")
          Acting.spend(scene, name, Actions.info(name), out)
          TurnState.write(holder, 'turn' => TurnState.turn(holder).merge('instinctive' => nil))

          Ok.new(:state => out)
        end

        # Its first action after Instinctive Support must be Support.
        def self.must_support_refusal(npc, label, name)
          return nil unless TurnState.turn(npc)['must_support'] && !Support.supported?(npc) && name != Support::NAME

          Err.new(:must_support, 'pf2e.companion_must_support', 'name' => label)
        end
      end
    end
  end
end
