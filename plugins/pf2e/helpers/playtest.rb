module AresMUSH
  module Pf2e

    # Whether the playtest's self-service commands - selfaward/xp, selfaward/gold, selfapprove -
    # answer at all. Off on a live game, where staff award and approve.
    def self.playtest?
      Global.read_config('pf2e', 'playtest') == true
    end

    # GM Core's lump sum for a new character of a level (Treasure for New Characters), in copper,
    # less the starting money every character already holds.
    def self.playtest_wealth_owed(level)
      gp = (Global.read_config('pf2e', 'playtest_wealth') || {})[level.to_i]

      return 0 unless gp

      [ Pf2egear.convert_money(gp.to_i, 'gp') - Pf2egear::STARTING_MONEY, 0 ].max
    end
  end
end
