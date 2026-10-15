module AresMUSH
  module Pf2e

    # Who hears of a creature's review: the admins of a submission, and its author of an admin's decision.
    # Each answers the message it sent, for the one who acted to be told too.
    module CreatureNotices

      def self.submitted(creature, by)
        message = t('pf2e.creature_awaits', :name => creature.name, :id => creature.id, :author => by.name)
        Global.notifier.notify_ooc(:pf2_creature, message) { |one| one && one.is_admin? }
        message
      end

      # An author is not told of their own decision, which an admin may make on a creature of theirs.
      def self.decided(creature, by, decision, note)
        done = CreatureReview::DECISIONS.fetch(decision)
        message = t("pf2e.creature_#{done}", :name => creature.name, :by => by.name, :reason => note)

        Global.logger.info "PF2 creature c:#{creature.id} #{creature.name} #{done} by #{by.name}"
        Login.notify(creature.owner, :pf2_creature, message, creature.id) if creature.owner && creature.owner != by
        message
      end
    end
  end
end
