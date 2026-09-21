module AresMUSH
  module Pf2e

    # Who is in an encounter, and how a command names them.
    #
    # The initiative order is a list of rows, one per combatant, highest initiative first:
    #
    #   { 'id' => 3, 'init' => 18.2, 'name' => 'Goblin Warrior #3', 'npc' => '41' }
    #   { 'id' => 1, 'init' => 15.0, 'name' => 'Aria', 'char' => '12' }
    #
    # A row names its holder - a character, or a `Pf2eNpc` the GM added - by database id, so nothing has
    # to guess from a name which of them it is. Its id is given when it joins and never reused, so `#3`
    # names the same goblin all fight long whatever the order does - which is what a player types to
    # target it, since three goblins share a name. A row with neither holder is a name the GM put in the
    # order and nothing more.
    module Combatants

      Combatant = Struct.new(:holder, :label, :number, :init) do
        def creature?
          Actors.of(holder).creature?
        end

        def ref
          number ? "##{number}" : label
        end

        def name
          label
        end
      end

      ID = /\A#?(\d+)\z/

      # The order's rows. An order written as `[ initiative, name ]` pairs is read as rows once, and kept.
      def self.rows(encounter)
        held = Array(encounter.participants)

        return held if held.all? { |one| one.is_a?(Hash) }

        last = encounter.last_number.to_i
        read = held.map do |one|
          next one if one.is_a?(Hash)

          last += 1
          char = Character.named(one[1].to_s)
          { 'id' => last, 'init' => one[0].to_f, 'name' => one[1].to_s, 'char' => char&.id }.compact
        end

        encounter.update(:participants => read, :last_number => last)
        read
      end

      def self.holder_of(row)
        return Pf2eNpc[row['npc']] if row['npc']
        return Character[row['char']] if row['char']

        nil
      end

      def self.combatant(row)
        Combatant.new(holder_of(row), row['name'], row['id'].to_i, row['init'].to_f)
      end

      def self.all(encounter)
        rows(encounter).map { |row| combatant(row) }
      end

      # The one at this place in the order.
      def self.at(encounter, index)
        row = rows(encounter)[index]

        row ? combatant(row) : nil
      end

      # Whoever holds a place in the order under this name.
      def self.holder_named(encounter, label)
        return nil if label.to_s.empty?
        return Character.named(label) unless encounter

        row = rows(encounter).find { |one| one['name'] == label }

        row ? holder_of(row) : Character.named(label)
      end

      # ------------------------------------------------------------------------------
      # The order

      # Someone takes a place in the order: a character, a creature, or with no holder a name the GM put
      # there.
      def self.join(encounter, name, init, holder: nil)
        id = encounter.last_number.to_i + 1
        row = { 'id' => id, 'name' => name }

        row[Actors.of(holder).creature? ? 'npc' : 'char'] = holder.id if holder
        row['init'] = placed(row, init)

        encounter.update(:last_number => id)
        write(encounter, rows(encounter) + [ row ])

        row
      end

      def self.leave(encounter, id)
        write(encounter, rows(encounter).reject { |row| row['id'].to_i == id.to_i })
      end

      def self.reroll(encounter, id, init)
        write(encounter, rows(encounter).map { |row| row['id'].to_i == id.to_i ? row.merge('init' => placed(row, init)) : row })
      end

      # Anyone but a character goes before a character on the same roll, which is the rule for a tie
      # between the GM's side and the players'.
      def self.placed(row, init)
        init.to_f + (row['char'] ? 0 : 0.2)
      end

      # The order, sorted, with the turn still on whoever held it.
      def self.write(encounter, rows)
        sorted = rows.sort_by { |row| -row['init'].to_f }

        encounter.update(:next_init => pointer(encounter, rows(encounter), sorted), :participants => sorted)
      end

      # `next_init` is one past whoever's turn it is. It follows them wherever a sort puts them; if they
      # have left, it points at whoever was to come after them.
      def self.pointer(encounter, was, sorted)
        return 0 if sorted.empty? || was.empty? || encounter.round.to_i.zero?

        at = encounter.next_init.to_i
        place = lambda { |row| sorted.index { |one| one['id'] == row['id'] } }
        held = place.call(was[(at - 1) % was.size])

        return (held + 1) % sorted.size if held

        following = was.size.times.map { |step| was[(at + step) % was.size] }.find { |row| place.call(row) }

        following ? place.call(following) : 0
      end

      # The combatant a command names: `#3`, or a name only one of them has - whole, or the start of it.
      def self.find(encounter, term)
        wanted = term.to_s.strip
        listed = all(encounter)

        if (id = wanted.match(ID))
          found = listed.find { |one| one.number == id[1].to_i }

          return found ? Ok.new(:state => found) : Err.new(:no_combatant, 'pf2e.no_combatant', 'target' => wanted)
        end

        exact = listed.select { |one| one.label.casecmp?(wanted) }
        close = exact.any? ? exact : listed.select { |one| one.label.downcase.start_with?(wanted.downcase) }

        return Ok.new(:state => close.first) if close.size == 1
        return Err.new(:no_combatant, 'pf2e.no_combatant', 'target' => wanted) if close.empty?

        Err.new(:ambiguous_combatant, 'pf2e.ambiguous_combatant', 'target' => wanted,
                'options' => close.map { |one| "#{one.ref} #{one.label}" }.join(', '))
      end

      # Someone a command names, in an encounter or out of one: a combatant where there is an encounter,
      # and otherwise a character by name.
      def self.resolve(enactor, term, encounter = nil)
        if encounter
          found = find(encounter, term)

          return found if found.ok? || term.to_s.match?(ID)
        end

        char = ClassTargetFinder.find(term, Character, enactor)

        return Err.new(:no_combatant, 'pf2e.no_combatant', 'target' => term) unless char.found?

        row = encounter && rows(encounter).find { |one| one['char'] == char.target.id }

        Ok.new(:state => row ? combatant(row) : Combatant.new(char.target, char.target.name, nil))
      end

      # Several at once, saying which names found nobody: `[ found, missing ]`.
      def self.resolve_all(enactor, terms, encounter = nil)
        found, missing = Array(terms).map { |term| [ term, resolve(enactor, term, encounter) ] }
                                     .partition { |_term, result| result.ok? }

        [ found.map { |_term, result| result.state }, missing.map(&:first) ]
      end

      # The active encounter in the room the enactor is in, if there is one.
      def self.encounter_here(enactor)
        scene = enactor.room&.scene

        scene ? PF2Encounter.scene_active_encounter(scene) : nil
      end

      # ------------------------------------------------------------------------------
      # Adding a creature

      # A creature joins the encounter: its own hit points and conditions, an id, and a place in the
      # order - its Perception check unless the GM says where. `name` is what the GM calls it; otherwise
      # it is the creature and its id.
      def self.add_npc(encounter, creature: nil, described: nil, name: nil, initiative: nil)
        npc = Pf2eNpc.create(:encounter => encounter, :creature => creature, :described => described || {})
        number = encounter.last_number.to_i + 1
        base = name.to_s.strip.empty? ? "#{creature || described['name']} ##{number}" : name.to_s.strip
        label = rows(encounter).any? { |row| row['name'] == base } ? "#{base} ##{number}" : base

        npc.update(:name => label, :number => number)

        rolled = initiative || (Pf2e.roll_dice.first + Npcs.stat(npc, 'perception', nil, [ 'initiative' ])['total'].to_i)

        join(encounter, label, rolled, :holder => npc)

        Ok.new(:state => { 'npc' => npc, 'initiative' => rolled.to_i })
      end

      # A creature described by the numbers off a stat block: `ac 16 fort 5 ref 7 will 3 perception 2 hp 20`.
      DESCRIBED = { 'ac' => %w{ac}, 'hp' => %w{hp}, 'perception' => %w{perception per},
                    'fortitude' => %w{fort fortitude}, 'reflex' => %w{ref reflex}, 'will' => %w{will},
                    'level' => %w{level lvl} }.freeze

      def self.described(name, text)
        pairs = text.to_s.downcase.scan(/([a-z]+)\s*([+-]?\d+)/)
        read = pairs.each_with_object({}) do |(word, value), out|
          field = DESCRIBED.find { |_field, words| words.include?(word) }&.first
          out[field] = value.to_i if field
        end

        return nil unless read['ac']

        { 'name' => name, 'level' => read['level'].to_i, 'ac' => read['ac'], 'hp' => read['hp'].to_i,
          'perception' => read['perception'].to_i, 'traits' => [],
          'saves' => { 'fortitude' => read['fortitude'].to_i, 'reflex' => read['reflex'].to_i,
                       'will' => read['will'].to_i } }
      end

      # ------------------------------------------------------------------------------
      # Who may do what

      # The GM runs the encounter: its organiser, or staff.
      def self.gm?(char, encounter)
        encounter && PF2Encounter.is_organizer?(char, encounter)
      end

      # A GM, or a player the GM trusted for this encounter, may set a target's cover and concealment.
      def self.trusted?(char, encounter)
        gm?(char, encounter) || Array(encounter&.trusted).include?(char.name)
      end
    end
  end
end
