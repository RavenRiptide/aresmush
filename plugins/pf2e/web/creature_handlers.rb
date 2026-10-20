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
        can = %w{view use edit clone share submit review retire make_public}.to_h { |action| [ action, CreatureAccess.may(actor, action, row).ok? ] }

        { ref: "saved:#{creature.id}", source: 'saved', id: creature.id, name: creature.name, level: shown&.block&.dig('level').to_i,
          traits: Array(shown&.block&.dig('traits')), owner: creature.owner_name, mine: CreatureAccess.owner?(actor, row),
          status: creature.status, audience: creature.audience || 'private', approved_for: creature.published_id ? (creature.approved_for || 'everyone') : nil,
          revision: shown&.number, latest: creature.head&.number,
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

      # What the game makes of a block: what would keep it from being saved, what is warned of, what it
      # runs of each part, where its figures sit for its level, and its stat block.
      def self.assessed(name, block)
        { errors: CreatureEditor.findings(CreatureCheck.errors(block)), warnings: CreatureEditor.findings(CreatureCheck.warnings(block)),
          mechanised: CreatureMechanised.of(block), bands: CreatureBenchmarks.bands(block), lines: lines(name, block) }
      end

      def self.matches?(summary, words, from, to)
        (words.empty? || Domains.slug(summary[:name]).include?(Domains.slug(words))) &&
          (from.nil? || summary[:level] >= from) && (to.nil? || summary[:level] <= to)
      end

      # The level of the revision this character is shown, read without loading it where that is the
      # latest, whose level the creature keeps.
      def self.shown_level(char, creature)
        actor = CreatureAccess.actor(char)
        row = Creatures.row(creature)
        latest = CreatureAccess.owner?(actor, row) || CreatureAccess.admin?(actor) || CreatureAccess.latest?(actor, row)

        latest || creature.published_id == creature.head_id ? creature.level.to_i : creature.published&.block&.dig('level').to_i
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
        scopes = (CreatureAccess::SCOPES.keys - [ 'all' ]) + [ 'bestiary' ] + (CreatureAccess.admin?(actor) ? [ 'all' ] : [])
        scope = scopes.include?(request.args['scope']) ? request.args['scope'] : 'mine'
        words = request.args['words'].to_s.strip
        from = CreatureWeb.number(request.args['level_from'])
        to = CreatureWeb.number(request.args['level_to'])

        # Each is found, filtered and sorted by its name and level, and only the page given is made up.
        listed = scope == 'bestiary' ? bestiary : saved(char, actor, scope)
        listed = listed.select { |one| CreatureWeb.matches?(one, words, from, to) }.sort_by { |one| [ one[:level], one[:name] ] }
        page = [ request.args['page'].to_i, 1 ].max
        shown = listed.drop((page - 1) * CreatureWeb::PAGE).first(CreatureWeb::PAGE)

        { scope: scope, scopes: scopes, total: listed.size, page: page, pages: [ (listed.size + CreatureWeb::PAGE - 1) / CreatureWeb::PAGE, 1 ].max,
          creatures: shown.map { |one| one[:summary].call(char) },
          can_create: CreatureAccess.may(actor, 'create').ok?, runs_own: CreatureAccess.runs_own?(actor), admin: CreatureAccess.admin?(actor),
          waiting: CreatureAccess.admin?(actor) ? Creatures.all.count(&:submitted_id) : 0,
          open_bestiaries: Gm.open_bestiaries }
      end

      def bestiary
        Bestiary.index.map do |name, listed|
          { name: name, level: listed['level'].to_i, summary: ->(char) { CreatureWeb.bestiary_summary(char, name, listed) } }
        end
      end

      def saved(char, actor, scope)
        Creatures.allowed(char, 'view').select { |creature| CreatureAccess.in_scope?(actor, Creatures.row(creature), scope) }.map do |creature|
          { name: creature.name, level: CreatureWeb.shown_level(char, creature), summary: ->(viewer) { CreatureWeb.saved_summary(viewer, creature) } }
        end
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

        found = Creatures.saved(char, key, 'view')

        return { error: t('pf2e.creature_web_not_found') } if found.err?

        creature = found.state['creature']
        summary = CreatureWeb.saved_summary(char, creature)
        shown = Creatures.shown(char, found.state)
        mine = summary[:can]['edit']

        { creature: summary, lines: CreatureWeb.lines(creature.name, shown.block), add: "+e/add c:#{creature.id}",
          addable: Creatures.usable?(char, Creatures.ref(char, creature)),
          block: mine ? CreatureBlock.plain(creature.head.block) : nil, editing_revision: mine ? creature.head.number : nil,
          shared_with: mine ? Array(creature.shared_with).filter_map { |id| Character[id]&.name } : [],
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
        Creatures.history(creature).map { |one| one.except('detail').transform_keys(&:to_sym) }
      end
    end
  end
end

module AresMUSH
  module Pf2e

    # What the web editor shares: whose creature an id names, and what a block came from.
    module CreatureEditor

      def self.editable(char, id)
        found = Creatures.saved(char, id.to_s, 'view')

        return Err.new(:not_found, 'pf2e.creature_web_not_found') if found.err?

        creature = found.state['creature']

        CreatureAccess.may(CreatureAccess.actor(char), 'edit', Creatures.row(creature)).and_then { Ok.new(:state => creature) }
      end

      # The block a new creature was started from, which its rules may come from: a bestiary creature, or a
      # saved one this character may see.
      def self.source(char, cloned_from)
        kind, _, key = cloned_from.to_s.partition(':')

        case kind
        when 'bestiary' then Bestiary.entry(Bestiary.named(key).to_s)
        when 'saved'
          found = Creatures.saved(char, key, 'clone')
          found.ok? ? Creatures.shown_block(char, found.state) : nil
        end
      end

      def self.findings(list)
        list.map { |one| { code: one['code'].to_s, message: t(one['key'], **CharState.symbolize(one['args'])) } }
      end

      def self.refusal(err)
        { code: err.code.to_s, message: t(err.key, **CharState.symbolize(err.args)) }
      end

      # An Err as a page shows it: every finding of a block's checks, or the one refusal.
      def self.error(err)
        return { error: t(err.key, **CharState.symbolize(err.args)) } unless err.code == :creature_invalid

        { error: t('pf2e.creature_invalid', :errors => findings(err.args['errors']).map { |one| one[:message] }.join(' ')) }
      end
    end

    # `pf2CreatureOptions` - the words a stat block may use, for the editor's choices.
    class PF2CreatureOptionsHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        { traits: CreatureVocabulary.traits, damage_types: IWR::DAMAGE_TYPES, sizes: %w{tiny small medium large huge gargantuan},
          rarities: %w{common uncommon rare unique}, skills: Hash(Global.read_config('pf2e_skills')).keys.sort,
          costs: [ '1', '2', '3', 'reaction', 'free', 'passive' ] }
      end
    end

    # `pf2CreatureStart` - a block to begin from: `{ from: 'bestiary:<name>' | 'saved:<id>' | 'blank', level }`,
    # or `{ from: 'described', words }` for the line a one-line `+e/add` reads.
    class PF2CreatureStartHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        from = request.args['from'].to_s

        return { block: CreatureBlock.blank(request.args['level'].to_i), cloned_from: nil } if from == 'blank'

        if from == 'described'
          read = Described.read('', request.args['words'].to_s)
          return { error: t('pf2e.creature_save_words') } unless read
          return CreatureEditor.error(read) if read.err?

          return { block: read.state, cloned_from: 'described' }
        end

        block = CreatureEditor.source(request.enactor, from)

        return { error: t('pf2e.creature_web_not_found') } unless block

        { block: CreatureBlock.cleaned(block, block), cloned_from: from }
      end
    end

    # `pf2CreatureCheck` - a block as it is built: `{ name, block, id?, cloned_from? }`. Answers what would
    # keep it from being saved, what is only warned of, what the game runs of it, and its stat block.
    class PF2CreatureCheckHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        char = request.enactor
        editing = request.args['id'].to_s.empty? ? nil : CreatureEditor.editable(char, request.args['id'])
        return { error: t('pf2e.creature_web_not_found') } if editing&.err?

        creature = editing&.state
        base = creature ? creature.head&.block : CreatureEditor.source(char, request.args['cloned_from'])
        name = request.args['name'].to_s.strip
        block = CreatureBlock.cleaned(request.args['block'], base).merge('name' => name)
        named = CreatureSaving.named(creature&.owner || char, name, creature)
        assessed = CreatureWeb.assessed(name, block)
        assessed[:errors] = CreatureEditor.findings([ CreatureCheck.found(named.code, named.args) ]) + assessed[:errors] if named.err?

        assessed.merge(line: Described.write(block), unwritable: Described.unwritable(block))
      end
    end

    # `pf2CreatureSave` - saves a block: `{ name, block, notes?, cloned_from? }` for a new creature, with
    # `id` and `base_revision` - the revision the editor began from - for a new revision of one. A save
    # against a revision since changed is refused, with the head, so nobody's edit is lost.
    class PF2CreatureSaveHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        char = request.enactor
        id = request.args['id'].to_s

        return CreatureAccess.may(CreatureAccess.actor(char), 'create').ok? ? create(char, request) : { error: t('pf2e.creature_may_not', :action => 'create') } if id.empty?

        found = CreatureEditor.editable(char, id)
        return CreatureEditor.error(found) if found.err?

        revise(char, found.state, request)
      end

      def create(char, request)
        from = request.args['cloned_from'].to_s
        block = CreatureBlock.cleaned(request.args['block'], CreatureEditor.source(char, from))

        told(CreatureSaving.create(char, request.args['name'].to_s.strip, block, :cloned_from => from.empty? ? 'web' : from,
                                                                                 :notes => request.args['notes'].to_s))
      end

      def revise(char, creature, request)
        block = CreatureBlock.cleaned(request.args['block'], creature.head.block)
        notes = request.args.key?('notes') ? request.args['notes'].to_s : nil

        told(CreatureSaving.revise(char, creature, block, :name => request.args['name'].to_s, :notes => notes,
                                                          :base_revision => request.args['base_revision'].to_i))
      end

      def told(outcome)
        if outcome.err?
          return { error: t('pf2e.creature_stale'), head: outcome.args['head'] } if outcome.code == :creature_stale
          return { errors: CreatureEditor.findings(outcome.args['errors']) } if outcome.code == :creature_invalid

          return { errors: [ CreatureEditor.refusal(outcome) ] }
        end

        creature = outcome.state['creature']
        revision = outcome.state['revision']

        { id: creature.id, revision: creature.head.number,
          summary: revision ? revision.summary : t('pf2e.creature_unchanged', :name => creature.name) }
      end
    end
  end
end

module AresMUSH
  module Pf2e

    # `pf2CreatureAct` - what an author does to one of their own from its page: `{ id, act }`, the act being
    # submit (with `note`, and `for`: everyone or author), withdraw, retire, restore, make_public, or share
    # (with `plotmasters` and `with`, names).
    class PF2CreatureActHandler
      ACTIONS = { 'submit' => 'submit', 'withdraw' => 'submit', 'retire' => 'retire', 'restore' => 'retire', 'share' => 'share',
                  'make_public' => 'make_public' }.freeze

      def handle(request)
        error = Website.check_login(request)
        return error if error

        char = request.enactor
        act = request.args['act'].to_s
        found = Creatures.saved(char, request.args['id'].to_s, 'view')

        return { error: t('pf2e.creature_web_not_found') } if found.err? || !ACTIONS.key?(act)

        creature = found.state['creature']
        allowed = CreatureAccess.may(CreatureAccess.actor(char), ACTIONS[act], Creatures.row(creature))
        return CreatureEditor.error(allowed) if allowed.err?

        done = send(act, char, creature, request.args)
        return CreatureEditor.error(done) if done.is_a?(Err)

        { creature: CreatureWeb.saved_summary(char, Pf2eCreature[creature.id]) }
      end

      def submit(char, creature, args)
        done = CreatureReview.submit!(creature, char, args['note'].to_s, :approved_for => args['for'].to_s.empty? ? 'everyone' : args['for'].to_s)
        CreatureNotices.submitted(creature, char) if done.ok?
        done
      end

      def make_public(char, creature, _args)
        CreatureReview.make_public!(creature, char)
      end

      def withdraw(char, creature, _args)
        CreatureReview.withdraw!(creature, char)
      end

      def retire(char, creature, _args)
        CreatureStore.retire!(creature, char, true)
      end

      def restore(char, creature, _args)
        CreatureStore.restore!(creature, char)
      end

      # Every Plotmaster or not, and these by name: Plotmasters and admins only.
      def share(char, creature, args)
        named = Creatures.sharers(Array(args['with']).map(&:to_s).map(&:strip).reject(&:empty?), creature)
        return named if named.err?

        ids = named.state.map { |one| one.id.to_s }
        plotmasters = args['plotmasters'] == true || args['plotmasters'].to_s == 'true'
        audience = CreatureAccess.share(Creatures.row(creature), plotmasters, ids)
        return audience if audience.err?

        CreatureStore.share!(creature, audience.state, ids, char)
      end
    end

    # `pf2CreatureQueue` - for admins: what awaits approval, with its findings and what changed since it
    # was last published.
    class PF2CreatureQueueHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        char = request.enactor
        return { error: t('pf2e.creature_may_not', :action => 'review') } unless CreatureAccess.admin?(CreatureAccess.actor(char))

        waiting = Creatures.waiting

        { submissions: waiting.map { |creature| submission(char, creature) } }
      end

      def submission(char, creature)
        revision = creature.submitted
        block = revision.block

        { creature: CreatureWeb.saved_summary(char, creature), revision: revision.number, note: creature.submitted_note,
          approved_for: creature.submitted_for || 'everyone',
          changes: creature.published ? Creatures.changes(creature.published.block, block) : t('pf2e.creature_queue_new') }
          .merge(CreatureWeb.assessed(creature.name, block))
      end
    end

    # `pf2CreatureReview` - an admin's decision: `{ id, decision: approve | reject | unpublish, note }`. A
    # rejection needs its reason, which its author reads on the creature.
    class PF2CreatureReviewHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        char = request.enactor
        return { error: t('pf2e.creature_may_not', :action => 'review') } unless CreatureAccess.admin?(CreatureAccess.actor(char))

        creature = Pf2eCreature[request.args['id']]
        return { error: t('pf2e.creature_web_not_found') } unless creature

        decision = request.args['decision'].to_s
        note = request.args['note'].to_s
        done = CreatureReview.decide!(creature, char, decision, note)
        return CreatureEditor.error(done) if done.err?

        CreatureNotices.decided(creature, char, decision, note)

        { creature: CreatureWeb.saved_summary(char, Pf2eCreature[creature.id]),
          messages: done.messages.map { |one| t(one['key'], **CharState.symbolize(one['args'] || {})) } }
      end
    end
  end
end
