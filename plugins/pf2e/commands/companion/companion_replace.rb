module AresMUSH
  module Pf2e

    # companion/replace [<type>]: starts replacing their animal companion, with a new animal of the same build,
    # or of the type specified. Staff approve the replacement; until then, the old companion stays in force.
    class PF2CompanionReplaceCmd
      include CommandHandler
      include CompanionOutcome

      attr_accessor :type

      def parse_args
        self.type = trim_arg(cmd.args)
      end

      def check_can_replace
        refusal = Companion.replace_refusal(enactor)
        refusal ? t(refusal) : nil
      end

      def handle
        outcome = Companion.start_replacement!(enactor, self.type)
        return client.emit_failure(rendered(outcome)) if outcome.err?

        char = Character[enactor.id]
        state = outcome.state
        left = Companion.choices_left(char).uniq

        parts = [ t('pf2e.companion_replace_started', :old => state['old'], :type => state['type'].downcase) ]
        parts << t('pf2e.companion_replace_choose', :feats => left.join(', ')) unless left.empty?
        parts << t('pf2e.companion_replace_name')
        parts << t('pf2e.companion_replace_request', :number => state['request'].id) if state['request']

        client.emit_success parts.join(' ')
      end
    end

    # companion/replace/option <feat>=<choice>: makes one of the choices a replacement of another type makes
    # again, such as nimble or savage.
    class PF2CompanionReplaceOptionCmd
      include CommandHandler
      include CompanionOutcome

      attr_accessor :feat, :choice

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.feat = trim_arg(args.arg1)
        self.choice = trim_arg(args.arg2)
      end

      def required_args
        [ self.feat, self.choice ]
      end

      def handle
        outcome = Companion.choose_for_replacement!(enactor, self.feat, self.choice)
        return client.emit_failure(rendered(outcome)) if outcome.err?

        state = outcome.state
        said = t('pf2e.companion_replace_option_set', :feat => state['feat'], :choice => state['choice'])
        left = state['left'].uniq
        said = "#{said} #{t('pf2e.companion_replace_option_left', :feats => left.join(', '))}" unless left.empty?

        client.emit_success said
      end
    end

    # companion/replace/cancel: withdraws a replacement still waiting for staff.
    class PF2CompanionReplaceCancelCmd
      include CommandHandler
      include CompanionOutcome

      def handle
        outcome = Companion.cancel_replacement!(enactor)
        return client.emit_failure(rendered(outcome)) if outcome.err?

        client.emit_success t('pf2e.companion_replace_cancelled', :old => outcome.state['old'])
      end
    end

    # companion/dead <character> and companion/revive <character>: staff mark a companion dead, or alive again
    # when it's raised or reincarnated exactly as it was.
    class PF2CompanionDeadCmd
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

      def dead?
        cmd.switch.to_s.downcase == 'dead'
      end

      def handle
        return client.emit_failure(t('pf2e.not_found')) unless subject

        outcome = Companion.mark_dead!(subject, :dead => dead?)
        return client.emit_failure(rendered(outcome)) if outcome.err?

        name = Companion.name_of(Character[subject.id]) || t('pf2e.companion_subject_unnamed_mid')
        client.emit_success t(dead? ? 'pf2e.companion_marked_dead' : 'pf2e.companion_revived', :char => subject.name, :name => name)
      end
    end
  end
end
