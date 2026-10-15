module AresMUSH
  module Pf2e

    # Saving a stat block as a creature: a new one, a new revision of one, or either by name. The
    # `creature` commands and the web editor both save through here, and each says what came back in its
    # own way.
    #
    #   Ok(state: { 'creature', 'revision', 'created' })   revision is nil where nothing changed
    #   Err(:creature_invalid, 'errors' => findings)        CreatureCheck's, every one
    #   Err(:creature_stale, 'head' => number)              a revision since saved by someone else
    #   Err from a name                                     CreatureCheck.name, CreatureStore.name_free
    module CreatureSaving

      def self.create(char, name, block, cloned_from: nil, notes: nil)
        named = named(char, name)
        return named if named.err?

        held = block.merge('name' => named.state)
        refused = invalid(held)
        return refused if refused

        creature = CreatureStore.create!(char, named.state, held, :cloned_from => cloned_from)
        CreatureStore.notes!(creature, notes, char) if notes.to_s.strip != ''

        fresh = Pf2eCreature[creature.id]
        saved(fresh, fresh.head, true)
      end

      # Against `base_revision`, the one the editor began from, where one is given. A new name renames it;
      # notes given replace its own.
      def self.revise(char, creature, block, name: nil, base_revision: nil, notes: nil)
        creature = Pf2eCreature[creature.id]
        name = name.to_s.strip.empty? ? creature.name : name.to_s.strip

        return Err.new(:creature_stale, 'pf2e.creature_stale', 'head' => creature.head.number) if base_revision && creature.head.number != base_revision.to_i

        refused = invalid(block.merge('name' => name))
        return refused if refused

        if name != creature.name
          renamed = named(creature.owner || char, name, creature)
          return renamed if renamed.err?

          CreatureStore.rename!(creature, renamed.state, char)
        end

        revision = CreatureStore.revise!(Pf2eCreature[creature.id], block, char)
        CreatureStore.notes!(creature, notes, char) if !notes.nil? && notes.to_s != creature.notes.to_s

        saved(Pf2eCreature[creature.id], revision, false)
      end

      # A new revision of the author's own creature of this name, or a new creature. A copy (`fresh`) is
      # always a new one, and never writes over one of theirs. A retired creature holds no name.
      def self.save(char, name, block, cloned_from: nil, fresh: false)
        refused = invalid(block)
        return refused if refused

        own = Pf2eCreature.find(:name_slug => Domains.slug(name)).to_a.find { |one| one.owner_id.to_s == char.id.to_s && !one.retired_at }

        return Err.new(:creature_name_yours, 'pf2e.creature_name_yours', 'name' => own.name) if own && fresh
        return revise(char, own, block) if own

        create(char, name, block, :cloned_from => cloned_from)
      end

      def self.invalid(block)
        errors = CreatureCheck.errors(block)

        errors.any? ? Err.new(:creature_invalid, 'pf2e.creature_invalid', 'errors' => errors) : nil
      end

      def self.named(owner, name, creature = nil)
        CreatureCheck.name(name).and_then { |checked| CreatureStore.name_free(owner, checked, creature) }
      end

      def self.saved(creature, revision, created)
        Ok.new(:state => { 'creature' => creature, 'revision' => revision, 'created' => created })
      end
    end
  end
end
