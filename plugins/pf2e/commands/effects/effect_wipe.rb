module AresMUSH
  module Pf2e

    # `effect/wipe <who>` - end every effect on each combatant named, and whatever each brought with it.
    class PF2EffectWipeCmd
      include CommandHandler

      attr_accessor :targets

      def parse_args
        self.targets = trimmed_list_arg(cmd.args)
      end

      def required_args
        [ self.targets ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)
        chars = ActiveEffects.targets(client, enactor, self.targets)

        return if chars.empty?

        unless Pf2e.can_damage_pc?(enactor, chars.map(&:name), encounter&.id)
          client.emit_failure t('pf2e.cannot_damage_pc')
          return
        end

        done = chars.reject { |char| CharState.emit_error!(client, ActiveEffects.wipe(char)) }

        return if done.empty?

        client.emit_success t('pf2e.effects_wiped', :targets => done.map(&:name).sort.join(', '))
      end
    end
  end
end
