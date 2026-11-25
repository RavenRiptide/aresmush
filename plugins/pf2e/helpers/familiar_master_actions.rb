module AresMUSH
  module Pf2e
    module Familiar

      # Master abilities a familiar uses in an encounter to give its master something (Player Core p. 214):
      #
      #   Familiar Focus         2 actions, once a day: its master regains 1 Focus Point, up to their maximum
      #   Restorative Familiar   2 actions, once a day: its master regains (half their level, at least 1)d8 HP
      #
      # Each is an action on the familiar's stat block while its master has the ability today, run by a row in
      # `MonsterAbilities`. The day's use is counted on the master's encounter state, since the familiar's
      # record is made anew each time it joins; a fresh encounter starts rested, and one carried on carries it.
      module MasterActions

        FOCUS = 'Familiar Focus'.freeze
        RESTORATIVE = 'Restorative Familiar'.freeze

        ACTIONS = { FOCUS => { 'cost' => 2 }, RESTORATIVE => { 'cost' => 2 } }.freeze
        TRAITS = [ 'concentrate' ].freeze
        PER = 'day'.freeze

        # The stat block's entries for the actions its master has today.
        def self.actions(state)
          ACTIONS.select { |name, _row| Daily.master_ability?(state, name) }.map do |name, row|
            { 'name' => name, 'type' => 'action', 'cost' => row['cost'], 'traits' => TRAITS,
              'text' => (Daily.catalogue[name] || {})['shortdesc'].to_s }
          end
        end

        # MonsterAbilities' refusal: a master to give it to, today's use not yet spent, and for Familiar
        # Focus, a focus pool short of full.
        def self.refusal(use)
          state = use.actor.holder.master
          return Err.new(:familiar_no_master, 'pf2e.familiar_action_no_master', 'action' => use.name) unless state

          if TurnState.used(state, use.name).positive? && !Combatants.gm?(use.scene.enactor, use.scene.encounter)
            return Err.new(:familiar_used_today, 'pf2e.familiar_action_used', 'name' => use.actor.label, 'action' => use.name)
          end

          return nil unless use.name == FOCUS

          magic = state.magic
          max = magic ? Pf2emagic.focus_pool_max(magic) : 0
          return Err.new(:familiar_no_pool, 'pf2e.familiar_focus_no_pool', 'master' => master_label(use)) if max.zero?
          return nil if Pf2emagic.focus_points_left(magic) < max

          Err.new(:familiar_pool_full, 'pf2e.familiar_focus_full', 'master' => master_label(use), 'max' => max)
        end

        # MonsterAbilities' run: what its master regains, and the day's use counted on them.
        def self.run(use)
          state = use.actor.holder.master

          if use.name == FOCUS
            now = regain_focus(state)
            use.out['lines'] << Telling.event('pf2e.familiar_focus_restored', :master => master_label(use), :current => now,
                                                                              :max => Pf2emagic.focus_pool_max(state.magic))
          else
            thrown = Pf2e.thrown_formula(restorative_dice(state))
            amount = Harm.heal(state, thrown['total'])
            use.out['lines'] << Acting.healed(master_label(use), amount, thrown['shown'])
            use.out['gm'] << Telling.event('pf2e.act_hp_left', 'target' => master_label(use), 'hp' => Harm.hit_points(state))
          end

          TurnState.count_use(state, use.name, PER)
        end

        # One Focus Point back, up to their maximum. Answers how many they now have. Patron's Claim gives
        # one too.
        def self.regain_focus(state)
          magic = state.magic
          now = [ Pf2emagic.focus_points_left(magic) + 1, Pf2emagic.focus_pool_max(magic) ].min
          magic.update(:focus_pool => { 'current' => now })

          now
        end

        # 1d8 times half their level, at least 1d8.
        def self.restorative_dice(state)
          "#{[ state.pf2_level.to_i / 2, 1 ].max}d8"
        end

        def self.master_label(use)
          Combatants.turn_name(use.scene.encounter, use.actor.label)
        end
      end
    end
  end
end
