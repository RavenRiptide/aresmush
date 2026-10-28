module AresMUSH
  module Scenes
    class AutospaceCmd
      include CommandHandler

      # Emblem of Ea: after added, for autospace/after.
      attr_accessor :option, :after

      def parse_args
        self.option = trim_arg(cmd.args)
        self.after = cmd.switch_is?("after")
      end

      def handle

        # Emblem of Ea: autospace/after sets pose_autospace_after, with its own messages.
        if (self.after)
          if (!self.option)
            enactor.update(pose_autospace_after: nil)
            message = t('scenes.autospace_after_cleared')
          else
            enactor.update(pose_autospace_after: self.option)
            formatted = Scenes.format_autospace(enactor, self.option)
            message = t('scenes.autospace_after_set', :option => formatted)
          end
        elsif (!self.option)
          enactor.update(pose_autospace: nil)
          message = t('scenes.autospace_cleared')
        else
          enactor.update(pose_autospace: self.option)
          formatted = Scenes.format_autospace(enactor, self.option)
          message = t('scenes.autospace_set', :option => formatted)
        end

        client.emit_success message
        AresCentral.warn_if_setting_linked_preference(client, enactor)
      end
    end
  end
end
