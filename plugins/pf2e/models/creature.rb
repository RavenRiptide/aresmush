module AresMUSH

  # A creature someone has saved, to add to an encounter by name as one from the bestiary is
  # (`Pf2e::Creatures`). What it is lives in its revisions: each edit is a new one, never rewritten, and
  # an encounter keeps the one it was added with. `head` is the latest; `published` the one an admin
  # approved, which anyone may use; `submitted` the one awaiting an admin.
  #
  # Its status is read from these, not kept: retired, submitted, published, or a draft.
  class Pf2eCreature < Ohm::Model
    include ObjectModel

    attribute :name
    attribute :name_slug
    index :name_slug

    reference :owner, "AresMUSH::Character"
    # The owner's name as it was, for a creature whose owner has gone.
    attribute :owner_name

    # private, shared (with `shared_with`, character ids), or plotmasters.
    attribute :audience, :default => 'private'
    attribute :shared_with, :type => DataType::Array, :default => []

    reference :head, "AresMUSH::Pf2eCreatureRevision"
    reference :published, "AresMUSH::Pf2eCreatureRevision"
    reference :submitted, "AresMUSH::Pf2eCreatureRevision"
    # What the author said in submitting it, and what an admin said in sending it back.
    attribute :submitted_note
    attribute :review_note
    attribute :retired_at, :type => DataType::Time

    # Whom the author asked approval for, and whom the published revision is approved for: `everyone`,
    # or `author` - their own storylines, and those they share it with.
    attribute :submitted_for
    attribute :approved_for
    # The job staff discuss a submission in, while it waits.
    attribute :approval_job_id

    # The head's, for lists that need not read a block.
    attribute :level, :type => DataType::Integer
    attribute :traits, :type => DataType::Array, :default => []

    # The author's own notes, no part of the stat block.
    attribute :notes
    # Where it began: `bestiary:Goblin Warrior`, `saved:12`, `encounter`, `described`.
    attribute :cloned_from

    collection :revisions, "AresMUSH::Pf2eCreatureRevision", :creature
    collection :events, "AresMUSH::Pf2eCreatureEvent", :creature

    before_delete :delete_history

    def delete_history
      self.revisions.each(&:delete)
      self.events.each(&:delete)
    end

    def status
      return 'retired' if self.retired_at
      return 'submitted' if self.submitted_id
      return 'approved' if self.published_id && self.approved_for == 'author'
      return 'published' if self.published_id

      'draft'
    end
  end

  # One state of a saved creature's stat block, in the bestiary's shape. Never rewritten.
  class Pf2eCreatureRevision < Ohm::Model
    include ObjectModel

    reference :creature, "AresMUSH::Pf2eCreature"
    attribute :number, :type => DataType::Integer
    attribute :block, :type => DataType::Hash, :default => {}
    attribute :by
    attribute :by_id
    # What changed from the one before: `AC 18 to 19; Strike Claw added`.
    attribute :summary
  end

  # Anything else that happened to a saved creature: shared, submitted, approved, retired.
  class Pf2eCreatureEvent < Ohm::Model
    include ObjectModel

    reference :creature, "AresMUSH::Pf2eCreature"
    attribute :kind
    attribute :by
    attribute :by_id
    attribute :revision, :type => DataType::Integer
    attribute :detail, :type => DataType::Hash, :default => {}
  end
end
