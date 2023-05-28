module AresMUSH
  module Tinker
    class TinkerCmd
      include CommandHandler
      
      def check_can_manage
        return t('dispatcher.not_allowed') if !enactor.has_permission?("tinker")
        return nil
      end
      
      def handle
        char = Character.find_one_by_name("Testchar")
        
        feat_list = char.pf2_feats.values
        
        client.emit feat_list
        
        
      end

    end
  end
end
