module AresMUSH
  module Pf2e

    # What the web portal draws of an encounter: the same data the `+e` commands read, as JSON.
    module EncounterWeb

      # MUSH markup as plain text, for a page that styles it itself.
      def self.plain(text)
        AnsiFormatter.strip_ansi(MushFormatter.format(text.to_s)).gsub(/\r?\n/, "\n")
      end

      def self.combatant(encounter, one, viewer, gm)
        holder = one.holder
        number = one.number.to_s

        { id: one.number, name: one.label, initiative: one.init.to_i, creature: one.creature?,
          conditions: holder ? Pf2e.condition_labels(holder, false) : [],
          effects: holder ? ActiveEffects.on(holder).map { |effect| "#{effect.name} (#{plain(ActiveEffects.remaining(effect))})" } : [],
          cover: (encounter.cover || {})[number], concealment: (encounter.concealment || {})[number],
          hp: hit_points_seen(holder, viewer, gm),
          turn: holder ? plain(TurnState.summary(holder)) : nil }
      end

      # The GM sees everyone's. A creature's are the GM's alone. A character's are on their combat sheet,
      # so whoever may see that - the sheet's own rule, `Sheet.viewable?` - may see them here.
      def self.hit_points_seen(holder, viewer, gm)
        return nil unless holder
        return Harm.hit_points(holder) if gm
        return nil if Actors.of(holder).creature? || viewer.nil?

        Sheet.viewable?(viewer, holder, 'combat').ok? ? Harm.hit_points(holder) : nil
      end
    end

    # `pf2Encounter` - an encounter's order, each combatant's id, conditions, cover and counts, and its log.
    class PF2EncounterHandler
      def handle(request)
        error = Website.check_login(request, true)
        return error if error

        encounter = PF2Encounter[request.args['id']]

        return { error: t('webportal.not_found') } unless encounter

        enactor = request.enactor
        gm = enactor ? Combatants.gm?(enactor, encounter) : false
        listed = Combatants.all(encounter)

        { id: encounter.id, round: encounter.round.to_i, active: encounter.is_active,
          current: ActiveEffects.current_turn(encounter), organizer: encounter.organizer, gm: gm,
          trusted: Array(encounter.trusted), difficulty: EncounterWeb.plain(Difficulty.shown(encounter)),
          combatants: listed.map { |one| EncounterWeb.combatant(encounter, one, enactor, gm) },
          log: Array(encounter.messages).last(30).map { |_time, message| EncounterWeb.plain(message) } }
      end
    end

    # `pf2Actions` - the actions the viewer can use, by mode of play, with what each rolls.
    class PF2ActionsHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        char = request.enactor

        modes = Actions::MODES.keys.each_with_object({}) do |mode, out|
          out[mode] = Actions.available(char, mode).map do |name|
            entry = Actions.info(name)
            check = entry['check'] || {}

            { name: name, cost: Actions.cost(name), traits: Array(entry['traits']),
              rolls: Array(check['statistic']).join(' or '), against: check['against'] || check['dc'],
              effect: entry['self_effect'], description: EncounterWeb.plain(entry['description']) }
          end
        end

        { modes: modes }
      end
    end

    # `pf2LastRoll` - every modifier of the viewer's last roll in an encounter, as `+e/why` shows it.
    class PF2LastRollHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        { lines: Telling.lines(request.enactor.pf2_last_roll).map { |line| EncounterWeb.plain(line) } }
      end
    end
  end
end
