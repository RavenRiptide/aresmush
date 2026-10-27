module AresMUSH
  module Pf2e

    class PF2ListRollAliasCmd
      include CommandHandler

      attr_accessor :alias, :value

      def check_approval
        return nil if (enactor.is_approved?) || (enactor.is_admin?)
        return t('pf2e.not_approved')
      end

      def handle
        list = enactor.pf2_roll_aliases

        template = Pf2eRollAliasTemplate.new(enactor, list)

        client.emit template.render
      end

    end
  end
end
