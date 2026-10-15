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
          can_create: CreatureAccess.may(actor, 'create').ok?, runs_own: CreatureAccess.runs_own?(actor), admin: CreatureAccess.admin?(actor),
          waiting: CreatureAccess.admin?(actor) ? Creatures.all.count(&:submitted_id) : 0,
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
        creature.events.to_a.sort_by { |one| [ one.created_at.to_s, one.id.to_i ] }.map do |one|
          # What changed belongs to the event that made the revision, not to one that only names it.
          made = %w{created revised renamed}.include?(one.kind)
          summary = made && one.revision ? creature.revisions.to_a.find { |revision| revision.number == one.revision }&.summary : nil

          { at: one.created_at.to_s[0, 16], by: one.by, kind: one.kind, revision: one.revision, summary: summary }
        end
      end
    end
  end
end

module AresMUSH
  module Pf2e

    # What the web editor shares: whose creature an id names, and what a block came from.
    module CreatureEditor

      def self.editable(char, id)
        found = Creatures.find(char, "c:#{id}", 'view')

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
          found = Creatures.find(char, "c:#{key}", 'clone')
          found.ok? ? Creatures.shown_block(char, found.state) : nil
        end
      end

      def self.findings(list)
        list.map { |one| { code: one['code'].to_s, message: t(one['key'], **CharState.symbolize(one['args'])) } }
      end

      def self.refusal(err)
        { code: err.code.to_s, message: t(err.key, **CharState.symbolize(err.args)) }
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

        if from == 'blank'
          level = request.args['level'].to_i
          return { block: { 'name' => '', 'level' => level, 'traits' => [], 'saves' => { 'fortitude' => 0, 'reflex' => 0, 'will' => 0 },
                            'strikes' => [], 'actions' => [] }, cloned_from: nil }
        end

        if from == 'described'
          read = Described.read('', request.args['words'].to_s)
          return { error: t('pf2e.creature_save_words') } unless read
          return { error: t(read.key, **CharState.symbolize(read.args)) } if read.err?

          return { block: read.state, cloned_from: 'described' }
        end

        block = CreatureEditor.source(request.enactor, from)

        return { error: t('pf2e.creature_web_not_found') } unless block

        { block: CreatureBlock.plain(block).except('pack', 'source', 'adjustment', 'approved'), cloned_from: from }
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
        named = CreatureCheck.name(name).and_then { |checked| CreatureStore.name_free(creature&.owner || char, checked, creature) }
        errors = (named.err? ? [ CreatureCheck.found(named.code, named.args) ] : []) + CreatureCheck.errors(block)

        { errors: CreatureEditor.findings(errors), warnings: CreatureEditor.findings(CreatureCheck.warnings(block)),
          mechanised: CreatureMechanised.of(block), bands: CreatureBenchmarks.bands(block), lines: CreatureWeb.lines(name, block), line: Described.write(block),
          unwritable: Described.unwritable(block) }
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
        return { error: t(found.key, **CharState.symbolize(found.args)) } if found.err?

        revise(char, found.state, request)
      end

      def create(char, request)
        name = request.args['name'].to_s.strip
        block = CreatureBlock.cleaned(request.args['block'], CreatureEditor.source(char, request.args['cloned_from'])).merge('name' => name)
        named = CreatureCheck.name(name).and_then { |checked| CreatureStore.name_free(char, checked) }

        return { errors: [ CreatureEditor.refusal(named) ] } if named.err?

        errors = CreatureCheck.errors(block)
        return { errors: CreatureEditor.findings(errors) } if errors.any?

        creature = CreatureStore.create!(char, named.state, block, :cloned_from => request.args['cloned_from'].to_s.empty? ? 'web' : request.args['cloned_from'])
        CreatureStore.notes!(creature, request.args['notes'].to_s, char) if request.args['notes'].to_s.strip != ''

        { id: creature.id, revision: creature.head.number, summary: creature.head.summary }
      end

      def revise(char, creature, request)
        return { error: t('pf2e.creature_stale'), head: creature.head.number } if creature.head.number != request.args['base_revision'].to_i

        name = request.args['name'].to_s.strip
        block = CreatureBlock.cleaned(request.args['block'], creature.head.block)
        errors = CreatureCheck.errors(block.merge('name' => name))
        return { errors: CreatureEditor.findings(errors) } if errors.any?

        if name != creature.name
          named = CreatureCheck.name(name).and_then { |checked| CreatureStore.name_free(creature.owner || char, checked, creature) }
          return { errors: [ CreatureEditor.refusal(named) ] } if named.err?

          CreatureStore.rename!(creature, named.state, char)
        end

        revision = CreatureStore.revise!(Pf2eCreature[creature.id], block, char)
        CreatureStore.notes!(creature, request.args['notes'].to_s, char) if request.args.key?('notes') && request.args['notes'].to_s != creature.notes.to_s
        head = Pf2eCreature[creature.id].head

        { id: creature.id, revision: head.number, summary: revision ? revision.summary : t('pf2e.creature_unchanged', :name => name) }
      end
    end
  end
end

