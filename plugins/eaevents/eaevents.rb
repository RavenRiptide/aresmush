$:.unshift File.dirname(__FILE__)

module AresMUSH

  # Emblem of Ea's additions to the stock events plugin: a player limit with a waitlist, a
  # death-consent flag, and each sign-up's level and class.
  #
  # The stock plugin still owns events and sign-ups. This plugin adds two attributes to Event and
  # works out the roster and waitlist from the order people signed up, so nothing is stored twice.
  # The stock commands, web handlers, and templates call in here at the few points where they
  # need to know about the limit (each such call is marked "Emblem of Ea: Custom Ares change").
  #
  # The folder is `eaevents`, not `ea_events`: the plugin loader matches a folder to its module
  # ignoring case but not underscores.
  module EaEvents

    def self.plugin_dir
      File.dirname(__FILE__)
    end

    def self.shortcuts
      {}
    end

    # The stock plugin answers `event` with every switch it knows and nil for the rest, so these
    # two reach this plugin whichever is asked first.
    def self.get_cmd_handler(client, cmd, enactor)
      return nil if cmd.root != "event"

      case cmd.switch
      when "limit"
        return EventLimitCmd
      when "consent"
        return EventConsentCmd
      end

      nil
    end

    def self.get_event_handler(event_name)
      nil
    end

    def self.get_web_request_handler(request)
      nil
    end
  end
end
