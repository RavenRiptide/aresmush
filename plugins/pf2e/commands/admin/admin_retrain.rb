module AresMUSH
  module Pf2e

    # admin/retrain <character>=<old feat>/<new feat>: swaps a feat they hold for another in the same slot,
    # by PF2e's retraining rules (Pf2e::Retrain).
    class PF2AdminRetrainCmd
      include CommandHandler

      attr_accessor :character, :old_feat, :new_feat

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        feats = args.arg2.to_s.split('/', 2)

        self.character = trim_arg(args.arg1)
        self.old_feat = trim_arg(feats[0])
        self.new_feat = trim_arg(feats[1])
      end

      def required_args
        [ self.character, self.old_feat, self.new_feat ]
      end

      def check_can_change_sheet
        return nil if enactor.has_permission?('manage_sheet')
        return t('dispatcher.not_allowed')
      end

      def handle
        subject = Pf2e.get_character(self.character, enactor)

        return client.emit_failure(t('pf2e.not_found')) unless subject
        return client.emit_failure(t('pf2e.retrain_not_approved', :char => subject.name)) unless subject.is_approved?
        return client.emit_failure(t('pf2e.retrain_drafting', :char => subject.name)) if subject.advancing

        old = resolve(self.old_feat)
        return unless old

        new = resolve(self.new_feat)
        return unless new

        old_name, old_details = old
        new_name, new_details = new

        taking = Retrain.taking(subject, old_name)
        return client.emit_failure(t('pf2e.retrain_not_held', :char => subject.name, :feat => old_name)) unless taking

        failure = Retrain.check(taking, old_details, new_name, new_details)
        return if CharState.emit_error!(client, failure)

        failure = against_sheet(subject, taking, old_name, old_details, new_name, new_details)
        return client.emit_failure(failure) if failure

        Retrain.retrain!(subject, taking, old_details, new_name, :by => enactor.name)

        client.emit_success t('pf2e.retrain_done', :char => subject.name, :old => old_name, :new => new_name,
                              :level => taking['level'])
      end

      private

      def resolve(term)
        found = Pf2e.get_feat_details(term)

        return found unless found.is_a?(String)

        client.emit_failure Pf2e.feat_lookup_failure(term, found)

        nil
      end

      # The questions that read the character, each a rendered message or nil.
      def against_sheet(subject, taking, old_name, old_details, new_name, new_details)
        return t('pf2e.retrain_old_grants', :feat => old_name) unless Retrain.reversible?(old_details)
        return t('pf2e.retrain_new_opens', :feat => new_name) if Retrain.opens_anything?(new_details)

        dependents = Retrain.dependents(subject, old_name)
        return t('pf2e.retrain_dependents', :feat => old_name, :feats => dependents.sort.join(', ')) unless dependents.empty?

        repeat = Pf2e.feat_repeat_block(subject, new_name, new_details, nil, taking['level'])
        return repeat if repeat

        prereqs = new_details['prereq']
        return nil if prereqs.blank? || Pf2e.meets_prereqs?(subject, prereqs, taking['level'])

        Pf2e.explain_feat_block(subject, new_details) || t('pf2e.feat_fails_prereq')
      end
    end
  end
end
