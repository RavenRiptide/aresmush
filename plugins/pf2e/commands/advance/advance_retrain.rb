module AresMUSH
  module Pf2e

    # advance/retrain <feat>: retrains the feat this level owes a retrain (a witch familiar taking over the
    # familiar a basic feat gave) into another, in the old feat's slot. The replacement goes through
    # FeatGain like any feat this level takes, so its grants and choices open here; the old feat leaves
    # DraftSheet's feats, and the level's commit revokes it.
    class PF2AdvanceRetrainCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :value

      def parse_args
        self.value = trim_arg(cmd.args)
      end

      def required_args
        [ self.value ]
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        advancement = enactor.pf2_advancement
        owed = Array(advancement['retrains']).find { |one| one['to'].blank? }

        return client.emit_failure(t('pf2e.retrain_none_owed')) unless owed

        found = Pf2e.get_feat_details(self.value)
        return client.emit_failure(Pf2e.feat_lookup_failure(self.value, found)) if found.is_a?(String)

        new_name, new_details = found
        old = Pf2e.get_feat_details(owed['from'])
        old_details = old.is_a?(Array) ? old[1] : {}

        failure = Retrain.check(owed, old_details, new_name, new_details)
        return if CharState.emit_error!(client, failure)

        failure = Retrain.sheet_block(enactor, owed, new_name, new_details)
        return client.emit_failure(failure) if failure

        owed['to'] = new_name

        # A feat another feat's choice gave (Natural Ambition's Familiar) takes the choice with it.
        made = Pf2e.recorded_choices(enactor).find { |_name, label, _level| label.to_s.casecmp?(owed['from']) }
        owed['choice'] = made.first if made

        to_assign = enactor.pf2_to_assign

        result = Advancement::FeatGain.apply(enactor, new_name, new_details,
          :bucket => owed['bucket'],
          :to_assign => to_assign,
          :advancement => advancement,
          :client => client)

        enactor.pf2_to_assign = to_assign
        enactor.pf2_advancement = advancement
        enactor.save

        client.emit_success t('pf2e.retrain_chosen', :old => owed['from'], :new => new_name)

        Advancement::FeatGain.emit!(client, result[:messages])
        result[:after_save].each { |deferred| Advancement::FeatGain.emit!(client, deferred.call) }
      end
    end
  end
end
