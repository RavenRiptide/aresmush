module AresMUSH
  module Pf2noms

    def self.calculate_current_alts(player)
      altlist = player.characters

      # Staff bits register to receive RPP but are not counted as alts.

      altlist.select { |a| !(a.is_admin?) }.size
    end

    def do_nom_refresh(char)
      player = char.player

      return nil unless player

      noms_for_week = Global.read_config('pf2noms', 'noms_per_week')

      player.update(nomlist: [])
      player.update(totalnoms: noms_for_week)

    end

  end
end
