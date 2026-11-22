module AresMUSH
  module Pf2e

    # What a refused detail or pick says, rendered for the player. Here rather than in familiar_set.rb
    # because this file loads first (a plugin's files load in sorted order) and every familiar command uses it.
    module FamiliarOutcome
      def rendered(failure)
        t(failure.key, **failure.args.transform_keys(&:to_sym))
      end
    end

    # What the familiar pick commands share: they need a familiar, check the answer before saving anything
    # (Familiar::Choices), and say where the change waits for staff.
    module FamiliarPickCommand
      include FamiliarOutcome

      def check_has_familiar
        Familiar.main_source(enactor) ? nil : t('pf2e.familiar_none_yours')
      end

      def check_value
        found = checked
        found.err? ? rendered(found) : nil
      end

      # The change was saved: what it is, then where it waits.
      def emit_saved(message, request)
        waits = request ? t('pf2e.familiar_waits_request', :number => request.id) : t('pf2e.familiar_waits_app')

        client.emit_success "#{message} #{waits}"
      end
    end

    # familiar/specific <specific familiar>, or familiar/specific none: makes their familiar a specific
    # familiar (Player Core 2), whose choices are then made with familiar/choose.
    class PF2FamiliarSpecificCmd
      include CommandHandler
      include FamiliarPickCommand

      attr_accessor :value

      def parse_args
        self.value = cmd.args.to_s
      end

      def required_args
        [ self.value.strip.empty? ? nil : self.value ]
      end

      def checked
        @checked ||= Familiar::Choices.specific(enactor, self.value)
      end

      def handle
        name = checked.state
        message = name ? t('pf2e.familiar_specific_set', :name => name) : t('pf2e.familiar_specific_cleared')
        comment = name ? t('pf2e.familiar_specific_comment', :name => name) : t('pf2e.familiar_specific_cleared_comment')

        request = Familiar.change!(enactor, comment) do |pending|
          # Another specific familiar asks other things, so its choices start again.
          pending.delete('choices') unless pending['specific'] == name
          pending['specific'] = name
        end

        emit_saved(message, request)

        open = Familiar::Choices.open_choices(Character[enactor.id]).keys
        client.emit_ooc t('pf2e.familiar_choices_open', :words => open.join(', '), :word => open.first) unless open.empty?
      end
    end

    # familiar/pet <ability>, <ability>: a plain pet's two abilities, fixed when it is gained.
    class PF2FamiliarPetCmd
      include CommandHandler
      include FamiliarPickCommand

      attr_accessor :value

      def parse_args
        self.value = cmd.args.to_s
      end

      def required_args
        [ self.value.strip.empty? ? nil : self.value ]
      end

      def checked
        @checked ||= Familiar::Choices.pet_abilities(enactor, self.value)
      end

      def handle
        abilities = Familiar.abilities_text(checked.state)
        comment = t('pf2e.familiar_pet_comment', :abilities => abilities)

        request = Familiar.change!(enactor, comment) { |pending| pending['pet_abilities'] = checked.state }
        message = t('pf2e.familiar_pet_set', :abilities => abilities)
        emit_saved(message, request)
      end
    end

    # familiar/choose <choice>=<answer>: a choice their specific familiar or Leshy Familiar asks for.
    class PF2FamiliarChooseCmd
      include CommandHandler
      include FamiliarPickCommand

      attr_accessor :word, :answer

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.word = trim_arg(args.arg1)
        self.answer = trim_arg(args.arg2)
      end

      def required_args
        [ self.word, self.answer ]
      end

      def checked
        @checked ||= Familiar::Choices.choose(enactor, self.word, self.answer)
      end

      def handle
        word, answer = checked.state
        label = t(Familiar::Choices.open_choices(enactor)[word]['label'])
        message = t('pf2e.familiar_choice_set', :label => label, :answer => answer)
        comment = t('pf2e.familiar_choice_comment', :label => label, :answer => answer)

        request = Familiar.change!(enactor, comment) do |pending|
          pending['choices'] = (pending['choices'] || {}).merge(word => answer)
        end

        emit_saved(message, request)
      end
    end
  end
end
