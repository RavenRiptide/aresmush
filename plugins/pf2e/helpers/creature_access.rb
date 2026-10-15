module AresMUSH
  module Pf2e

    # Who may do what with a saved creature (`Pf2eCreature`).
    #
    # Anyone approved authors one. A Plotmaster or an admin uses their own, and those another Plotmaster
    # or admin shares with them, as they stand. Anyone else - a player, or an author who has stopped being
    # a Plotmaster - uses a creature only once an admin has approved it, which publishes that revision for
    # everyone. Admins approve, and may do anything. Raven set this out on 2026-10-14.
    #
    # Pure: an actor is `{ 'id', 'kind' => Gm.kind(char), 'approved' }` (`actor`), and a creature is its
    # row (`Creatures.row`).
    module CreatureAccess

      def self.actor(char)
        { 'id' => char.id.to_s, 'kind' => Gm.kind(char), 'approved' => char.is_approved? ? true : false }
      end

      def self.admin?(actor)
        actor['kind'] == 'staff'
      end

      # A Plotmaster or an admin: who uses creatures nobody has approved.
      def self.runs_own?(actor)
        actor['kind'] != 'event runner'
      end

      def self.owner?(actor, row)
        !row['owner_id'].nil? && row['owner_id'].to_s == actor['id'].to_s
      end

      # Shared with them: by name, or with every Plotmaster. A share reaches only a Plotmaster or an
      # admin, and only while they are one.
      def self.reaches?(actor, row)
        runs_own?(actor) && (row['audience'] == 'plotmasters' || Array(row['shared_with']).map(&:to_s).include?(actor['id'].to_s))
      end

      def self.published?(row)
        !row['published'].nil?
      end

      def self.retired?(row)
        row['retired'] ? true : false
      end

      # Who may be named in a share.
      def self.shareable?(actor)
        runs_own?(actor)
      end

      # Whether they get its latest revision, as its author left it, rather than the one published.
      def self.latest?(actor, row)
        admin?(actor) || (runs_own?(actor) && (owner?(actor, row) || reaches?(actor, row)))
      end

      ACTIONS = {
        'create' => ->(actor, _row) { admin?(actor) || actor['approved'] },
        'view' => ->(actor, row) { admin?(actor) || owner?(actor, row) || (!retired?(row) && (reaches?(actor, row) || published?(row))) },
        'use' => ->(actor, row) { !retired?(row) && (latest?(actor, row) || published?(row)) },
        'clone' => ->(actor, row) { ACTIONS['view'].call(actor, row) },
        'edit' => ->(actor, row) { admin?(actor) || owner?(actor, row) },
        'share' => ->(actor, row) { admin?(actor) || owner?(actor, row) },
        'submit' => ->(actor, row) { admin?(actor) || owner?(actor, row) },
        'review' => ->(actor, _row) { admin?(actor) },
        'retire' => ->(actor, row) { admin?(actor) || (owner?(actor, row) && !published?(row)) },
        'purge' => ->(actor, _row) { admin?(actor) }
      }.freeze

      def self.may(actor, action, row = {})
        allowed = ACTIONS.fetch(action.to_s).call(actor, row)

        allowed ? Ok.new(:state => row) : Err.new(:creature_may_not, 'pf2e.creature_may_not', 'action' => action.to_s)
      end
    end
  end
end
