module AresMUSH
  module Pf2e

    # An admin's approval of a saved creature, which publishes it for everyone (Raven, 2026-10-14) or, as
    # its author asks, for their own storylines only (2026-10-20). The author submits the head; an admin
    # approves it, and that revision is what anyone else gets from then on, however the author edits it
    # after; or sends it back with a reason. An admin may unpublish one, and its author make one approved
    # for themselves public.
    #
    # Every approval, unpublishing and making public rewrites the house bestiary file (`HouseBestiary`),
    # which holds the public ones.
    module CreatureReview

      FOR = %w{everyone author}.freeze

      def self.submit!(creature, by, note, approved_for: 'everyone')
        creature = Pf2eCreature[creature.id]

        return Err.new(:creature_approved_for, 'pf2e.creature_approved_for', 'kinds' => FOR.join(', ')) unless FOR.include?(approved_for)

        return Err.new(:creature_retired, 'pf2e.creature_retired', 'name' => creature.name) if creature.retired_at
        return Err.new(:creature_submitted, 'pf2e.creature_submitted', 'name' => creature.name) if creature.submitted_id
        return Err.new(:creature_nothing_new, 'pf2e.creature_nothing_new', 'name' => creature.name) if creature.head_id == creature.published_id

        refused = CreatureSaving.invalid(creature.head.block)
        return refused if refused

        creature.update(:submitted => creature.head, :submitted_note => note.to_s.strip, :submitted_for => approved_for, :review_note => nil)
        CreatureStore.event!(creature, 'submitted', by, :revision => creature.head.number, :detail => { 'note' => note.to_s.strip, 'for' => approved_for })

        Ok.new(:state => creature)
      end

      # What each decision an admin may make is called once it is made.
      DECISIONS = { 'approve' => 'approved', 'reject' => 'rejected', 'unpublish' => 'unpublished' }.freeze

      # An admin's decision by name, with the reason a rejection needs.
      def self.decide!(creature, by, decision, note)
        case decision
        when 'approve' then approve!(creature, by)
        when 'reject' then reject!(creature, by, note)
        when 'unpublish' then unpublish!(creature, by)
        else Err.new(:creature_decision, 'pf2e.creature_decision', 'decisions' => DECISIONS.keys.join(', '))
        end
      end

      def self.withdraw!(creature, by)
        creature = Pf2eCreature[creature.id]

        return Err.new(:creature_not_submitted, 'pf2e.creature_not_submitted', 'name' => creature.name) unless creature.submitted_id

        number = creature.submitted.number
        creature.update(:submitted => nil, :submitted_note => nil)
        CreatureStore.event!(creature, 'withdrawn', by, :revision => number)

        Ok.new(:state => creature)
      end

      def self.approve!(creature, by)
        creature = Pf2eCreature[creature.id]

        return Err.new(:creature_not_submitted, 'pf2e.creature_not_submitted', 'name' => creature.name) unless creature.submitted_id

        approved_for = creature.submitted_for || 'everyone'
        clash = approved_for == 'everyone' ? public_clash(creature) : nil
        return clash if clash

        revision = creature.submitted
        creature.update(:published => revision, :approved_for => approved_for, :submitted => nil, :submitted_for => nil, :review_note => nil)
        CreatureStore.event!(creature, 'approved', by, :revision => revision.number, :detail => { 'for' => approved_for })

        HouseBestiary.told(Ok.new(:state => creature))
      end

      # One approved for its author's storylines, made public as approved: staff have reviewed it already.
      def self.make_public!(creature, by)
        creature = Pf2eCreature[creature.id]

        return Err.new(:creature_not_own_approved, 'pf2e.creature_not_own_approved', 'name' => creature.name) unless CreatureAccess.own_approved?(Creatures.row(creature))

        clash = public_clash(creature)
        return clash if clash

        creature.update(:approved_for => 'everyone')
        CreatureStore.event!(creature, 'made public', by, :revision => creature.published.number)

        HouseBestiary.told(Ok.new(:state => creature))
      end

      # Two public creatures may not share a name: anyone may name one.
      def self.public_clash(creature)
        clash = Pf2eCreature.find(:name_slug => creature.name_slug).to_a.find do |other|
          other.id != creature.id && CreatureAccess.public?(Creatures.row(other)) && !other.retired_at
        end

        clash ? Err.new(:creature_published_name, 'pf2e.creature_published_name', 'name' => creature.name, 'other' => Creatures.labelled(clash)) : nil
      end

      def self.reject!(creature, by, reason)
        creature = Pf2eCreature[creature.id]

        return Err.new(:creature_not_submitted, 'pf2e.creature_not_submitted', 'name' => creature.name) unless creature.submitted_id
        return Err.new(:creature_reason, 'pf2e.creature_reason') if reason.to_s.strip.empty?

        number = creature.submitted.number
        creature.update(:submitted => nil, :review_note => reason.to_s.strip)
        CreatureStore.event!(creature, 'rejected', by, :revision => number, :detail => { 'reason' => reason.to_s.strip })

        Ok.new(:state => creature)
      end

      def self.unpublish!(creature, by)
        creature = Pf2eCreature[creature.id]

        return Err.new(:creature_not_published, 'pf2e.creature_not_published', 'name' => creature.name) unless creature.published_id

        number = creature.published.number
        creature.update(:published => nil)
        CreatureStore.event!(creature, 'unpublished', by, :revision => number)

        HouseBestiary.told(Ok.new(:state => creature))
      end
    end

    # The creatures admins have approved, written out as a bestiary file beside Foundry's, to keep with the
    # game in git: they survive the loss of the database and read as text (Raven, 2026-10-14). The game
    # reads saved creatures from the database, not from here.
    module HouseBestiary

      def self.path
        File.join(Bestiary.dir, 'house.yml')
      end

      # Each under the name it was approved with, which a later rename does not change until it too is
      # approved.
      def self.blocks
        Pf2eCreature.all.to_a.select { |creature| CreatureAccess.public?(Creatures.row(creature)) && !creature.retired_at }.to_h do |creature|
          [ creature.published.block['name'], creature.published.block.merge('approved' => creature.published.number) ]
        end.sort.to_h
      end

      # Written whole to a file beside it and moved into place, so a reader never finds half of one. The
      # database is the record: a file that cannot be written is said, and changes nothing there.
      def self.write!
        # Plain hashes, which any YAML reader takes, not the database's own kinds of them.
        held = JSON.parse(JSON.dump(blocks))
        header = "# The game's own creatures, as admins approved them. Written by the game (`Pf2e::HouseBestiary`); kept in git.\n"
        fresh = "#{path}.new"

        File.write(fresh, header + (held.empty? ? "--- {}\n" : held.to_yaml))
        File.rename(fresh, path)
        nil
      rescue SystemCallError => e
        Global.logger.error "The house bestiary could not be written to #{path}: #{e.message}"
        e.message
      end

      # An outcome with the file written, and a message where it could not be.
      def self.told(outcome)
        failed = write!

        failed ? outcome.with_message('pf2e.creature_house_unwritten', 'path' => path, 'why' => failed) : outcome
      end
    end
  end
end