module AresMUSH
  module Pf2e

    # `pf2CreatureAct` - what an author does to one of their own from its page: `{ id, act }`, the act being
    # submit (with `note`), withdraw, retire, restore, or share (with `plotmasters` and `with`, names).
    class PF2CreatureActHandler
      ACTIONS = { 'submit' => 'submit', 'withdraw' => 'submit', 'retire' => 'retire', 'restore' => 'retire', 'share' => 'share' }.freeze

      def handle(request)
        error = Website.check_login(request)
        return error if error

        char = request.enactor
        act = request.args['act'].to_s
        found = Creatures.find(char, "c:#{request.args['id']}", 'view')

        return { error: t('pf2e.creature_web_not_found') } if found.err? || !ACTIONS.key?(act)

        creature = found.state['creature']
        allowed = CreatureAccess.may(CreatureAccess.actor(char), ACTIONS[act], Creatures.row(creature))
        return { error: t(allowed.key, **CharState.symbolize(allowed.args)) } if allowed.err?

        done = send(act, char, creature, request.args)
        return { error: t(done.key, **CharState.symbolize(done.args)) } if done.is_a?(Err)

        { creature: CreatureWeb.saved_summary(char, Pf2eCreature[creature.id]) }
      end

      def submit(char, creature, args)
        errors = CreatureCheck.errors(creature.head.block)
        return Err.new(:creature_invalid, 'pf2e.creature_invalid', 'errors' => CreatureEditor.findings(errors).map { |one| one[:message] }.join(' ')) if errors.any?

        done = CreatureReview.submit!(creature, char, args['note'].to_s)
        if done.ok?
          message = t('pf2e.creature_awaits', :name => creature.name, :id => creature.id, :author => char.name)
          Global.notifier.notify_ooc(:pf2_creature, message) { |one| one && one.is_admin? }
        end
        done
      end

      def withdraw(char, creature, _args)
        CreatureReview.withdraw!(creature, char)
      end

      def retire(char, creature, _args)
        CreatureStore.retire!(creature, char, true)
      end

      def restore(char, creature, _args)
        CreatureStore.retire!(creature, char, false)
      end

      # Every Plotmaster or not, and these by name: Plotmasters and admins only.
      def share(char, creature, args)
        named = Array(args['with']).map(&:to_s).map(&:strip).reject(&:empty?).map { |name| [ name, Character.find_one_by_name(name) ] }
        missing = named.find { |_name, one| one.nil? }
        return Err.new(:not_found, 'pf2e.char_not_found') if missing

        refused = named.find { |_name, one| !CreatureAccess.shareable?(CreatureAccess.actor(one)) }
        return Err.new(:creature_share_who, 'pf2e.creature_share_who', 'name' => refused.last.name) if refused

        ids = named.map { |_name, one| one.id.to_s }
        plotmasters = args['plotmasters'] == true || args['plotmasters'].to_s == 'true'
        audience = if plotmasters then 'plotmasters'
                   elsif ids.any? then 'shared'
                   else 'private'
                   end

        CreatureStore.share!(creature, audience, ids, char)
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

        waiting = Creatures.all.select(&:submitted_id).sort_by { |creature| creature.submitted.created_at.to_s }

        { submissions: waiting.map { |creature| submission(char, creature) } }
      end

      def submission(char, creature)
        revision = creature.submitted
        block = revision.block

        { creature: CreatureWeb.saved_summary(char, creature), revision: revision.number, note: creature.submitted_note,
          changes: creature.published ? Creatures.changes(creature.published.block, block) : t('pf2e.creature_queue_new'),
          errors: CreatureEditor.findings(CreatureCheck.errors(block)), warnings: CreatureEditor.findings(CreatureCheck.warnings(block)),
          mechanised: CreatureMechanised.of(block), bands: CreatureBenchmarks.bands(block), lines: CreatureWeb.lines(creature.name, block) }
      end
    end

    # `pf2CreatureReview` - an admin's decision: `{ id, decision: approve | reject | unpublish, note }`. A
    # rejection needs its reason, which its author reads on the creature.
    class PF2CreatureReviewHandler
      DONE = { 'approve' => 'approved', 'reject' => 'rejected', 'unpublish' => 'unpublished' }.freeze

      def handle(request)
        error = Website.check_login(request)
        return error if error

        char = request.enactor
        return { error: t('pf2e.creature_may_not', :action => 'review') } unless CreatureAccess.admin?(CreatureAccess.actor(char))

        creature = Pf2eCreature[request.args['id']]
        decision = request.args['decision'].to_s
        return { error: t('pf2e.creature_web_not_found') } unless creature && DONE.key?(decision)

        note = request.args['note'].to_s
        done = case decision
               when 'approve' then CreatureReview.approve!(creature, char)
               when 'reject' then CreatureReview.reject!(creature, char, note)
               else CreatureReview.unpublish!(creature, char)
               end

        return { error: t(done.key, **CharState.symbolize(done.args)) } if done.err?

        message = t("pf2e.creature_#{DONE[decision]}", :name => creature.name, :by => char.name, :reason => note)
        Global.logger.info "PF2 creature c:#{creature.id} #{creature.name} #{DONE[decision]} by #{char.name}"
        Login.notify(creature.owner, :pf2_creature, message, creature.id) if creature.owner && creature.owner != char

        { creature: CreatureWeb.saved_summary(char, Pf2eCreature[creature.id]),
          messages: done.messages.map { |one| t(one['key'], **CharState.symbolize(one['args'] || {})) } }
      end
    end
  end
end
