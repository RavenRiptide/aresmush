module AresMUSH
  module Pf2e

    # What the `creature` commands share: who is asking, as the access table reads them, and the saved
    # creature a command names.
    module CreatureCommand
      def actor
        @actor ||= CreatureAccess.actor(enactor)
      end

      # A saved creature this character may do `action` with, by name, `c:<id>` or `c:<name>`.
      def saved(term, action)
        found = Creatures.find(enactor, term =~ Creatures::SAVED ? term : "c:#{term}", action)

        return found if found.err?

        Ok.new(:state => found.state['creature'])
      end

      # Errors as one line each, for what refused a save.
      def told_errors(errors)
        errors.map { |one| t(one['key'], **CharState.symbolize(one['args'])) }.join('%r')
      end

      # Saves a block as a new revision of their creature of that name, or as a new creature.
      def save(name, block, cloned_from: nil)
        errors = CreatureCheck.errors(block)

        return client.emit_failure(t('pf2e.creature_invalid', :errors => told_errors(errors))) if errors.any?

        own = Creatures.allowed(enactor, 'edit').find { |one| one.owner_id.to_s == enactor.id.to_s && one.name_slug == Domains.slug(name) }

        if own
          revision = CreatureStore.revise!(own, block, enactor)
          return client.emit_ooc(t('pf2e.creature_unchanged', :name => own.name)) unless revision

          return client.emit_success(t('pf2e.creature_saved', :name => own.name, :id => own.id, :revision => revision.number,
                                                              :summary => revision.summary))
        end

        named = CreatureCheck.name(name)
        return if CharState.emit_error!(client, named)

        made = CreatureStore.create!(enactor, named.state, block, :cloned_from => cloned_from)
        client.emit_success t('pf2e.creature_created', :name => made.name, :id => made.id)
      end

      # The latest revision of one of theirs, changed and saved again.
      def revised(term)
        found = saved(term, 'edit')
        return if CharState.emit_error!(client, found)

        creature = found.state
        changed = yield(creature.head.block)
        return if CharState.emit_error!(client, changed)

        errors = CreatureCheck.errors(changed.state)
        return client.emit_failure(t('pf2e.creature_invalid', :errors => told_errors(errors))) if errors.any?

        revision = CreatureStore.revise!(creature, changed.state, enactor)
        return client.emit_ooc(t('pf2e.creature_unchanged', :name => creature.name)) unless revision

        client.emit_success t('pf2e.creature_saved', :name => creature.name, :id => creature.id, :revision => revision.number,
                                                     :summary => revision.summary)
      end
    end

    # `creature/list [mine|shared|published|all][/<level>]` - saved creatures you may use, or see.
    class PF2CreatureListCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :scope, :level

      SCOPES = %w{mine shared published all}.freeze

      def parse_args
        scope, _, level = cmd.args.to_s.partition('/')
        self.scope = scope.strip.downcase.empty? ? 'all' : scope.strip.downcase
        self.level = level.strip.match?(/\A-?\d+\z/) ? level.strip.to_i : nil
      end

      def check_scope
        SCOPES.include?(self.scope) ? nil : t('pf2e.creature_list_scopes', :scopes => SCOPES.join(', '))
      end

      def handle
        listed = Creatures.allowed(enactor, 'view').select { |creature| in_scope?(creature) }
                          .select { |creature| self.level.nil? || creature.level.to_i == self.level }
                          .sort_by { |creature| [ creature.level.to_i, creature.name ] }

        return client.emit_ooc(t('pf2e.creature_list_none')) if listed.empty?

        lines = listed.map do |creature|
          "#{"c:#{creature.id}".ljust(8)}#{creature.name.ljust(32)} Creature #{creature.level.to_s.ljust(3)} #{creature.owner_name.to_s.ljust(16)} #{creature.status}"
        end

        client.emit ([ t('pf2e.creature_list_title') ] + lines).join('%r')
      end

      def in_scope?(creature)
        mine = creature.owner_id.to_s == enactor.id.to_s

        case self.scope
        when 'mine' then mine
        when 'shared' then !mine && CreatureAccess.reaches?(actor, Creatures.row(creature))
        when 'published' then !creature.published_id.nil?
        else true
        end
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
        revision = ref['revision'] || creature.head
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
        block = Creatures.block(ref) || ref['creature']&.head&.block
        from = ref['source'] == 'bestiary' ? "bestiary:#{ref['name']}" : "saved:#{ref['creature'].id}"

        save(self.name, block, :cloned_from => from)
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

        named = CreatureCheck.name(self.name)
        return if CharState.emit_error!(client, named)

        CreatureStore.rename!(found.state, named.state, enactor)
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

        block = Creatures.block(found.state) || found.state['creature']&.head&.block
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

      def handle
        found = saved(self.term, 'share')
        return if CharState.emit_error!(client, found)

        creature = found.state
        everyone = self.with.first.downcase

        if %w{plotmasters private}.include?(everyone) && !cmd.switch_is?('unshare')
          CreatureStore.share!(creature, everyone, [], enactor)
          return told(creature)
        end

        named = self.with.map { |name| [ name, Character.find_one_by_name(name) ] }
        missing = named.find { |_name, char| char.nil? }
        return client.emit_failure(t('pf2e.char_not_found')) if missing

        refused = named.find { |_name, char| !CreatureAccess.shareable?(CreatureAccess.actor(char)) }
        return client.emit_failure(t('pf2e.creature_share_who', :name => refused.last.name)) if refused

        ids = named.map { |_name, char| char.id.to_s }
        held = Array(creature.shared_with).map(&:to_s)
        now = cmd.switch_is?('unshare') ? held - ids : (held + ids).uniq

        CreatureStore.share!(creature, now.empty? ? 'private' : 'shared', now, enactor)
        told(creature)
      end

      def told(creature)
        creature = Pf2eCreature[creature.id]
        names = Array(creature.shared_with).map { |id| Character[id]&.name }.compact

        who = case creature.audience
              when 'plotmasters' then t('pf2e.creature_audience_plotmasters')
              when 'shared' then names.join(', ')
              else t('pf2e.creature_audience_private')
              end

        client.emit_success t('pf2e.creature_shared', :name => creature.name, :who => who)
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
        events = creature.events.to_a.sort_by { |one| [ one.created_at.to_s, one.id.to_i ] }
        summaries = creature.revisions.to_a.to_h { |one| [ one.number, one.summary ] }
        lines = events.map do |one|
          revision = one.revision ? " r#{one.revision}" : ''
          said = one.kind == 'revised' || one.kind == 'created' ? summaries[one.revision] : (one.detail || {}).map { |key, value| "#{key}: #{Array(value).join(', ')}" }.join('; ')

          "#{one.created_at.to_s[0, 16]}  #{one.by.to_s.ljust(14)} #{one.kind}#{revision}#{said.to_s.empty? ? '' : " - #{said}"}"
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
        CreatureStore.retire!(found.state, enactor, retiring)
        client.emit_success t(retiring ? 'pf2e.creature_retired_ok' : 'pf2e.creature_restored', :name => found.state.name)
      end
    end
  end
end
