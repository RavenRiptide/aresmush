$:.unshift File.dirname(__FILE__)

module AresMUSH
  module Pf2noms

    def self.plugin_dir
      File.dirname(__FILE__)
    end

    def self.shortcuts
      Global.read_config("pf2noms", "shortcuts")
    end

    def self.get_cmd_handler(client, cmd, enactor)
      case cmd.root
      when "dmnom"
        case cmd.switch
        when "all"
          return PF2DMNomAllCommand
        else
          return PF2DMNomCommand
        end
      when "nom"
        return PF2NomCommand
      when "noms"
        return PF2NomDisplayCommand
      when "rpp"
        case cmd.switch
        when "award"
          return PF2AwardRPPCmd
        when "spend"
          return PF2SpendRPPCmd
        when nil
          return PF2RPPCmd
        end
      when "rpphist", "listrpp"
        return PF2RPPHistCmd
      end

      nil
    end

    def self.get_event_handler(event_name)
      case event_name
      when "CronEvent"
        return NomCronEventHandler
      end
      nil
    end

    def self.get_web_request_handler(request)
      nil
    end

  end
end
