module AresMUSH
  module Tinker
    class TinkerCmd
      include CommandHandler
      
      def check_can_manage
        return t('dispatcher.not_allowed') if !enactor.has_permission?("tinker")
        return nil
      end
      
      def handle
        if (args = cmd.to_s.match(/^tinker\/(.*)\s(.*)=(.*)\/(\d+)\/(\d+)$/))
            client.emit_success "#{cmd}"
        else
            client.emit_failure "#{cmd}"
        end
      end

    end
  end
end
