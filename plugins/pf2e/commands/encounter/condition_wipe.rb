module AresMUSH
  module Pf2e

    # `condition/wipe <list>` - clear every condition set on each combatant named.
    class PF2ConditionWipeCmd
      include CommandHandler

      attr_accessor :target

      def parse_args
        self.target = trimmed_list_arg(cmd.args)
      end

      def required_args
        [ self.target ]
      end

      def handle
        encounter = Pf2e::Combatants.encounter_here(enactor)
        target_list = ActiveEffects.targets(client, enactor, self.target)

        return if target_list.empty?

        unless Pf2e.can_damage_pc?(enactor, target_list.map(&:name), encounter&.id)
          client.emit_failure t('pf2e.cannot_damage_pc')
          return
        end

        done = target_list.reject { |char| Pf2e::CharState.emit_error!(client, Pf2e.wipe_conditions(char)) }

        return if done.empty?

        client.emit_success t('pf2e.conditions_wiped', :targets => done.map(&:name).sort.join(', '))

        # What something else brings stays while that does, and whoever wiped them is told.
        done.each do |char|
          Pf2e.held_conditions(char).each do |name, held|
            client.emit_ooc t('pf2e.condition_kept', :condition => name, :target => char.name, :from => held['granted_by'])
          end
        end
      end
    end
  end
end
