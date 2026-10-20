module AresMUSH
  module Pf2e

    # What the `creature` commands share: who is asking, as the access table reads them, and the saved
    # creature a command names.
    module CreatureCommand
      def actor
        @actor ||= CreatureAccess.actor(enactor)
      end

      # A saved creature this character may do `action` with, by name, `c:<id>` or `c:<name>`. One they
      # may see and not do this with is refused as that, rather than as not there.
      def saved(term, action)
        found = Creatures.find(enactor, term =~ Creatures::SAVED ? term : "c:#{term}", 'view')

        return found if found.err?

        creature = found.state['creature']

        CreatureAccess.may(actor, action, Creatures.row(creature)).and_then { Ok.new(:state => creature) }
      end

      # Errors as one line each, for what refused a save.
      def told_errors(errors)
        errors.map { |one| t(one['key'], **CharState.symbolize(one['args'])) }.join('%r')
      end

      # Says why something was refused: every finding of a block's checks, or the one refusal.
      def refused?(outcome)
        return false if outcome.ok?
        return CharState.emit_error!(client, outcome) unless outcome.code == :creature_invalid

        client.emit_failure t('pf2e.creature_invalid', :errors => told_errors(outcome.args['errors']))
        true
      end

      # Says what a save (`CreatureSaving`) did.
      def told_saved(outcome)
        return if refused?(outcome)

        creature = outcome.state['creature']
        revision = outcome.state['revision']

        return client.emit_success(t('pf2e.creature_created', :name => creature.name, :id => creature.id)) if outcome.state['created']
        return client.emit_ooc(t('pf2e.creature_unchanged', :name => creature.name)) unless revision

        client.emit_success t('pf2e.creature_saved', :name => creature.name, :id => creature.id, :revision => revision.number,
                                                     :summary => revision.summary)
      end

      def save(name, block, cloned_from: nil, fresh: false)
        told_saved(CreatureSaving.save(enactor, name, block, :cloned_from => cloned_from, :fresh => fresh))
      end

      # The latest revision of one of theirs, changed and saved again.
      def revised(term)
        found = saved(term, 'edit')
        return if CharState.emit_error!(client, found)

        changed = yield(found.state.head.block)
        return if CharState.emit_error!(client, changed)

        told_saved(CreatureSaving.revise(enactor, found.state, changed.state))
      end
    end

    # `creature/list [mine|shared|published|all][/<level>]` - saved creatures you may use, or see.
    class PF2CreatureListCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :scope, :level

      def parse_args
        scope, _, level = cmd.args.to_s.partition('/')
        self.scope = scope.strip.downcase.empty? ? 'all' : scope.strip.downcase
        self.level = level.strip.match?(/\A-?\d+\z/) ? level.strip.to_i : nil
      end

      def check_scope
        CreatureAccess::SCOPES.key?(self.scope) ? nil : t('pf2e.creature_list_scopes', :scopes => CreatureAccess::SCOPES.keys.join(', '))
      end

      def handle
        listed = Creatures.allowed(enactor, 'view').select { |creature| CreatureAccess.in_scope?(actor, Creatures.row(creature), self.scope) }
                          .select { |creature| self.level.nil? || creature.level.to_i == self.level }
                          .sort_by { |creature| [ creature.level.to_i, creature.name ] }

        return client.emit_ooc(t('pf2e.creature_list_none')) if listed.empty?

        lines = listed.map do |creature|
          "#{"c:#{creature.id}".ljust(8)}#{creature.name.ljust(32)} Creature #{creature.level.to_s.ljust(3)} #{creature.owner_name.to_s.ljust(16)} #{creature.status}"
        end

        client.emit ([ t('pf2e.creature_list_title') ] + lines).join('%r')
      end
    end

    # `creature <creature>` - a saved creature's stat block, with whose it is and where it stands.
    class PF2CreatureViewCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term

      def parse_args
        self.term = trim_arg(cmd.args)
      end

      def required_args
        [ self.term ]
      end

      def handle
        found = Creatures.find(enactor, self.term, 'view')
        return if CharState.emit_error!(client, found)

        ref = found.state
        return client.emit(StatBlock.lines(ref['name'], Bestiary.entry(ref['name'])).join('%r')) if ref['source'] == 'bestiary'

        creature = ref['creature']
        revision = Creatures.shown(enactor, ref)
        lines = [ t('pf2e.creature_header', :id => creature.id, :revision => revision.number, :latest => creature.head.number,
                                            :owner => creature.owner_name, :status => creature.status) ]
        lines += StatBlock.lines(creature.name, revision.block)
        lines << t('pf2e.creature_review_note', :note => creature.review_note) if creature.review_note && CreatureAccess.may(actor, 'edit', Creatures.row(creature)).ok?
        lines << t('pf2e.creature_notes', :notes => creature.notes) if creature.notes.to_s.strip != '' && CreatureAccess.may(actor, 'edit', Creatures.row(creature)).ok?

        client.emit lines.join('%r')
      end
    end

    # `creature/save <name>=<description>` saves a creature from a one-line description, or a new revision
    # of your own of that name. `creature/save <name>=#<id>` saves one from the encounter you run here.
    class PF2CreatureSaveCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :name, :words

      def parse_args
        self.name, _, words = cmd.args.to_s.partition('=')
        self.name = self.name.strip
        self.words = words.strip
      end

      def required_args
        [ self.name, self.words ]
      end

      def check_may_create
        CreatureAccess.may(actor, 'create').ok? ? nil : t('pf2e.creature_may_not', :action => 'create')
      end

      def handle
        from = self.words.start_with?('#') ? 'encounter' : 'described'
        read = from == 'encounter' ? from_encounter : Described.read(self.name, self.words)

        return client.emit_failure(t('pf2e.creature_save_words')) unless read
        return if CharState.emit_error!(client, read)

        save(self.name, read.state, :cloned_from => from)
      end

      # A creature in the encounter they run here, as its stat block is written, without its adjustment.
      def from_encounter
        encounter = Combatants.encounter_here(enactor)

        return Err.new(:no_encounter, 'pf2e.not_in_active_encounter') unless encounter
        return Err.new(:not_gm, 'pf2e.not_organizer') unless Combatants.gm?(enactor, encounter)

        Combatants.find(encounter, self.words).and_then do |one|
          one.creature? ? Ok.new(:state => one.holder.written_stat_block) : Err.new(:not_creature, 'pf2e.adjust_not_creature', 'who' => one.label)
        end
      end
    end

    # `creature/clone <creature>=<new name>` - a copy of a bestiary creature, or a saved one you may see,
    # to make your own.
    class PF2CreatureCloneCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term, :name

      def parse_args
        self.term, _, name = cmd.args.to_s.partition('=')
        self.term = self.term.strip
        self.name = name.strip
      end

      def required_args
        [ self.term, self.name ]
      end

      def check_may_create
        CreatureAccess.may(actor, 'create').ok? ? nil : t('pf2e.creature_may_not', :action => 'create')
      end

      def handle
        found = Creatures.find(enactor, self.term, 'clone')
        return if CharState.emit_error!(client, found)

        ref = found.state
        block = Creatures.shown_block(enactor, ref)
        from = ref['source'] == 'bestiary' ? "bestiary:#{ref['name']}" : "saved:#{ref['creature'].id}"

        save(self.name, block, :cloned_from => from, :fresh => true)
      end
    end

    # `creature/set <name>=<part>` and `creature/unset <name>=<part>` - one part at a time, in the words
    # of a description: `ac 19 hp 40`, `strike claw +9 1d6+4 slashing (agile)`, `weak fire 5`.
    class PF2CreatureSetCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term, :words

      def parse_args
        self.term, _, words = cmd.args.to_s.partition('=')
        self.term = self.term.strip
        self.words = words.strip
      end

      def required_args
        [ self.term, self.words ]
      end

      def handle
        unsetting = cmd.switch_is?('unset')

        revised(self.term) { |block| unsetting ? CreatureDraft.unset(block, self.words) : CreatureDraft.set(block, self.words) }
      end
    end

    # `creature/rename <name>=<new name>`
    class PF2CreatureRenameCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term, :name

      def parse_args
        self.term, _, name = cmd.args.to_s.partition('=')
        self.term = self.term.strip
        self.name = name.strip
      end

      def required_args
        [ self.term, self.name ]
      end

      def handle
        found = saved(self.term, 'edit')
        return if CharState.emit_error!(client, found)

        creature = found.state
        named = CreatureCheck.name(self.name).and_then { |checked| CreatureStore.name_free(creature.owner || enactor, checked, creature) }
        return if CharState.emit_error!(client, named)

        CreatureStore.rename!(creature, named.state, enactor)
        client.emit_success t('pf2e.creature_renamed', :was => found.state.name, :name => named.state)
      end
    end

    # `creature/notes <name>=<notes>` - the author's own notes, no part of the stat block.
    class PF2CreatureNotesCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term, :notes

      def parse_args
        self.term, _, notes = cmd.args.to_s.partition('=')
        self.term = self.term.strip
        self.notes = notes.strip
      end

      def required_args
        [ self.term ]
      end

      def handle
        found = saved(self.term, 'edit')
        return if CharState.emit_error!(client, found)

        CreatureStore.notes!(found.state, self.notes, enactor)
        client.emit_success t('pf2e.creature_notes_set', :name => found.state.name)
      end
    end

    # `creature/describe <name>` - the line that makes it again, and what a line cannot hold.
    class PF2CreatureDescribeCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term

      def parse_args
        self.term = trim_arg(cmd.args)
      end

      def required_args
        [ self.term ]
      end

      def handle
        found = Creatures.find(enactor, self.term, 'clone')
        return if CharState.emit_error!(client, found)

        block = Creatures.shown_block(enactor, found.state)
        lines = [ "creature/save #{found.state['name']}=#{Described.write(block)}" ]
        missing = Described.unwritable(block)
        lines << t('pf2e.creature_unwritable', :list => missing.join(', ')) if missing.any?

        client.emit lines.join('%r%r')
      end
    end

    # `creature/share <name>=<character>[,...]`, `=plotmasters` or `=private` - who besides its author may
    # use it unapproved: Plotmasters and admins only. `creature/unshare <name>=<character>`.
    class PF2CreatureShareCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term, :with

      def parse_args
        self.term, _, with = cmd.args.to_s.partition('=')
        self.term = self.term.strip
        self.with = with.split(',').map(&:strip).reject(&:empty?)
      end

      def required_args
        [ self.term, self.with.first ]
      end

      WORDS = %w{plotmasters private}.freeze

      def handle
        found = saved(self.term, 'share')
        return if CharState.emit_error!(client, found)

        creature = found.state
        words = self.with.map(&:downcase) & WORDS
        unsharing = cmd.switch_is?('unshare')
        held = Array(creature.shared_with).map(&:to_s)

        return client.emit_failure(t('pf2e.creature_share_mixed')) if words.any? && (self.with.size > 1 || (unsharing && words == [ 'private' ]))
        return shared(creature, false, []) if words == [ 'private' ]
        return shared(creature, !unsharing, held) if words == [ 'plotmasters' ]

        named = Creatures.sharers(self.with, creature)
        return if CharState.emit_error!(client, named)

        ids = named.state.map { |char| char.id.to_s }

        shared(creature, creature.audience == 'plotmasters', unsharing ? held - ids : (held + ids).uniq)
      end

      # Every Plotmaster or not, and these by name, which stand apart: either is taken back alone.
      def shared(creature, plotmasters, ids)
        audience = CreatureAccess.share(Creatures.row(creature), plotmasters, ids)
        return if CharState.emit_error!(client, audience)

        CreatureStore.share!(creature, audience.state, ids, enactor)

        who = ([ plotmasters ? t('pf2e.creature_audience_plotmasters') : nil ] + ids.map { |id| Character[id]&.name }).compact
        who = [ t('pf2e.creature_audience_private') ] if who.empty?

        client.emit_success t('pf2e.creature_shared', :name => creature.name, :who => who.join(', '))
      end
    end

    # `creature/history <name>` - its revisions and what else happened to it.
    class PF2CreatureHistoryCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term

      def parse_args
        self.term = trim_arg(cmd.args)
      end

      def required_args
        [ self.term ]
      end

      def handle
        found = saved(self.term, 'edit')
        return if CharState.emit_error!(client, found)

        creature = found.state
        lines = Creatures.history(creature).map do |one|
          revision = one['revision'] ? " r#{one['revision']}" : ''
          said = one['summary'] || one['detail'].map { |key, value| "#{key}: #{Array(value).join(', ')}" }.join('; ')

          "#{one['at']}  #{one['by'].to_s.ljust(14)} #{one['kind']}#{revision}#{said.to_s.empty? ? '' : " - #{said}"}"
        end

        client.emit ([ t('pf2e.creature_history_title', :name => creature.name, :id => creature.id) ] + lines).join('%r')
      end
    end

    # `creature/retire <name>` and `creature/restore <name>` - off the lists and out of use, or back.
    class PF2CreatureRetireCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term

      def parse_args
        self.term = trim_arg(cmd.args)
      end

      def required_args
        [ self.term ]
      end

      def handle
        found = saved(self.term, 'retire')
        return if CharState.emit_error!(client, found)

        retiring = cmd.switch_is?('retire')
        if retiring
          CreatureStore.retire!(found.state, enactor, true)
        else
          return if CharState.emit_error!(client, CreatureStore.restore!(found.state, enactor))
        end

        client.emit_success t(retiring ? 'pf2e.creature_retired_ok' : 'pf2e.creature_restored', :name => found.state.name)
      end
    end

    # `creature/owner <creature>=<character>` - for staff: hands it to someone else, whose it is from now on.
    class PF2CreatureOwnerCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term, :to

      def parse_args
        self.term, _, to = cmd.args.to_s.partition('=')
        self.term = self.term.strip
        self.to = to.strip
      end

      def required_args
        [ self.term, self.to ]
      end

      def handle
        found = saved(self.term, 'hand')
        return if CharState.emit_error!(client, found)

        to = Character.find_one_by_name(self.to)
        return client.emit_failure(t('pf2e.char_not_found')) unless to

        return if CharState.emit_error!(client, CreatureStore.hand!(found.state, to, enactor))

        client.emit_success t('pf2e.creature_handed', :name => found.state.name, :owner => to.name)
      end
    end

    # `creature/purge <creature>` - for staff: gone for good, once no encounter holds it.
    class PF2CreaturePurgeCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term

      def parse_args
        self.term = trim_arg(cmd.args)
      end

      def required_args
        [ self.term ]
      end

      def handle
        found = saved(self.term, 'purge')
        return if CharState.emit_error!(client, found)

        name = found.state.name
        done = CreatureStore.purge!(found.state, enactor)
        return if CharState.emit_error!(client, done)

        CharState.emit_messages!(client, done)
        client.emit_success t('pf2e.creature_purged', :name => name)
      end
    end
  end
end
