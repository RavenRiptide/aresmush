module AresMUSH
  module Pf2e

    # Who hears of a creature's review: the admins of a submission, and its author of an admin's decision.
    # Each answers the message it sent, for the one who acted to be told too.
    #
    # A submission also opens a job, where staff already work and the author can talk with them; the
    # decision or a withdrawal closes it. The category is `pf2e.creature_approval_category`, the game's
    # request category where it is not set, and none at all where it is blank.
    module CreatureNotices

      def self.submitted(creature, by)
        message = t('pf2e.creature_awaits', :name => creature.name, :id => creature.id, :author => by.name)
        Global.notifier.notify_ooc(:pf2_creature, message) { |one| one && one.is_admin? }
        open_job(Pf2eCreature[creature.id], by)
        message
      end

      def self.withdrawn(creature, by)
        close_job(creature, by, t('pf2e.creature_withdrawn', :name => creature.name))
      end

      def self.category
        held = Global.read_config('pf2e', 'creature_approval_category')
        held.nil? ? Jobs.request_category : held.to_s.strip
      end

      def self.open_job(creature, by)
        return if category.empty? || !creature.submitted_id

        made = Jobs.create_job(category, t('pf2e.creature_job_title', :name => creature.name, :id => creature.id), job_text(creature), by)
        return Global.logger.warn("PF2 creature c:#{creature.id} opened no job: #{made[:error]}") unless made[:job]

        creature.update(:approval_job_id => made[:job].id)
      end

      # What staff read in the job: what was asked for and said, and the stat block with what it is
      # warned of.
      def self.job_text(creature)
        block = creature.submitted.block
        asked = t(creature.submitted_for == 'author' ? 'pf2e.creature_job_for_author' : 'pf2e.creature_job_for_everyone')
        warned = CreatureCheck.warnings(block).map { |one| t(one['key'], **CharState.symbolize(one['args'])) }

        ([ asked, creature.submitted_note.to_s.empty? ? nil : "\"#{creature.submitted_note}\"", '',
           StatBlock.lines(creature.name, block).join('%r') ] + (warned.any? ? [ '', warned.join('%r') ] : [])).compact.join('%r')
      end

      def self.close_job(creature, by, message)
        job = creature.approval_job_id ? Job[creature.approval_job_id] : nil
        Jobs.close_job(by, job, message) if job
        Pf2eCreature[creature.id]&.update(:approval_job_id => nil)
      end

      # An author is not told of their own decision, which an admin may make on a creature of theirs.
      def self.decided(creature, by, decision, note)
        done = CreatureReview::DECISIONS.fetch(decision)
        own = decision == 'approve' && Pf2eCreature[creature.id]&.approved_for == 'author'
        message = t("pf2e.creature_#{own ? 'approved_own' : done}", :name => creature.name, :by => by.name, :reason => note)

        Global.logger.info "PF2 creature c:#{creature.id} #{creature.name} #{done} by #{by.name}"
        Login.notify(creature.owner, :pf2_creature, message, creature.id) if creature.owner && creature.owner != by
        close_job(creature, by, message) if %w{approve reject}.include?(decision)
        message
      end
    end
  end
end
