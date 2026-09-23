module AresMUSH
  module Pf2e

    # What a character carries in an encounter: a copy of their gear, what they wear, wield and have
    # invested, and their money, taken as they enter it.
    #
    # Everything in the encounter - their sheet there, their Strikes and AC, what they use - reads and
    # changes the copy, so what they buy or sell outside meanwhile is no part of it. A character carrying on
    # from an earlier encounter carries that one's copy on. When the encounter ends, what they used up of
    # their own consumables comes off their own inventory, and their money and anything that lasts no longer
    # than the encounter stay with it.
    #
    # An item that something made rather than the character owning it says so: `granted_by` what made it,
    # and `expires` when it goes - `encounter` for what the encounter gave out, `rest` for what lasts until
    # the next daily preparations, nothing for what they keep. An alchemist's preparations and ammunition
    # will be made this way; see `docs/plans/2026-09-22-made-and-granted-items.md`.
    module Equipment

      # The kinds of item, by the collection a holder keeps each in. Bags first, so an item in one can be
      # put in the bag's copy.
      def self.kinds
        [ [ 'bags', PF2Bag ] ] + Pf2egear::Inventory::CATEGORIES.map do |row|
          [ row['collection'].to_s, AresMUSH.const_get(row['model']) ]
        end
      end

      # The links between items, which a copy points at the other copies.
      LINKS = %w{bag shield weapon}.freeze

      # Something made an item for whoever holds it: the encounter gave it out, a rest prepared it, a
      # character crafted it. `expires` says how long it lasts.
      def self.grant!(holder, category, name, quantity, info, granted_by:, expires: nil)
        item = Pf2egear.create_item(holder, category, name, quantity, info)

        item.update(:granted_by => granted_by, :expires => expires)

        item
      end

      # What lasts no longer than this, gone: the day's preparations at the next rest, what Quick Alchemy
      # made at the maker's next turn. A creature carries nothing of its own, so it has none of this.
      def self.lapse!(holder, expires)
        return unless Actors.of(holder).carries_items?

        kinds.each do |collection, _model|
          holder.public_send(collection).to_a.select { |item| item.expires == expires }.each(&:delete)
        end
      end

      def self.copies(state)
        kinds.flat_map { |collection, _model| state.public_send(collection).to_a }
      end

      # Copies what `from` carries - a character, or their state in an earlier encounter - to `state`.
      def self.copy!(state, from)
        copied = {}
        made = []

        kinds.each do |collection, model|
          from.public_send(collection).to_a.each do |item|
            own = item.attributes.except(:character_id, :state_id, :created_at, :updated_at, :copied_from,
                                         *LINKS.map { |link| :"#{link}_id" })
            copy = model.create(own.merge(:state => state, :copied_from => item.copied_from || item.id))

            copied[[ model, item.id ]] = copy
            made << [ item, copy ]
          end
        end

        made.each do |item, copy|
          links = LINKS.select { |link| item.respond_to?(link) && item.public_send(link) }
                       .to_h { |link| [ link.to_sym, copied[[ item.public_send(link).class, item.public_send(link).id ]] ] }

          copy.update(links) unless links.empty?
        end

        state.update(:pf2_money => from.pf2_money.to_i, :consumables_at_start => started_with(state))
      end

      # The encounter has ended: what it did to the character's own consumables happens to them. What it
      # gave out was the encounter's, and goes no further. Answers what it could not do - an item they no
      # longer have - as events, for whoever tells it.
      # What of the copy becomes the character's own when the encounter ends: anything it made that outlasts
      # it. What it gave out for the encounter alone goes with it.
      def self.kept(state)
        kinds.flat_map do |collection, model|
          state.public_send(collection).to_a.reject(&:copied_from).reject { |one| one.expires == 'encounter' }
               .map { |one| [ model, one ] }
        end
      end

      def self.settle!(state)
        char = state.character

        return [] unless char

        now = state.consumables.to_a
        held = now.select(&:copied_from).to_h { |one| [ one.copied_from.to_s, one ] }
        missed = []

        (state.consumables_at_start || {}).each do |source, started|
          used = started['quantity'].to_i - (held[source]&.quantity).to_i

          next unless used.positive?

          missed << used_up(char, source, started['name'], used)
        end

        kept(state).each do |model, gained|
          own = gained.attributes.except(:character_id, :state_id, :created_at, :updated_at, :copied_from,
                                         *LINKS.map { |link| :"#{link}_id" })

          gained.update(:copied_from => model.create(own.merge(:character => char)).id)
        end

        # Settled up to here: an encounter restarted and ended again settles only what happened since.
        state.update(:consumables_at_start => started_with(state))

        missed.compact
      end

      # What they came in with, by the item of their own each copy was taken from. What the encounter gave
      # them has none, and settles nothing.
      def self.started_with(state)
        state.consumables.to_a.select(&:copied_from)
             .to_h { |one| [ one.copied_from.to_s, { 'quantity' => one.quantity.to_i, 'name' => one.name } ] }
      end

      def self.used_up(char, source, name, used)
        item = PF2Consumable[source]

        return Turns.event('pf2e.settle_missing', 'name' => char.name, 'item' => name) unless item && item.character == char

        left = item.quantity.to_i - used

        left.positive? ? item.update(:quantity => left) : item.delete

        nil
      end
    end
  end
end
