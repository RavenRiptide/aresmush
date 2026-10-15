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

        errors = CreatureCheck.errors(creature.head.block)
        return client.emit_failure(t('pf2e.creature_invalid', :errors => told_errors(errors))) if errors.any?

        done = CreatureReview.submit!(creature, enactor, self.note)
        return if CharState.emit_error!(client, done)

        client.emit_success t('pf2e.creature_submitted_ok', :name => creature.name)
        message = t('pf2e.creature_awaits', :name => creature.name, :id => creature.id, :author => enactor.name)
        Global.notifier.notify_ooc(:pf2_creature, message) { |char| char && char.is_admin? }
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

          "c:#{creature.id} #{creature.name}, Creature #{revision.block['level']}, by #{creature.owner_name}, revision #{revision.number}#{note}%r    #{changes}"
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

      DONE = { 'approve' => 'approved', 'reject' => 'rejected', 'unpublish' => 'unpublished' }.freeze

      def handle
        found = saved(self.term, 'review')
        return if CharState.emit_error!(client, found)

        creature = found.state
        decision = cmd.switch.to_s.downcase
        done = case decision
               when 'approve' then CreatureReview.approve!(creature, enactor)
               when 'reject' then CreatureReview.reject!(creature, enactor, self.reason)
               else CreatureReview.unpublish!(creature, enactor)
               end

        return if CharState.emit_error!(client, done)

        message = t("pf2e.creature_#{DONE[decision]}", :name => creature.name, :by => enactor.name, :reason => self.reason)
        client.emit_success message
        Global.logger.info "PF2 creature c:#{creature.id} #{creature.name} #{DONE[decision]} by #{enactor.name}"
        Login.notify(creature.owner, :pf2_creature, message, creature.id) if creature.owner && creature.owner != enactor
      end
    end
  end
end
