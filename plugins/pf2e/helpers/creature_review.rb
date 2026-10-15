module AresMUSH
  module Pf2e

    # An admin's approval of a saved creature, which publishes it for everyone (Raven, 2026-10-14). The
    # author submits the head; an admin approves it, and that revision is what anyone else gets from then
    # on, however the author edits it after; or sends it back with a reason. An admin may unpublish one.
    #
    # Every approval and unpublishing rewrites the house bestiary file (`HouseBestiary`).
    module CreatureReview

      def self.submit!(creature, by, note)
        creature = Pf2eCreature[creature.id]

        return Err.new(:creature_retired, 'pf2e.creature_retired', 'name' => creature.name) if creature.retired_at
        return Err.new(:creature_submitted, 'pf2e.creature_submitted', 'name' => creature.name) if creature.submitted_id
        return Err.new(:creature_nothing_new, 'pf2e.creature_nothing_new', 'name' => creature.name) if creature.head_id == creature.published_id

        creature.update(:submitted => creature.head, :submitted_note => note.to_s.strip, :review_note => nil)
        CreatureStore.event!(creature, 'submitted', by, :revision => creature.head.number, :detail => { 'note' => note.to_s.strip })

        Ok.new(:state => creature)
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

        clash = Pf2eCreature.find(:name_slug => creature.name_slug).to_a.find { |other| other.id != creature.id && other.published_id }

        return Err.new(:creature_published_name, 'pf2e.creature_published_name', 'name' => creature.name, 'other' => Creatures.labelled(clash)) if clash

        revision = creature.submitted
        creature.update(:published => revision, :submitted => nil, :review_note => nil)
        CreatureStore.event!(creature, 'approved', by, :revision => revision.number)
        HouseBestiary.write!

        Ok.new(:state => creature)
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
        HouseBestiary.write!

        Ok.new(:state => creature)
      end
    end

    # The creatures admins have approved, written out as a bestiary file beside Foundry's, to keep with the
    # game in git: they survive the loss of the database and read as text (Raven, 2026-10-14). The game
    # reads saved creatures from the database, not from here.
    module HouseBestiary

      def self.path
        File.join(Bestiary.dir, 'house.yml')
      end

      def self.blocks
        Pf2eCreature.all.to_a.select(&:published_id).sort_by(&:name).to_h do |creature|
          [ creature.name, creature.published.block.merge('approved' => creature.published.number) ]
        end
      end

      def self.write!
        # Plain hashes, which any YAML reader takes, not the database's own kinds of them.
        held = JSON.parse(JSON.dump(blocks))
        header = "# The game's own creatures, as admins approved them. Written by the game (`Pf2e::HouseBestiary`); kept in git.\n"

        File.write(path, header + (held.empty? ? "--- {}\n" : held.to_yaml))
      end
    end
  end
end
