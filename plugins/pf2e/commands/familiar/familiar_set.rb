module AresMUSH
  module Pf2e

    # familiar/name <name>, familiar/species <species>, familiar/form <form>: sets a detail of their
    # familiar for staff to approve. The value is checked before anything is saved (Familiar::Details).
    class PF2FamiliarSetCmd
      include CommandHandler
      include FamiliarOutcome

      FIELDS = %w{name species form}.freeze

      attr_accessor :field, :value

      def parse_args
        self.field = cmd.switch.to_s.downcase
        self.value = cmd.args.to_s
      end

      def required_args
        [ self.value.strip.empty? ? nil : self.value ]
      end

      def check_field
        FIELDS.include?(self.field) ? nil : t('dispatcher.not_allowed')
      end

      def check_has_familiar
        Familiar.main_source(enactor) ? nil : t('pf2e.familiar_none_yours')
      end

      def check_value
        found = checked
        found.err? ? rendered(found) : nil
      end

      def checked
        @checked ||= case self.field
                     when 'name' then Familiar::Details.name(self.value)
                     when 'species' then Familiar::Details.species(self.value)
                     else Familiar::Details.form(self.value).and_then { |form| Familiar::Choices.form_allowed(enactor, form) }
                     end
      end

      def handle
        request = Familiar.set!(enactor, self.field, checked.state)
        label = t("pf2e.familiar_field_#{self.field}")

        if request
          client.emit_success t('pf2e.familiar_detail_set_request', :field => label, :value => checked.state, :number => request.id)
        else
          client.emit_success t('pf2e.familiar_detail_set', :field => label, :value => checked.state)
        end
      end
    end

    # What familiar/approve and familiar/reject share: staff only, and the character named.
    module StaffFamiliarCommand
      def check_can_change_sheet
        return nil if enactor.has_permission?('manage_sheet')
        return t('dispatcher.not_allowed')
      end

      def subject
        @subject ||= Pf2e.get_character(self.character, enactor)
      end
    end

    # familiar/approve <character>: approves the details their familiar is waiting on, and closes the request.
    class PF2FamiliarApproveCmd
      include CommandHandler
      include FamiliarOutcome
      include StaffFamiliarCommand

      attr_accessor :character

      def parse_args
        self.character = trim_arg(cmd.args)
      end

      def required_args
        [ self.character ]
      end

      def handle
        return client.emit_failure(t('pf2e.not_found')) unless subject

        outcome = Familiar.approve!(subject, :by => enactor)
        return client.emit_failure(rendered(outcome)) if outcome.err?

        client.emit_success t('pf2e.familiar_approved', :char => subject.name, :name => outcome.state['approved']['name'])
      end
    end

    # familiar/reject <character>=<reason>: sends the details back with the reason, in the request.
    class PF2FamiliarRejectCmd
      include CommandHandler
      include FamiliarOutcome
      include StaffFamiliarCommand

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

        outcome = Familiar.reject!(subject, :by => enactor, :reason => self.reason)
        return client.emit_failure(rendered(outcome)) if outcome.err?

        client.emit_success t('pf2e.familiar_rejected', :char => subject.name)
      end
    end

    # familiar/cantrip <character>=<old cantrip>/<new cantrip>: changes a cantrip their Cantrip Connection
    # adds to their repertoire, which stands in for retraining it (Familiar::MasterSpells).
    class PF2FamiliarCantripCmd
      include CommandHandler
      include FamiliarOutcome
      include StaffFamiliarCommand

      attr_accessor :character, :old_cantrip, :new_cantrip

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        cantrips = args.arg2.to_s.split('/', 2)

        self.character = trim_arg(args.arg1)
        self.old_cantrip = trim_arg(cantrips[0])
        self.new_cantrip = trim_arg(cantrips[1])
      end

      def required_args
        [ self.character, self.old_cantrip, self.new_cantrip ]
      end

      def handle
        return client.emit_failure(t('pf2e.not_found')) unless subject
        unless Familiar::MasterSpells.repertoire?(subject)
          return client.emit_failure(t('pf2e.familiar_cantrip_not_repertoire', :name => subject.name))
        end

        outcome = Familiar::MasterSpells.change!(subject, self.old_cantrip, self.new_cantrip)
        return client.emit_failure(rendered(outcome)) if outcome.err?

        client.emit_success t('pf2e.familiar_cantrip_changed', :name => subject.name, :old => outcome.state['old'],
                                                               :new => outcome.state['new'])
      end
    end
  end
end
