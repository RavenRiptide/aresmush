module AresMUSH
  module Pf2e

    # `encounter/poison <weapon>=<poison>` - applies an injury poison you carry to a weapon you wield. It
    # waits on the weapon for your first Strike with it that hits. Two actions for most poisons, as each
    # says; one with Poison Weapon, or for a Toxicologist.
    class PF2EncounterPoisonCmd
      include CommandHandler

      attr_accessor :weapon, :poison

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.weapon = trim_arg(args.arg1)
        self.poison = trim_arg(args.arg2)
      end

      def required_args
        [ self.weapon, self.poison ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter

        found = Combatants.find(encounter, enactor.name)

        return client.emit_failure(t('pf2e.encounter_gear_not_in')) unless found.ok? && found.state.holder

        actor = found.state
        stopped = Restraints.refusal(actor, 'Interact', [ 'manipulate' ])

        return CharState.emit_error!(client, stopped) if stopped

        applied = WeaponPoison.apply!(actor.holder, self.weapon, self.poison)

        return if CharState.emit_error!(client, applied)

        TurnState.spend(actor.holder, 'Interact', :cost => applied.state['cost'], :type => 'action')

        message = t('pf2e.poison_applied', :name => enactor.name, :weapon => applied.state['weapon'],
                                           :poison => applied.state['poison'], :actions => Actions::COSTS[applied.state['cost'].clamp(1, 3)])

        Pf2e::Encounters::Announce.tell(PF2Encounter[encounter.id], message, :room => enactor_room, :story => true)
      end
    end

    # `encounter/spray <who>` - a Toxicologist's Greater Field Discovery: the poison a creature just failed
    # its initial save against sprays onto another creature next to it, whom you name. The game can't see
    # who is next to whom, so that is yours and the GM's to judge. Gone at the end of your turn if unused.
    class PF2EncounterSprayCmd
      include CommandHandler

      attr_accessor :who

      def parse_args
        self.who = trim_arg(cmd.args)
      end

      def required_args
        [ self.who ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter

        actor = Combatants.find(encounter, enactor.name)

        return client.emit_failure(t('pf2e.encounter_gear_not_in')) unless actor.ok? && actor.state.holder

        target = Combatants.find(encounter, self.who)

        return if CharState.emit_error!(client, target)

        out = Acting.report
        sprayed = WeaponPoison.spray!(Acting::Scene.new(encounter, actor.state, target.state, nil, true), out)

        return if CharState.emit_error!(client, sprayed)

        Pf2e::Encounters::Announce.tell(PF2Encounter[encounter.id], Telling.lines(out['lines']).join('%r'),
                                        :room => enactor_room, :story => true)
      end
    end
  end
end
