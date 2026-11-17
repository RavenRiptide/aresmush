module AresMUSH
  module Pf2emagic

    # Can this set of spells be placed in the slots available at one rank?
    #
    # PF2e slots are pools, and a pool can be restricted. A Wizard's curriculum slot takes only a
    # spell from the school's list; a Cleric's divine font slot takes only heal or harm. The
    # question is therefore which spell goes in which slot, and comparing counts does not answer
    # that once a rank has two restricted pools. Greedy assignment does not either, because the
    # pool a spell is allowed to use may be the one another spell needs.
    #
    # Pure: pools and spell names in, a boolean out. It reads nothing outside its arguments.
    module SlotFit

      # A slot that takes anything.
      ANY = nil

      # Capacities are per-rank slot counts, so single digits. Expanding them into individual slots
      # keeps the matching simple; the cap bounds the work a corrupt stat block can ask for.
      MAX_SLOTS = 64

      # The pools a caster has at one rank: their open slots, plus one pool per restriction.
      #
      # `restrictions` is { name => { 'count' => n, 'eligible' => [ spells ] } } - what a
      # restriction's own rules produce, such as a curriculum's school list or a font's heal/harm.
      def self.from_slots(open_count, restrictions)
        pools = []
        pools << { 'name' => ANY, 'capacity' => open_count.to_i, 'eligible' => ANY } if open_count.to_i.positive?

        (restrictions || {}).each_pair do |name, restriction|
          next unless restriction.is_a?(Hash)
          count = restriction['count'].to_i
          next unless count.positive?

          pools << { 'name' => name, 'capacity' => count, 'eligible' => Array(restriction['eligible']) }
        end

        pools
      end

      def self.fits?(pools, spells)
        !assign(pools, spells).nil?
      end

      # Which pool each spell goes in: one list of spells per pool, in the pools' order, or nil when
      # they don't all fit. A spell a restricted pool accepts goes there before an open slot, so
      # the open slots left over are the ones a display can call free.
      def self.assign(pools, spells)
        pools = Array(pools).select { |pool| pool.is_a?(Hash) }
        spells = Array(spells)
        placed = pools.map { [] }
        return placed if spells.empty?

        slots = expand(pools)
        return nil if spells.size > slots.size

        # Kuhn's algorithm: give every spell a slot, backing a spell out of one when that frees a
        # placement for another. Spells are tracked by position, since a list can repeat a name.
        keys = spells.map { |spell| spell.to_s.downcase }
        taken = {}

        return nil unless keys.each_index.all? { |index| place(index, keys, slots, taken, {}) }

        taken.each_pair { |slot, index| placed[slots[slot]['pool']] << spells[index] }
        placed
      end

      # One entry per individual slot: the spells it accepts (nil = any) and the pool it belongs
      # to. Restricted slots come first, which is what makes `assign` prefer them.
      def self.expand(pools)
        ordered = pools.each_with_index.sort_by { |pool, index| [ pool['eligible'].nil? ? 1 : 0, index ] }

        ordered.each_with_object([]) do |(pool, index), slots|
          eligible = pool['eligible']
          eligible = eligible.map { |s| s.to_s.downcase } if eligible

          [ pool['capacity'].to_i, MAX_SLOTS - slots.size ].min.times { slots << { 'eligible' => eligible, 'pool' => index } }
        end
      end

      def self.place(index, keys, slots, taken, seen)
        slots.each_with_index do |slot, slot_index|
          next if seen[slot_index]
          next unless slot['eligible'].nil? || slot['eligible'].include?(keys[index])

          seen[slot_index] = true
          occupant = taken[slot_index]

          if occupant.nil? || place(occupant, keys, slots, taken, seen)
            taken[slot_index] = index
            return true
          end
        end

        false
      end
    end
  end
end
