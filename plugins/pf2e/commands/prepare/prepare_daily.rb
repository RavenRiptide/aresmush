module AresMUSH
  module Pf2e

    # prepare/<switch> [<pick>]: a daily choice a feat has the character make, the switch its data names,
    # such as prepare/longevity Athletics. With no pick, it lists what they can pick from.
    class PF2PrepareDailyCmd
      include CommandHandler

      attr_accessor :pick

      def parse_args
        self.pick = trim_arg(cmd.args)
      end

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
      end

      def handle
        block = DailyChoices.for_switch(enactor, cmd.switch)

        return client.emit_failure(t('pf2e.daily_not_held', :switch => cmd.switch)) unless block

        return list(block) if self.pick.blank?

        outcome = DailyChoices.pick!(enactor, cmd.switch, self.pick)

        return if CharState.emit_error!(client, outcome)

        made = outcome.state
        key = made['previous'] ? 'pf2e.daily_picked_instead' : 'pf2e.daily_picked'

        client.emit_success t(key, :source => made['source'], :pick => DailyChoices.label(made), :previous => made['previous'],
                                   :switch => cmd.switch.downcase)

        # A batch brewed in the encounter they are in.
        return if Array(made['brewed']).empty?

        client.emit_success t('pf2e.daily_brewed', :name => enactor.name, :items => made['brewed'].join(', '), :source => made['source'])
      end

      def list(block)
        options = DailyChoices.options(enactor, block)

        return client.emit_failure(t('pf2e.daily_no_options', :source => block['source'])) if options.empty?

        client.emit BorderedListTemplate.new(options, t('pf2e.daily_options_title', :source => block['source'])).render
      end
    end

    # unprepare/<switch>: takes back the pick made since the last rest, putting back the one it replaced if
    # that one was still in force.
    class PF2UnprepareDailyCmd
      include CommandHandler

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
      end

      def handle
        outcome = DailyChoices.unpick!(enactor, cmd.switch)

        return if CharState.emit_error!(client, outcome)

        taken = outcome.state
        key = taken['restored'] ? 'pf2e.daily_unpicked_restored' : 'pf2e.daily_unpicked_ok'

        client.emit_success t(key, :source => taken['source'], :pick => taken['taken'], :restored => taken['restored'],
                                   :switch => cmd.switch.downcase)
      end
    end
  end
end
