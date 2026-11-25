module AresMUSH
  module Pf2e
    module Companion

      # An animal companion acting in an encounter (Player Core pp. 206-207, and the minion trait). It has no
      # turn of its own: it acts on its master's, with the 2 actions Command an Animal gives it (3 when its
      # master spends 2 actions with Companion's Cry), or, once mature, 1 action of its own without a Command,
      # to Strike or Stride (or Burrow, Climb, Fly or Swim with that Speed). Once it has used that action it
      # can't be Commanded that round. Command a Minion Commands it as Command an Animal does, since it has the
      # minion trait, but only Command an Animal takes Companion's Cry.
      #
      # The GM may have it do anything. A player is refused what the rules don't let it do.
      module Minion

        COMMAND = 'Command an Animal'.freeze
        # Command a Minion as a string: familiar_minion.rb, which names it too, loads after this file.
        COMMANDS = [ COMMAND, 'Command a Minion' ].freeze
        COMMANDED = 2
        CRY = "Companion's Cry".freeze
        CRIED = 3
        OWN_ACTIONS = [ 'Stride' ].freeze
        # A move it may make with its own action where it has the Speed.
        MOVES = { 'Burrow' => 'burrow', 'Climb' => 'climb', 'Fly' => 'fly', 'Swim' => 'swim' }.freeze
        VERBS = %w{act strike}.freeze

        # The actions a Command gave it this turn, or 0.
        def self.commanded(npc)
          TurnState.turn(npc)['commanded'].to_i
        end

        def self.commanded?(npc)
          commanded(npc).positive?
        end

        def self.feats(npc)
          char = npc.master&.character
          char ? Companion.held(char, :draft => false) : []
        end

        # A Mature feat or Imposing Destrier: 1 action of its own without a Command.
        def self.independent?(npc)
          feats(npc).any? { |_name, details| details['companion_independent'].to_i.positive? }
        end

        def self.cry?(npc)
          feats(npc).any? { |name, _details| name.casecmp?(CRY) }
        end

        # The actions its turn holds: what a Command gave it, or 1 of its own once mature, or none.
        def self.turn_actions(npc)
          return commanded(npc) if commanded?(npc)

          independent?(npc) ? 1 : 0
        end

        # It acted on its own this round, which ends what it can be given.
        def self.acted_alone?(npc)
          !commanded?(npc) && TurnState.turn(npc)['actions'].to_i.positive?
        end

        # The one combatant a Command is aimed at, where it is the actor's own companion; nil otherwise, and
        # Command an Animal at any other animal is the general action, with its Nature check.
        def self.commanded_one(actor, name, targets)
          return nil unless COMMANDS.include?(name) && targets.size == 1

          target = targets.first
          own = target.holder && Actors.of(target.holder).minion_kind == 'companion' && target.master.to_i == actor.number.to_i
          own ? target : nil
        end

        # `actions` is what its master spends on the Command: 1, or 2 with Companion's Cry.
        def self.command_refusal(npc, label, name, actions)
          return Err.new(:command_again, 'pf2e.companion_command_again', 'name' => label) if commanded?(npc)
          return Err.new(:command_after_own, 'pf2e.companion_command_after_own', 'name' => label) if acted_alone?(npc)
          return nil if actions == 1
          return Err.new(:command_actions, 'pf2e.companion_command_actions', 'action' => name) unless actions == 2 && name == COMMAND
          return nil if cry?(npc)

          Err.new(:command_cry, 'pf2e.companion_command_cry', 'name' => label)
        end

        def self.command!(npc, actions)
          TurnState.write(npc, 'turn' => TurnState.turn(npc).merge('commanded' => actions))
        end

        # What a player may not have it do: anything but act or Strike, act outside their turn or past its
        # actions, use a reaction, or, on its own action, anything but Strike, Stride or a Speed it has. `term`
        # is the action as typed, nil for a Strike.
        #
        # Exploration has no turns, so there it needs neither its master's turn nor a Command.
        def self.player_refusal(encounter, combatant, verb, term)
          npc = combatant.holder
          label = combatant.label

          return Err.new(:companion_verb, 'pf2e.companion_act_only', 'name' => label, 'ref' => combatant.ref) unless VERBS.include?(verb)

          turn = Minions.turn_refusal(encounter, combatant, 'pf2e.companion_not_commanded')
          return turn if turn
          return Spells.must_support_refusal(npc, label, nil) || Support.refusal(npc, label, nil, verb) if verb == 'strike'

          typed = term.to_s.split('=').first.to_s.split('/').first.to_s.strip
          own = typed.empty? ? nil : Actors.of(npc).own_ability(typed)
          found = own.nil? && !typed.empty? ? Actions.find(typed) : nil
          return nil unless own || found&.ok?

          # One of its own actions (Support, its advanced maneuver) by its stat block's name, or a catalogue action.
          name = own ? own['name'] : found.state
          type = own ? own['type'] : Actions.info(name)['type']
          return Err.new(:companion_reaction, 'pf2e.companion_no_reactions', 'name' => label) if type == 'reaction'

          must = Spells.must_support_refusal(npc, label, name)
          return must if must

          supported = Support.refusal(npc, label, name, verb)
          return supported if supported

          ridden = Riding.minion_refusal(npc, label, name)
          return ridden if ridden

          limited = own_limits(npc, label, name, own)
          return limited if limited
          return nil if Exploration.exploring?(encounter) || commanded?(npc) || own_action?(npc, name)

          Err.new(:companion_own_action, 'pf2e.companion_own_action_only', 'name' => label, 'action' => name)
        end

        # A maneuver used as often as its words allow (Fire Breath, once per hour), and a raging badger's
        # concentrate actions, which it can't use except to Seek.
        def self.own_limits(npc, label, name, own)
          frequency = own ? CreatureAbilities.frequency(own['text']) : nil
          if frequency && TurnState.used(npc, name) >= frequency['max'].to_i
            return Err.new(:maneuver_spent, 'pf2e.companion_maneuver_spent', 'name' => label, 'action' => name, 'per' => frequency['per'])
          end

          return nil unless Maneuvers.raging?(npc) && name != 'Seek'

          traits = own ? Array(own['traits']) : Array(Actions.info(name)['traits'])
          traits.map(&:to_s).map(&:downcase).include?('concentrate') ? Err.new(:raging, 'pf2e.companion_raging_concentrate', 'name' => label, 'action' => name) : nil
        end

        def self.own_action?(npc, name)
          return true if OWN_ACTIONS.include?(name)

          speed = MOVES[name]
          !speed.nil? && (npc.stat_block['speeds'] || {})[speed].to_i.positive?
        end
      end
    end
  end
end
