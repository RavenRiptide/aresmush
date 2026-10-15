module AresMUSH
  module Pf2e

    # What the web portal draws of the creatures: the library of saved ones and the bestiary, and one
    # creature's stat block. The same rules as the `creature` commands decide what each viewer sees.
    module CreatureWeb

      PAGE = 50

      def self.saved_summary(char, creature)
        actor = CreatureAccess.actor(char)
        row = Creatures.row(creature)
        shown = Creatures.shown(char, Creatures.ref(char, creature))
        can = %w{view use edit clone share submit review retire}.to_h { |action| [ action, CreatureAccess.may(actor, action, row).ok? ] }

        { ref: "saved:#{creature.id}", source: 'saved', id: creature.id, name: creature.name, level: shown&.block&.dig('level').to_i,
          traits: Array(shown&.block&.dig('traits')), owner: creature.owner_name, mine: CreatureAccess.owner?(actor, row),
          status: creature.status, audience: creature.audience || 'private', revision: shown&.number, latest: creature.head&.number,
          published_revision: creature.published&.number, can: can }
      end

      def self.bestiary_summary(char, name, listed)
        { ref: "bestiary:#{name}", source: 'bestiary', name: name, level: listed['level'].to_i, traits: Array(listed['traits']),
          pack: listed['pack'], addable: Gm.open?(char, name) }
      end

      # A stat block as the lines `+e/creature` prints, as plain text.
      def self.lines(name, block)
        StatBlock.lines(name, block).map { |line| EncounterWeb.plain(line) }
      end

      def self.matches?(summary, words, from, to)
        (words.empty? || Domains.slug(summary[:name]).include?(Domains.slug(words))) &&
          (from.nil? || summary[:level] >= from) && (to.nil? || summary[:level] <= to)
      end

      def self.number(value)
        value.to_s.strip.match?(/\A-?\d+\z/) ? value.to_i : nil
      end
    end

    # `pf2Creatures` - the library: `{ scope, words, level_from, level_to, page }`. Scopes are mine, shared,
    # published and bestiary, and all for an admin.
    class PF2CreaturesHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        char = request.enactor
        actor = CreatureAccess.actor(char)
        scopes = %w{mine shared published bestiary} + (CreatureAccess.admin?(actor) ? [ 'all' ] : [])
        scope = scopes.include?(request.args['scope']) ? request.args['scope'] : 'mine'
        words = request.args['words'].to_s.strip
        from = CreatureWeb.number(request.args['level_from'])
        to = CreatureWeb.number(request.args['level_to'])

        listed = scope == 'bestiary' ? bestiary(char) : saved(char, actor, scope)
        listed = listed.select { |one| CreatureWeb.matches?(one, words, from, to) }.sort_by { |one| [ one[:level], one[:name] ] }
        page = [ request.args['page'].to_i, 1 ].max

        { scope: scope, scopes: scopes, total: listed.size, page: page, pages: [ (listed.size + CreatureWeb::PAGE - 1) / CreatureWeb::PAGE, 1 ].max,
          creatures: listed.drop((page - 1) * CreatureWeb::PAGE).first(CreatureWeb::PAGE),
          can_create: CreatureAccess.may(actor, 'create').ok?, runs_own: CreatureAccess.runs_own?(actor),
          open_bestiaries: Gm.open_bestiaries }
      end

      def bestiary(char)
        Bestiary.index.map { |name, listed| CreatureWeb.bestiary_summary(char, name, listed) }
      end

      def saved(char, actor, scope)
        Creatures.allowed(char, 'view').select do |creature|
          row = Creatures.row(creature)
          mine = CreatureAccess.owner?(actor, row)

          case scope
          when 'mine' then mine
          when 'shared' then !mine && CreatureAccess.reaches?(actor, row)
          when 'published' then CreatureAccess.published?(row)
          else true
          end
        end.map { |creature| CreatureWeb.saved_summary(char, creature) }
      end
    end

    # `pf2Creature` - one creature, `{ ref }` as `saved:12` or `bestiary:Goblin Warrior`: its stat block, how
    # to add it, and for its author its notes, what an admin said, and its history.
    class PF2CreatureHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        char = request.enactor
        source, _, key = request.args['ref'].to_s.partition(':')

        return bestiary(char, key) if source == 'bestiary'

        found = Creatures.find(char, "c:#{key}", 'view')

        return { error: t('pf2e.creature_web_not_found') } if found.err?

        creature = found.state['creature']
        summary = CreatureWeb.saved_summary(char, creature)
        shown = Creatures.shown(char, found.state)
        mine = summary[:can]['edit']

        { creature: summary, lines: CreatureWeb.lines(creature.name, shown.block), add: "+e/add c:#{creature.id}",
          addable: Creatures.usable?(char, Creatures.ref(char, creature)),
          notes: mine ? creature.notes : nil, review_note: mine ? creature.review_note : nil,
          history: mine ? history(creature) : [] }
      end

      def bestiary(char, name)
        named = Bestiary.named(name)

        return { error: t('pf2e.creature_web_not_found') } unless named

        summary = CreatureWeb.bestiary_summary(char, named, Bestiary.index[named])

        { creature: summary, lines: CreatureWeb.lines(named, Bestiary.entry(named)), add: "+e/add #{named}", addable: summary[:addable],
          notes: nil, review_note: nil, history: [] }
      end

      def history(creature)
        creature.events.to_a.sort_by { |one| [ one.created_at.to_s, one.id.to_i ] }.map do |one|
          summary = one.revision ? creature.revisions.to_a.find { |revision| revision.number == one.revision }&.summary : nil

          { at: one.created_at.to_s[0, 16], by: one.by, kind: one.kind, revision: one.revision, summary: summary }
        end
      end
    end
  end
end
