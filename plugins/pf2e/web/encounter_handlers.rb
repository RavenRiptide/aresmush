module AresMUSH
  module Pf2e

    # What the web portal draws of an encounter: the same data the `+e` commands read, as JSON.
    module EncounterWeb

      # MUSH markup as plain text, for a page that styles it itself, without the line break the formatter
      # ends everything with.
      def self.plain(text)
        AnsiFormatter.strip_ansi(MushFormatter.format(text.to_s)).gsub(/\r?\n/, "\n").chomp
      end

      # The log's last lines, each with its text in the game's colours, for the page's AnsiFormat, a line
      # the game told marked with its prefix at the reader's level. An encounter notice - `start`, `end`,
      # `round` or `turn` - also has its notice details, for the page to lay out as its own.
      def self.log(encounter, viewer = nil, last = 30)
        EncounterLog.lines(encounter, last).map do |_time, message, notice, notice_details, line|
          text = line ? SystemPrefix.for(viewer, message, line) : message

          # The formatter ends every message with a line break, which a line of the page does not need.
          { notice: notice, text: Website.format_output_for_html(text.to_s).chomp, notice_details: notice_details }.compact
        end
      end

      # Every change in the encounter, with whether it has been taken back and who spent a Hero Point in it.
      def self.history(encounter)
        at = History.at(encounter)

        History.listed(encounter).map do |entry|
          { seq: entry['seq'], said: entry['said'], undone: entry['seq'] > at, heroes: entry['heroes'] }
        end
      end

      # Everyone in the order, each familiar and animal companion straight after its master, as `+e/view` lists them.
      def self.listed(encounter)
        everyone = Combatants.all(encounter)
        minions, others = everyone.partition(&:minion?)
        placed = others.flat_map { |one| [ one ] + minions.select { |minion| minion.master.to_i == one.number } }

        placed + (minions - placed)
      end

      def self.combatant(encounter, one, viewer, gm)
        holder = one.holder
        number = one.number.to_s

        # A familiar or companion has no initiative: it acts on its master's turn.
        { id: one.number, name: one.label, initiative: one.minion? ? nil : one.init.to_i, minion: one.minion?, creature: one.creature?,
          lines: lines(encounter, one),
          conditions: holder ? Pf2e.condition_labels(holder, false) : [],
          effects: holder ? ActiveEffects.on(holder).map { |effect| "#{effect.name} (#{plain(ActiveEffects.remaining(effect))})" } : [],
          cover: (encounter.cover || {})[number], concealment: (encounter.concealment || {})[number],
          hp: hit_points_seen(holder, viewer, gm), hero_points: hero_points_seen(encounter, holder, viewer, gm),
          turn: holder ? turn(encounter, holder) : nil,
          shapes: gm && one.creature? && holder ? Shapes.shown(holder) : nil }.compact
      end

      # What is said beneath a combatant's name: whose familiar or companion it is, who rides whom, and the prey a
      # ranger hunts or their companion shares.
      def self.lines(encounter, one)
        holder = one.holder
        return [] unless holder

        kind = Actors.of(holder).minion_kind
        owner = kind ? holder.master&.name : nil
        lines = []

        if owner
          key = if kind == 'companion' then 'pf2e.view_companion_of'
                elsif holder.stat_block['pet'] then 'pf2e.view_pet_of'
                else 'pf2e.view_familiar_of'
                end
          lines << t(key, :char => owner)
        end

        riding = Companion::Riding.view_line(holder)
        lines << riding if riding

        prey = HuntPrey.prey(holder)
        if prey
          row = Combatants.rows(encounter).find { |found| found['name'] == prey }
          lines << t('pf2e.view_hunting', :target => row ? "#{prey} (##{row['id']})" : prey)
        end

        if owner && ActiveEffects.on(holder).any? { |effect| (effect.mark || {})['slug'] == HuntPrey::SHARE_SLUG }
          lines << t('pf2e.view_sharing_hunt', :char => owner)
        end

        lines
      end

      # What they have done this turn, and who they share the multiple attack penalty with, where the penalty
      # counts a rider's or a mount's attacks too.
      def self.turn(encounter, holder)
        summary = plain(TurnState.summary(holder))
        return summary unless Companion::Riding.shared_attacks(holder).positive?

        partner = Companion::Riding.partner_of(holder)
        row = partner ? Companion::Riding.row_of(encounter, partner) : nil
        row ? t('pf2e.turn_shared', :summary => summary.chomp('.'), :name => row['name']) : summary
      end

      # The GM sees everyone's. Anyone else sees how hurt a creature looks. A character's are on their combat
      # sheet, and every sheet is open, so anyone logged in sees them, and so are a familiar's and a companion's.
      def self.hit_points_seen(holder, viewer, gm)
        return nil unless holder
        return Harm.hit_points(holder) if gm
        return Harm.looks(holder) if Actors.of(holder).creature? && Actors.of(holder).minion_kind.nil?
        return nil if viewer.nil?

        Harm.hit_points(holder)
      end

      # A character's Hero Points in the encounter's scene, for whoever may see their hit points.
      def self.hero_points_seen(encounter, holder, viewer, gm)
        scene = encounter.scene

        return nil unless holder && scene && !Actors.of(holder).creature?
        return nil unless gm || viewer

        HeroPoints.held(scene, HeroPoints.character(holder))
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
        listed = EncounterWeb.listed(encounter)

        page = { id: encounter.id, round: encounter.round.to_i, active: encounter.is_active,
                 current: ActiveEffects.current_turn(encounter), organizer: PF2Encounter.gm_of(encounter)&.name || encounter.organizer, gm: gm,
                 trusted: Array(encounter.trusted),
                 history: EncounterWeb.history(encounter),
                 combatants: listed.map { |one| EncounterWeb.combatant(encounter, one, enactor, gm) },
                 log: EncounterWeb.log(encounter, enactor) }

        # The difficulty is the GM's alone, so it is not sent to anyone else.
        page[:difficulty] = EncounterWeb.plain(Difficulty.shown(encounter)).strip if gm
        page
      end
    end

    # `pf2SceneEncounter` - the encounter running in a scene, `{ scene_id }`, for the scene's page to link
    # to: `{ id, exploring }`, or nothing where none runs or the viewer may not read the scene.
    class PF2SceneEncounterHandler
      def handle(request)
        error = Website.check_login(request, true)
        return error if error

        scene = Scene[request.args['scene_id']]
        return {} unless scene && Scenes.can_read_scene?(request.enactor, scene)

        running = PF2Encounter.scene_active_encounter(scene)
        running ? { id: running.id, exploring: Exploration.exploring?(running) } : {}
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
