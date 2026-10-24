module AresMUSH
  module Chargen
    def self.custom_approval(char)

      # What a character invests each day is invested from the start. Everything else a day's
      # preparations give them comes with their first encounter.
      Pf2e.do_daily_investiture(char)

      # If you don't want to have any custom approval steps, just leave this blank.

      # Otherwise, do what you need to do.  Here's an example of how to add
      # someone to a role based on their faction:
      #
      #  faction = char.group("Faction")
      #  role = Role.find_by_name(faction)
      #
      #  if (role)
      #    char.roles.add role
      #  end
      #
      # See https://www.aresmush.com/tutorials/config/chargen.html for details.
    end
  end
end
