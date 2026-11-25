module AresMUSH
  module Pf2e

    module CompanionOutcome
      def rendered(failure)
        t(failure.key, **failure.args.transform_keys(&:to_sym))
      end
    end

    # companion/name <name>: names their animal companion, for staff to approve. The name is checked before
    # anything is saved (Companion::Names).
    class PF2CompanionNameCmd
      include CommandHandler
      include CompanionOutcome

      attr_accessor :value

      def parse_args
        self.value = cmd.args.to_s
      end

      def required_args
        [ self.value.strip.empty? ? nil : self.value ]
      end

      def check_has_companion
        Companion.main(enactor) ? nil : t('pf2e.companion_none_yours')
      end

      def check_value
        found = checked
        found.err? ? rendered(found) : nil
      end

      def checked
        @checked ||= Companion::Names.name(self.value, enactor)
      end

      def handle
        replacing = Companion.replacement(enactor)
        request = Companion.set_name!(enactor, checked.state)

        if replacing
          client.emit_success t('pf2e.companion_name_set_replacement', :name => checked.state)
        elsif request
          client.emit_success t('pf2e.companion_name_set_request', :name => checked.state, :number => request.id)
        else
          client.emit_success t('pf2e.companion_name_set', :name => checked.state)
        end
      end
    end

    # What companion/approve and companion/reject share: staff only, and the character named.
    module StaffCompanionCommand
      def check_can_change_sheet
        return nil if enactor.has_permission?('manage_sheet')
        return t('dispatcher.not_allowed')
      end

      def subject
        @subject ||= Pf2e.get_character(self.character, enactor)
      end
    end

    # companion/approve <character>: approves their animal companion's name, and closes the request.
    class PF2CompanionApproveCmd
      include CommandHandler
      include CompanionOutcome
      include StaffCompanionCommand

      attr_accessor :character

      def parse_args
        self.character = trim_arg(cmd.args)
      end

      def required_args
        [ self.character ]
      end

      def handle
        return client.emit_failure(t('pf2e.not_found')) unless subject

        outcome = Companion.approve!(subject, :by => enactor)
        return client.emit_failure(rendered(outcome)) if outcome.err?

        key = outcome.state['replaced'] ? 'pf2e.companion_approved_replacement' : 'pf2e.companion_approved'
        name = outcome.state['approved']['name']
        client.emit_success t(key, :char => subject.name, :name => name)
        Array(outcome.state['came_off']).each do |item|
          client.emit_ooc t('pf2e.companion_gear_came_off_staff', :name => name, :char => subject.name, :item => item)
        end
      end
    end

    # companion/reject <character>=<reason>: sends their animal companion's name back with the reason, in the
    # request.
    class PF2CompanionRejectCmd
      include CommandHandler
      include CompanionOutcome
      include StaffCompanionCommand

      attr_accessor :character, :reason

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.character = trim_arg(args.arg1)
        self.reason = trim_arg(args.arg2)
      end

      def required_args
        [ self.character, self.reason ]
      end

      def handle
        return client.emit_failure(t('pf2e.not_found')) unless subject

        outcome = Companion.reject!(subject, :by => enactor, :reason => self.reason)
        return client.emit_failure(rendered(outcome)) if outcome.err?

        client.emit_success t('pf2e.companion_rejected', :char => subject.name)
      end
    end
  end
end
