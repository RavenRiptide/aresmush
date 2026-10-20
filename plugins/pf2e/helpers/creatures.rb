module AresMUSH
  module Pf2e

    # The creatures a GM names: the bestiary's, and those saved by the game's players (`Pf2eCreature`).
    #
    # A name resolves in this order, so that every bestiary name keeps its meaning:
    #
    #   c:<id>, c:<name>   a saved creature, and only that (`custom:` too)
    #   a bestiary name    exactly, as it always has
    #   one of your own    exactly
    #   anyone else's      exactly, among those you may do this with
    #   part of a name     across both; one match is it, several are listed
    #
    # Answers a ref: `{ 'source' => 'bestiary', 'name' }`, or `{ 'source' => 'saved', 'name', 'creature',
    # 'revision' }`, the revision being the one this character gets (`CreatureAccess.latest?`).
    module Creatures

      SAVED = /\Ac(?:ustom)?:\s*(.+)\z/im
      LISTED = 8

      def self.row(creature)
        owner = creature.owner
        { 'id' => creature.id.to_s, 'name' => creature.name, 'owner_id' => creature.owner_id&.to_s,
          'owner_runs_own' => !owner.nil? && Gm.plotmaster?(owner),
          'owner_name' => creature.owner_name, 'audience' => creature.audience || 'private',
          'shared_with' => Array(creature.shared_with).map(&:to_s), 'head' => creature.head_id,
          'published' => creature.published_id, 'submitted' => creature.submitted_id, 'retired' => !creature.retired_at.nil?,
          'approved_for' => creature.approved_for || 'everyone',
          'level' => creature.level.to_i, 'status' => creature.status }
      end

      def self.all
        Pf2eCreature.all.to_a
      end

      # Saved creatures a bestiary name now takes, which an import can make: the bestiary's creature wins
      # the name, and the saved one is reached by `c:` until it is renamed. `rake pf2e:creature_clashes`.
      def self.clashes
        all.reject(&:retired_at).select { |creature| Bestiary.named(creature.name) }
      end

      # Those awaiting an admin's approval, longest waiting first.
      def self.waiting
        all.select(&:submitted_id).sort_by { |creature| creature.submitted.created_at.to_s }
      end

      # Everything done to one, oldest first: `{ 'at', 'by', 'kind', 'revision', 'summary', 'detail' }`. What
      # changed belongs to the event that made the revision, not to one that only names it.
      MADE = %w{created revised renamed}.freeze

      def self.history(creature)
        summaries = creature.revisions.to_a.to_h { |one| [ one.number, one.summary ] }

        creature.events.to_a.sort_by { |one| [ one.created_at.to_s, one.id.to_i ] }.map do |one|
          # An event that names no revision reads back as 0; revisions count from 1.
          revision = one.revision.to_i.positive? ? one.revision : nil

          { 'at' => one.created_at.to_s[0, 16], 'by' => one.by, 'kind' => one.kind, 'revision' => revision,
            'summary' => MADE.include?(one.kind) ? summaries[revision] : nil, 'detail' => one.detail || {} }
        end
      end

      # The characters a share of this creature names, each one who may be named in it.
      def self.sharers(names, creature)
        named = names.map { |name| [ name, Character.find_one_by_name(name) ] }
        refused = named.find { |_name, char| char && !CreatureAccess.shareable?(CreatureAccess.actor(char), row(creature)) }

        return Err.new(:not_found, 'pf2e.char_not_found') if named.any? { |_name, char| char.nil? }
        return Err.new(:creature_share_who, 'pf2e.creature_share_who', 'name' => refused.last.name) if refused

        Ok.new(:state => named.map(&:last))
      end

      # Saved creatures this character may do this with.
      def self.allowed(char, action)
        actor = CreatureAccess.actor(char)

        all.select { |creature| CreatureAccess.may(actor, action, row(creature)).ok? }
      end

      # The revision of a saved creature this character gets: its latest for its author and those it is
      # shared with, the published one for anyone else.
      def self.revision_for(char, creature)
        latest = CreatureAccess.latest?(CreatureAccess.actor(char), row(creature))

        latest ? creature.head : creature.published
      end

      # The revision of one to show this character: its latest to its author and to admins, who may change
      # it, and otherwise the one they get.
      def self.shown(char, ref)
        return ref['revision'] unless ref['source'] == 'saved'

        creature = ref['creature']
        actor = CreatureAccess.actor(char)

        CreatureAccess.owner?(actor, row(creature)) || CreatureAccess.admin?(actor) ? creature.head : ref['revision']
      end

      # The stat block of a ref, as this character is shown it.
      def self.shown_block(char, ref)
        ref['source'] == 'saved' ? shown(char, ref)&.block : Bestiary.entry(ref['name'])
      end

      def self.ref(char, creature)
        { 'source' => 'saved', 'name' => creature.name, 'creature' => creature, 'revision' => revision_for(char, creature) }
      end

      def self.labelled(creature)
        "c:#{creature.id} #{creature.name} (#{creature.owner_name})"
      end

      def self.find(char, term, action = 'view')
        wanted = term.to_s.strip
        forced = wanted.match(SAVED)

        return saved(char, forced[1].strip, action) if forced

        named = Bestiary.named(wanted)
        return Ok.new(:state => { 'source' => 'bestiary', 'name' => named }) if named

        exactly = exact(char, wanted, action)
        return exactly if exactly

        partly(char, wanted, action)
      end

      # `c:12` or `c:barrow hound`: saved creatures only.
      def self.saved(char, term, action)
        if term.match?(/\A\d+\z/)
          creature = Pf2eCreature[term]
          allowed = creature && CreatureAccess.may(CreatureAccess.actor(char), action, row(creature)).ok?

          return allowed ? Ok.new(:state => ref(char, creature)) : Err.new(:not_found, 'pf2e.creature_not_found', 'creature' => "c:#{term}")
        end

        exact(char, term, action) || Err.new(:not_found, 'pf2e.creature_not_found', 'creature' => "c:#{term}")
      end

      # By whole name: their own first, then others'.
      def self.exact(char, term, action)
        wanted = Domains.slug(term)
        named = allowed(char, action).select { |creature| creature.name_slug == wanted }
        own = named.select { |creature| creature.owner_id.to_s == char.id.to_s }

        return Ok.new(:state => ref(char, own.first)) if own.size == 1
        return Ok.new(:state => ref(char, named.first)) if named.size == 1
        return ambiguous(term, named.map { |creature| labelled(creature) }) if named.size > 1

        nil
      end

      def self.partly(char, term, action)
        wanted = Domains.slug(term)
        beasts = Bestiary.index.keys.select { |name| Domains.slug(name).include?(wanted) }
        saved = allowed(char, action).select { |creature| creature.name_slug.to_s.include?(wanted) }

        return Ok.new(:state => { 'source' => 'bestiary', 'name' => beasts.first }) if beasts.size == 1 && saved.empty?
        return Ok.new(:state => ref(char, saved.first)) if saved.size == 1 && beasts.empty?
        return Err.new(:not_found, 'pf2e.creature_not_found', 'creature' => term) if beasts.empty? && saved.empty?

        ambiguous(term, saved.map { |creature| labelled(creature) } + beasts)
      end

      def self.ambiguous(term, options)
        Err.new(:ambiguous, 'pf2e.creature_ambiguous', 'creature' => term, 'options' => options.first(LISTED).join(', '))
      end

      # The stat block a ref names.
      def self.block(ref)
        ref['source'] == 'saved' ? ref['revision']&.block : Bestiary.entry(ref['name'])
      end

      # Whether a character may add what a ref names to an encounter.
      def self.usable?(char, ref)
        return Gm.open?(char, ref['name']) if ref['source'] == 'bestiary'

        !ref['revision'].nil? && CreatureAccess.may(CreatureAccess.actor(char), 'use', row(ref['creature'])).ok?
      end

      # What changed from one block to the next, for a revision's summary: `AC 18 to 19; Strike Claw added`.
      FIGURES = { 'ac' => 'AC', 'hp' => 'HP', 'level' => 'level', 'perception' => 'Perception', 'hardness' => 'Hardness',
                  'shape' => 'starting shape' }.freeze

      def self.changes(was, now)
        was ||= {}
        said = FIGURES.filter_map { |field, word| was[field] == now[field] ? nil : "#{word} #{was[field] || '-'} to #{now[field] || '-'}" }
        said += %w{fortitude reflex will}.filter_map do |save|
          before = (was['saves'] || {})[save]
          after = (now['saves'] || {})[save]
          before == after ? nil : "#{save.capitalize} #{before || '-'} to #{after || '-'}"
        end
        said += named_changes(was['strikes'], now['strikes'], 'Strike') + named_changes(was['actions'], now['actions'], 'ability')
        said += %w{traits immunities weaknesses resistances skills senses spellcasting shield size rarity}.filter_map do |field|
          was[field] == now[field] ? nil : "#{field.tr('_', ' ')} changed"
        end

        said.empty? ? 'no change' : said.join('; ')
      end

      def self.named_changes(was, now, what)
        before = Array(was).to_h { |one| [ one['name'].to_s, one ] }
        after = Array(now).to_h { |one| [ one['name'].to_s, one ] }

        (after.keys - before.keys).map { |name| "#{what} #{name} added" } +
          (before.keys - after.keys).map { |name| "#{what} #{name} removed" } +
          (after.keys & before.keys).reject { |name| after[name] == before[name] }.map { |name| "#{what} #{name} changed" }
      end
    end
  end
end
