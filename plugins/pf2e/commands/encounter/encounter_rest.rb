module AresMUSH
  module Pf2e

    # `+e/rest [<combatant>,<combatant>...]` - the GM says a night has passed for everyone in the encounter
    # here, or for those named: each gets a night's rest and the day's preparations (`Pf2e.rest`). As often
    # as the story needs; a mistaken one is taken back with `+e/undo`.
    class PF2EncounterRestCmd
      include CommandHandler

      attr_accessor :names

      def parse_args
        self.names = cmd.args.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        resting = resting(encounter)

        return if resting.nil?
        return client.emit_failure(t('pf2e.rest_nobody')) if resting.empty?

        resting.each { |one| Pf2e.rest(one.holder) }

        message = t('pf2e.rest_done', :name => enactor.name, :who => resting.map(&:label).join(', '))

        Pf2e::Encounters::Announce.tell(PF2Encounter[encounter.id], message, :room => enactor_room, :story => true)
      end

      # The characters named, or every character in the encounter. A creature does not prepare.
      def resting(encounter)
        return Combatants.all(encounter).reject(&:creature?).select(&:holder) if self.names.empty?

        found = self.names.map { |name| Combatants.find(encounter, name) }
        failed = found.find(&:err?)

        return nil if failed && CharState.emit_error!(client, failed)

        creature = found.map(&:state).find(&:creature?)

        if creature
          client.emit_failure t('pf2e.rest_creature', :ref => creature.ref)
          return nil
        end

        found.map(&:state)
      end
    end

    # `encounter/reprepare <combatant>` - the GM says a character has spent the time a feat asks to make
    # some of their daily choices again: Ultimate Flexibility's hour of training for their flexibility
    # feats, Radiant Armament's ten minutes for their blessed armament's rune. Only a GM: the time is the
    # story's, and so is whether they have already spent a limited use they would be giving up. Not named
    # for Retraining, the downtime activity, which it has nothing to do with.
    class PF2EncounterReprepareCmd
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
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        found = Combatants.find(encounter, self.who)

        return if CharState.emit_error!(client, found)
        return client.emit_failure(t('pf2e.rest_creature', :ref => found.state.ref)) if found.state.creature?

        outcome = DailyChoices.reopen!(found.state.holder)

        return if CharState.emit_error!(client, outcome)

        switches = outcome.state['switches'].map { |switch| "prepare/#{switch}" }.join(', ')
        message = t('pf2e.reprepare_done', :name => enactor.name, :who => found.state.label, :switches => switches)

        Pf2e::Encounters::Announce.tell(PF2Encounter[encounter.id], message, :room => enactor_room, :story => true)
      end
    end

    # `encounter/gather <combatant>[=<periods>]` - the GM says an alchemist has spent so many 10-minute
    # periods in exploration gathering reagents, one by default: each gives back vials, up to their maximum.
    # Only a GM, because the time spent is the story's.
    class PF2EncounterGatherCmd
      include CommandHandler

      attr_accessor :who, :periods

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_optional_arg2)

        self.who = trim_arg(args.arg1)
        self.periods = args.arg2.to_s.strip.empty? ? 1 : integer_arg(args.arg2)
      end

      def required_args
        [ self.who ]
      end

      def check_periods
        return nil if self.periods.to_i.positive?
        return t('pf2e.gather_bad_periods')
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        found = Combatants.find(encounter, self.who)

        return if CharState.emit_error!(client, found)
        return client.emit_failure(t('pf2e.rest_creature', :ref => found.state.ref)) if found.state.creature?

        outcome = Alchemy.gather!(found.state.holder, self.periods)

        return if CharState.emit_error!(client, outcome)

        message = t('pf2e.gather_done', :name => enactor.name, :who => found.state.label,
                                        :gained => outcome.state['gained'], :left => outcome.state['left'])

        Pf2e::Encounters::Announce.tell(PF2Encounter[encounter.id], message, :room => enactor_room, :story => true)
      end
    end

    # `+e/refocus [<combatant>]` - Refocus: a Focus Point back, or more for those whose feats say so. The GM
    # may refocus anyone; a player refocuses themselves.
    class PF2EncounterRefocusCmd
      include CommandHandler

      attr_accessor :who

      def parse_args
        self.who = trim_arg(cmd.args)
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter

        gm = Combatants.gm?(enactor, encounter)

        return client.emit_failure(t('pf2e.not_organizer')) if self.who && !gm

        found = Combatants.find(encounter, self.who || enactor.name)

        return if CharState.emit_error!(client, found)

        holder = found.state.holder
        before = holder.magic ? holder.magic.focus_pool['current'].to_i : 0
        refused = Pf2emagic.do_refocus(holder, gm)

        return client.emit_failure(refused) if refused

        after = Combatants.find(encounter, found.state.ref).state.holder.magic.focus_pool['current'].to_i
        restored = after - before

        client.emit_success t(restored == 1 ? 'pf2emagic.refocus_ok_one' : 'pf2emagic.refocus_ok_many', :points => restored)
      end
    end
  end
end
