module AresMUSH
  module Pf2e

    # What writes a saved creature, so no command writes the models itself: a new creature, a new
    # revision, and the events that say who did what.
    module CreatureStore

      # A block as a saved creature keeps it: its own name, said to be custom, and nothing of the pack it
      # may have been cloned from.
      def self.kept(creature_name, owner_name, block)
        block.except('pack', 'adjustment').merge('name' => creature_name, 'source' => "Custom: #{owner_name}")
      end

      # Whether a name is free for this author: none of their own other creatures has it, and no other
      # published one, which anyone may name, has it either. A retired creature holds no name.
      def self.name_free(owner, name, creature = nil)
        slug = Domains.slug(name)
        others = Pf2eCreature.find(:name_slug => slug).to_a.reject { |one| one.retired_at || (creature && one.id == creature.id) }
        own = others.find { |one| one.owner_id.to_s == owner.id.to_s }
        published = others.find(&:published_id)

        return Err.new(:creature_name_yours, 'pf2e.creature_name_yours', 'name' => own.name) if own
        return Err.new(:creature_published_name, 'pf2e.creature_published_name', 'name' => name, 'other' => Creatures.labelled(published)) if published

        Ok.new(:state => name)
      end

      def self.create!(char, name, block, cloned_from: nil)
        creature = Pf2eCreature.create(:name => name, :name_slug => Domains.slug(name), :owner => char, :owner_name => char.name,
                                       :audience => 'private', :cloned_from => cloned_from)
        revise!(creature, block, char, :kind => 'created')

        Pf2eCreature[creature.id]
      end

      # A new revision, where the block has changed: the head moves to it and the lists' fields follow.
      # Answers it, or nothing where nothing changed.
      def self.revise!(creature, block, by, kind: 'revised', detail: {}, summary: nil)
        creature = Pf2eCreature[creature.id]
        block = kept(creature.name, creature.owner_name, block)
        head = creature.head

        return nil if head && head.block == block

        number = creature.revisions.to_a.map { |one| one.number.to_i }.max.to_i + 1
        revision = Pf2eCreatureRevision.create(:creature => creature, :number => number, :block => block, :by => by.name,
                                               :by_id => by.id, :summary => summary || (head ? Creatures.changes(head.block, block) : 'created'))

        creature.update(:head => revision, :level => block['level'].to_i, :traits => Array(block['traits']))
        event!(creature, kind, by, :revision => number, :detail => detail)

        revision
      end

      def self.event!(creature, kind, by, revision: nil, detail: {})
        Pf2eCreatureEvent.create(:creature => creature, :kind => kind, :by => by.name, :by_id => by.id, :revision => revision,
                                 :detail => detail)
      end

      # A new name, which every revision from now on carries.
      def self.rename!(creature, name, by)
        creature = Pf2eCreature[creature.id]
        was = creature.name

        creature.update(:name => name, :name_slug => Domains.slug(name))
        revise!(creature, creature.head.block, by, :kind => 'renamed', :detail => { 'from' => was, 'to' => name }, :summary => "renamed from #{was}")
      end

      def self.share!(creature, audience, shared_with, by)
        Pf2eCreature[creature.id].update(:audience => audience, :shared_with => shared_with.map(&:to_s))
        event!(creature, 'shared', by, :detail => { 'audience' => audience, 'with' => shared_with.map(&:to_s) })
      end

      # Retired, it is off the lists and out of use, any request for approval with it; and out of the
      # house bestiary, where it was published.
      def self.retire!(creature, by, retired)
        creature = Pf2eCreature[creature.id]
        creature.update(:retired_at => retired ? Time.now : nil, :submitted => retired ? nil : creature.submitted)
        event!(creature, retired ? 'retired' : 'restored', by)
        HouseBestiary.write! if creature.published_id
      end

      # Their published creatures stay, for staff to hand on, with the name they were saved under; the rest
      # are retired. The game does not delete approved characters, so this is for the deletion staff make.
      def self.owner_deleted(char)
        Pf2eCreature.find(:owner_id => char.id).to_a.each do |creature|
          creature.update(:owner => nil, :owner_name => creature.owner_name || char.name)
          creature.update(:retired_at => Time.now) unless creature.published_id || creature.retired_at
        end
      end

      def self.notes!(creature, notes, by)
        Pf2eCreature[creature.id].update(:notes => notes)
        event!(creature, 'notes', by)
      end
    end
  end
end
