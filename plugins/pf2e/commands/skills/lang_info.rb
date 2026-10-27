module AresMUSH
  module Pf2e
    class PF2LanguageInfoCmd
      include CommandHandler

      attr_accessor :type

      def parse_args
        self.type = downcase_arg(cmd.args)
      end

      def required_args
        [ self.type ]
      end

      # Every group the language config has, so a group added there - rare, for one - can be listed
      # without a change here.
      def check_valid_type
        types = (Global.read_config('pf2e_languages') || {}).keys

        return nil if types.include?(self.type)
        return t('pf2e.bad_option', :element=>'language type', :options=>types.join(", "))
      end

      def handle

        langs = Global.read_config('pf2e_languages', self.type)

        template = PF2LanguageInfoTemplate.new(langs, self.type)

        client.emit template.render

      end

    end
  end
end
