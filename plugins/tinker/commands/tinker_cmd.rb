module AresMUSH
  module Tinker
    class TinkerCmd
      include CommandHandler
      
      def check_can_manage
        return t('dispatcher.not_allowed') if !enactor.has_permission?("tinker")
        return nil
      end
      
      def handle
      
        char = Character.named("Testchar")
        
        player = char.player
        
        # email = player.email
        
        client.emit [char, player].join(" -- ")
        
      end

    end
  end
end
