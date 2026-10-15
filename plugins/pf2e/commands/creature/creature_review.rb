module AresMUSH
  module Pf2e

    # `creature/submit <name>[=<note>]` asks an admin to approve your creature's latest revision, which
    # then anyone may use. `creature/withdraw <name>` takes the request back.
    class PF2CreatureSubmitCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term, :note

      def parse_args
        self.term, _, note = cmd.args.to_s.partition('=')
        self.term = self.term.strip
        self.note = note.strip
      end

      def required_args
        [ self.term ]
      end

      def handle
        found = saved(self.term, 'submit')
        return if CharState.emit_error!(client, found)

        creature = found.state

        if cmd.switch_is?('withdraw')
          done = CreatureReview.withdraw!(creature, enactor)
          return if CharState.emit_error!(client, done)

          return client.emit_success(t('pf2e.creature_withdrawn', :name => creature.name))
        end

        return if refused?(CreatureReview.submit!(creature, enactor, self.note))

        client.emit_success t('pf2e.creature_submitted_ok', :name => creature.name)
        CreatureNotices.submitted(creature, enactor)
      end
    end

    # `creature/check <creature>` - what would keep a creature from being saved, what is warned of, and
    # where each of its figures sits for its level by GM Core's tables.
    class PF2CreatureCheckCmd
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

        block = Creatures.shown_block(enactor, found.state)
        errors = CreatureCheck.errors(block)
        warnings = CreatureCheck.warnings(block)
        bands = CreatureBenchmarks.bands(block).map { |one| "#{one['figure']} #{one['value']}: #{one['band']}" }
        lines = [ t('pf2e.creature_check_title', :name => found.state['name'], :level => block['level'].to_i) ]
        lines << (errors.empty? ? t('pf2e.creature_check_no_errors') : told_errors(errors))
        lines << told_errors(warnings) if warnings.any?
        lines << bands.each_slice(3).map { |three| three.join('; ') }.join('%r')

        client.emit lines.join('%r%r')
      end
    end

    # `creature/queue` - for admins, the creatures awaiting approval.
    class PF2CreatureQueueCmd
      include CommandHandler
      include CreatureCommand

      def check_admin
        CreatureAccess.may(actor, 'review').ok? ? nil : t('pf2e.creature_may_not', :action => 'review')
      end

      def handle
        waiting = Creatures.all.select(&:submitted_id).sort_by { |creature| creature.submitted.created_at.to_s }

        return client.emit_ooc(t('pf2e.creature_queue_empty')) if waiting.empty?

        lines = waiting.map do |creature|
          revision = creature.submitted
          changes = creature.published ? Creatures.changes(creature.published.block, revision.block) : t('pf2e.creature_queue_new')
          note = creature.submitted_note.to_s.empty? ? '' : " \"#{creature.submitted_note}\""

          above = CreatureBenchmarks.warnings(revision.block).map { |one| "#{one['args']['figure']} #{one['args']['band']}" }
          flagged = above.empty? ? '' : "%r    #{t('pf2e.creature_queue_above', :list => above.join(', '))}"

          "c:#{creature.id} #{creature.name}, Creature #{revision.block['level']}, by #{creature.owner_name}, revision #{revision.number}#{note}%r    #{changes}#{flagged}"
        end

        client.emit ([ t('pf2e.creature_queue_title') ] + lines).join('%r')
      end
    end

    # `creature/approve <creature>`, `creature/reject <creature>=<reason>` and `creature/unpublish
    # <creature>` - for admins. Approval publishes the submitted revision for everyone.
    class PF2CreatureReviewCmd
      include CommandHandler
      include CreatureCommand

      attr_accessor :term, :reason

      def parse_args
        self.term, _, reason = cmd.args.to_s.partition('=')
        self.term = self.term.strip
        self.reason = reason.strip
      end

      def required_args
        [ self.term ]
      end

      def check_admin
        CreatureAccess.may(actor, 'review').ok? ? nil : t('pf2e.creature_may_not', :action => 'review')
      end

      def handle
        found = saved(self.term, 'review')
        return if CharState.emit_error!(client, found)

        decision = cmd.switch.to_s.downcase
        done = CreatureReview.decide!(found.state, enactor, decision, self.reason)
        return if CharState.emit_error!(client, done)

        CharState.emit_messages!(client, done)
        client.emit_success CreatureNotices.decided(found.state, enactor, decision, self.reason)
      end
    end
  end
end
