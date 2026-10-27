module AresMUSH
  module Pf2e

    # `rollprefix [<all|actions|off>]` - how much of what the game tells is marked with its prefix for
    # you (see `SystemPrefix`); with nothing after it, how much is now.
    class PF2RollPrefixCmd
      include CommandHandler

      attr_accessor :level

      def parse_args
        self.level = cmd.args ? downcase_arg(cmd.args) : nil
      end

      def handle
        levels = SystemPrefix::LEVELS

        unless self.level
          return client.emit_ooc t('pf2e.rollprefix_now', :prefix => SystemPrefix.prefix,
                                   :level => SystemPrefix.level_of(enactor), :options => levels.join('|'))
        end

        return client.emit_failure(t('pf2e.bad_option', :element => 'level', :options => levels.join(', '))) unless levels.include?(self.level)

        enactor.update(:pf2_roll_prefix => self.level)
        client.emit_success t('pf2e.rollprefix_set', :prefix => SystemPrefix.prefix, :level => self.level)
      end
    end
  end
end
