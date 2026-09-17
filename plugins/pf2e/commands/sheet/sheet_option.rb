module AresMUSH
  module Pf2e

    # `sheet/option` - the circumstances a character's own gear and feats offer, and which are on.
    class PF2RollOptionCmd
      include CommandHandler

      attr_accessor :option, :setting

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.option = downcase_arg(args.arg1)
        self.setting = downcase_arg(args.arg2)
      end

      def handle
        return client.emit PF2RollOptionsTemplate.new(Pf2e::RollOptions.declared(enactor)).render if
          self.option.blank?

        found = Pf2e::RollOptions.find(enactor, self.option)

        if !found
          client.emit_failure t('pf2e.no_such_option', :option => self.option)
          return
        end

        change(found)
      end

      # Naming an option with nothing after it turns it off or on, whichever it is not, because that is
      # what a switch does. `=default` hands it back to whatever declared it.
      def change(found)
        name = found['option']

        if self.setting == 'default'
          Pf2e::RollOptions.clear(enactor, name)
          return client.emit_success t('pf2e.option_default', :option => name)
        end

        on = case self.setting
             when 'on', 'yes' then true
             when 'off', 'no' then false
             else !found['on']
             end

        Pf2e::RollOptions.set(enactor, name, on)

        client.emit_success t(on ? 'pf2e.option_on' : 'pf2e.option_off', :option => name)
      end
    end
  end
end
