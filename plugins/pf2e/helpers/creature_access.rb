module AresMUSH
  module Pf2e

    # Who may do what with a saved creature (`Pf2eCreature`).
    #
    # Anyone approved authors one. A Plotmaster or an admin uses their own, and those another Plotmaster
    # or admin shares with them, as they stand. Anyone else - a player, or an author who has stopped being
    # a Plotmaster - uses a creature only once an admin has approved it, which publishes that revision for
    # everyone. Admins approve, and may do anything. Raven set this out on 2026-10-14.
    #
    # An author may ask instead for approval for their own storylines only (Raven, 2026-10-20). Approved
    # so, it is theirs and those they name to use, as approved, and hidden from everyone else. They may
    # make it public themselves, since staff have reviewed it, and retire it, as a public one's may not.
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
      # admin, only while they are one, and only from an author who may use it unapproved themselves - a
      # player's creature reaches nobody unapproved, nor does a Plotmaster's once they stop being one.
      def self.reaches?(actor, row)
        runs_own?(actor) && row['owner_runs_own'] &&
          (row['audience'] == 'plotmasters' || Array(row['shared_with']).map(&:to_s).include?(actor['id'].to_s))
      end

      # Approved: for everyone, or for its author's storylines only.
      def self.published?(row)
        !row['published'].nil?
      end

      def self.public?(row)
        published?(row) && row['approved_for'] != 'author'
      end

      def self.own_approved?(row)
        published?(row) && row['approved_for'] == 'author'
      end

      # One approved for its author's storylines, shared by name: whoever is named uses it as approved.
      def self.named_in?(actor, row)
        own_approved?(row) && Array(row['shared_with']).map(&:to_s).include?(actor['id'].to_s)
      end

      def self.retired?(row)
        row['retired'] ? true : false
      end

      # Who may be named in a share: a Plotmaster or admin, or anyone approved where the creature is
      # approved for its author's storylines.
      def self.shareable?(actor, row = {})
        runs_own?(actor) || (own_approved?(row) && actor['approved'] ? true : false)
      end

      # Who a creature is shared with: every Plotmaster, or those named, or nobody but its author.
      def self.audience(plotmasters, ids)
        return 'plotmasters' if plotmasters

        ids.any? ? 'shared' : 'private'
      end

      # A share's audience, where it can reach them: every Plotmaster is reached only by a creature whose
      # author uses their own unapproved.
      def self.share(row, plotmasters, ids)
        return Err.new(:creature_share_plotmasters, 'pf2e.creature_share_plotmasters') if plotmasters && !row['owner_runs_own']

        Ok.new(:state => audience(plotmasters, ids))
      end

      # The lists creatures are shown in, each of those an actor may view.
      SCOPES = {
        'mine' => ->(actor, row) { owner?(actor, row) },
        'shared' => ->(actor, row) { !owner?(actor, row) && (reaches?(actor, row) || named_in?(actor, row)) },
        'published' => ->(_actor, row) { public?(row) },
        'all' => ->(_actor, _row) { true }
      }.freeze

      def self.in_scope?(actor, row, scope)
        SCOPES.fetch(scope).call(actor, row)
      end

      # Whether they get its latest revision, as its author left it, rather than the one published.
      def self.latest?(actor, row)
        admin?(actor) || (runs_own?(actor) && (owner?(actor, row) || reaches?(actor, row)))
      end

      ACTIONS = {
        'create' => ->(actor, _row) { admin?(actor) || actor['approved'] },
        'view' => ->(actor, row) { admin?(actor) || owner?(actor, row) || (!retired?(row) && (reaches?(actor, row) || public?(row) || named_in?(actor, row))) },
        'use' => ->(actor, row) { !retired?(row) && (latest?(actor, row) || public?(row) || (own_approved?(row) && (owner?(actor, row) || named_in?(actor, row)))) },
        'clone' => ->(actor, row) { ACTIONS['view'].call(actor, row) },
        'edit' => ->(actor, row) { admin?(actor) || owner?(actor, row) },
        'share' => ->(actor, row) { admin?(actor) || (owner?(actor, row) && (runs_own?(actor) || own_approved?(row))) },
        'submit' => ->(actor, row) { admin?(actor) || owner?(actor, row) },
        'review' => ->(actor, _row) { admin?(actor) },
        'retire' => ->(actor, row) { admin?(actor) || (owner?(actor, row) && !public?(row)) },
        'make_public' => ->(actor, row) { own_approved?(row) && (admin?(actor) || owner?(actor, row)) },
        'purge' => ->(actor, _row) { admin?(actor) },
        'hand' => ->(actor, _row) { admin?(actor) }
      }.freeze

      def self.may(actor, action, row = {})
        allowed = ACTIONS.fetch(action.to_s).call(actor, row)

        allowed ? Ok.new(:state => row) : Err.new(:creature_may_not, 'pf2e.creature_may_not', 'action' => action.to_s)
      end
    end
  end
end
