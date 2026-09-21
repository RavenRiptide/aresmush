require 'json'

module AresMUSH
  module Pf2e

    # An encounter's history: every change in it, which the GM can take back and put back.
    #
    # A change is recorded as the whole encounter before and after it - its order, turn, cover and
    # concealment, each character's state in it, each creature, each effect - so taking one back is
    # putting the before back, whatever the change touched, and putting it back again is putting the after
    # back, with no die rolled twice.
    #
    # What its people carry is recorded too: their items and their money, which an encounter changes at
    # once because they are the characters' own. Those are the one thing a change outside the encounter
    # can move, so they go back only if they are still as the change left them, and money goes back by a
    # payment the audit records rather than by writing a balance. The history is one line: `history_at` is how many of its entries are
    # in effect, and recording a new one drops any past that point, which could only have been redone.
    #
    # An ended encounter's history is frozen.
    module History

      # What an encounter holds of its own that a change can move.
      FIELDS = %w{participants next_init round last_number cover concealment trusted current}.freeze

      # What an encounter owns, each by id: the states and creatures in it, and the effects on them. Asked
      # for rather than held in a constant, because the models load after this file.
      def self.owned
        { 'states' => [ Pf2eCombatantState, ->(encounter) { encounter.states.to_a } ],
          'npcs' => [ Pf2eNpc, ->(encounter) { encounter.npcs.to_a } ],
          'effects' => [ Pf2eEffect, ->(encounter) { Pf2eEffect.find(:encounter_id => encounter.id).to_a } ] }
      end

      KEY = :pf2e_recording

      def self.snapshot(encounter, people = [])
        encounter = PF2Encounter[encounter.id]
        held = { 'encounter' => plain(FIELDS.to_h { |field| [ field, encounter.public_send(field) ] }) }

        held.merge!(goods(people(encounter, people)))

        owned.each do |name, (_model, members)|
          held[name] = members.call(encounter).to_h do |one|
            [ one.id.to_s, plain(one.attributes.except(:created_at, :updated_at)) ]
          end
        end

        held
      end

      # The encounter as it was: what was there then is put back as it was, including what the change
      # deleted, and what the change created is gone.
      def self.restore(encounter, held)
        encounter = PF2Encounter[encounter.id]
        encounter.update(held['encounter'].transform_keys(&:to_sym))

        owned.each do |name, (model, members)|
          wanted = held[name] || {}

          members.call(encounter).each { |one| one.delete unless wanted.key?(one.id.to_s) }

          wanted.each do |id, attributes|
            attributes = attributes.transform_keys(&:to_sym)
            found = model[id]

            if found
              found.update_attributes(attributes)
              found.save
            else
              model.new(attributes.merge(:id => id)).save
            end
          end
        end
      end

      def self.plain(value)
        JSON.parse(JSON.dump(value))
      end

      # ------------------------------------------------------------------------------
      # What its people carry

      # Every character in the encounter, and anyone else a change reaches: whoever typed it, whoever
      # they paid.
      def self.people(encounter, extra = [])
        ids = Combatants.rows(encounter).map { |row| row['char'] }.compact + Array(extra).map { |one| one.respond_to?(:id) ? one.id : one }

        ids.map(&:to_s).uniq.map { |id| Character[id] }.compact
      end

      def self.goods(people)
        items = people.each_with_object({}) do |char, out|
          Pf2egear::Inventory::CATEGORIES.each do |row|
            char.public_send(row['collection']).to_a.each do |item|
              out["#{row['model']}:#{item.id}"] = plain(item.attributes.except(:created_at, :updated_at))
            end
          end
        end

        { 'people' => people.map { |char| char.id.to_s }, 'items' => items,
          'money' => people.to_h { |char| [ char.id.to_s, char.pf2_money.to_i ] } }
      end

      # What of theirs has moved since the change being taken back or put back: the first item or purse
      # that is no longer as the history expects, or nil.
      def self.moved(expected)
        people = Array(expected['people']).map { |id| Character[id] }.compact
        now = goods(people)

        changed = (now['items'].keys | Array(expected['items']&.keys)).find { |key| now['items'][key] != expected['items'][key] }
        return (now['items'][changed] || expected['items'][changed])['name'] if changed

        poorer = people.find { |char| now['money'][char.id.to_s] != expected['money'][char.id.to_s] }
        poorer ? t('pf2e.history_money_of', :name => poorer.name) : nil
      end

      def self.restore_goods(held, said)
        people = Array(held['people']).map { |id| Character[id] }.compact
        now = goods(people)

        (now['items'].keys - held['items'].keys).each { |key| item_at(key)&.delete }

        held['items'].each do |key, attributes|
          model, id = key.split(':')
          attributes = attributes.transform_keys(&:to_sym)
          found = item_at(key)

          if found
            found.update_attributes(attributes)
            found.save
          else
            AresMUSH.const_get(model).new(attributes.merge(:id => id)).save
          end
        end

        people.each do |char|
          owed = held['money'][char.id.to_s].to_i - now['money'][char.id.to_s].to_i

          Pf2egear.pay_player(char, owed, 'Encounter', said) unless owed.zero?
        end
      end

      def self.item_at(key)
        model, id = key.split(':')

        AresMUSH.const_get(model)[id]
      end

      # ------------------------------------------------------------------------------
      # Recording

      # Runs a change and records it, if it changed anything. A change inside another - `+e/as` running
      # a Strike - is part of the outer one.
      def self.recording(encounter, said, people = [])
        return yield if encounter.nil? || !encounter.is_active || Thread.current[KEY]

        Thread.current[KEY] = true
        before = snapshot(encounter, people)

        begin
          yield
        ensure
          Thread.current[KEY] = nil
        end

        after = snapshot(encounter, people)
        append(encounter, said, before, after) unless before == after
      end

      def self.entries(encounter)
        Pf2eEncounterEntry.find(:encounter_id => encounter.id).to_a.sort_by(&:seq)
      end

      def self.at(encounter)
        PF2Encounter[encounter.id].history_at.to_i
      end

      def self.append(encounter, said, before, after)
        applied = at(encounter)

        entries(encounter).select { |entry| entry.seq > applied }.each(&:delete)
        Pf2eEncounterEntry.create(:encounter => encounter, :seq => applied + 1, :said => said,
                                  :before => before, :after => after)
        PF2Encounter[encounter.id].update(:history_at => applied + 1)
      end

      # ------------------------------------------------------------------------------
      # Taking back and putting back

      def self.undo(encounter)
        return Err.new(:frozen, 'pf2e.history_frozen', 'id' => encounter.id) unless encounter.is_active

        entry = entries(encounter).find { |one| one.seq == at(encounter) }

        return Err.new(:nothing_to_undo, 'pf2e.history_nothing_to_undo') unless entry

        moved = moved(entry.after)
        return Err.new(:moved, 'pf2e.history_moved', 'what' => moved) if moved

        restore(encounter, entry.before)
        restore_goods(entry.before, t('pf2e.history_undone', :name => 'GM', :said => entry.said))
        PF2Encounter[encounter.id].update(:history_at => entry.seq - 1)

        Ok.new(:state => entry)
      end

      def self.redo(encounter)
        return Err.new(:frozen, 'pf2e.history_frozen', 'id' => encounter.id) unless encounter.is_active

        entry = entries(encounter).find { |one| one.seq == at(encounter) + 1 }

        return Err.new(:nothing_to_redo, 'pf2e.history_nothing_to_redo') unless entry

        moved = moved(entry.before)
        return Err.new(:moved, 'pf2e.history_moved', 'what' => moved) if moved

        restore(encounter, entry.after)
        restore_goods(entry.after, t('pf2e.history_redone', :name => 'GM', :said => entry.said))
        PF2Encounter[encounter.id].update(:history_at => entry.seq)

        Ok.new(:state => entry)
      end
    end
  end
end
