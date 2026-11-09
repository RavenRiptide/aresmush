module AresMUSH
  module Pf2e

    # Magical staves (GM Core's staff rules). A staff is a weapon, and its catalogue entry says the spells it
    # holds, by rank, in a `staff:` block:
    #
    #   Staff of Fire (Greater):
    #     staff:
    #       of: Staff of Fire                 # the staff it is a tier of; a tier holds every lower tier's spells
    #       spells:
    #         2: [ Breathe Fire, Floating Flame ]
    #         3: [ Floating Flame, Fireball ]
    #
    # - **Preparing.** `prepare/staff <staff>`, during daily preparations, by someone with at least one of its
    #   spells on a list they cast from. It gains charges equal to their highest spell slot's rank, and only
    #   they cast from it that day. They prepare one staff a day. A prepared caster may also expend one
    #   prepared spell they haven't cast, `prepare/staff <staff>/<rank> = <spell>`, for that rank in more
    #   charges. A Staff Nexus wizard may expend two from 8th level and three from 16th, one command each.
    # - **Casting.** The staff must be equipped, and the spell on one of their lists at a rank they can cast.
    #   It costs charges equal to its rank, and a cantrip none, heightened as theirs are. A spontaneous caster
    #   may instead spend 1 charge and a spell slot of the spell's rank or higher, saying `rank <n>`.
    # - **Staff Nexus.** The wizard's makeshift staff is a bound item. Its two spells, a cantrip and a
    #   1st-rank spell from their spellbook, are picked in chargen when they choose the thesis
    #   (`addspell makeshift/<rank> = <spell>`), kept on their magic as `makeshift_spells`, and changed after
    #   that only by staff (`admin/set <char>/makeshift`). A spell the makeshift staff holds can't leave
    #   their spellbook. Any other staff they prepare holds those two as well. Prepared on its own, the
    #   makeshift staff gets no charges for being prepared, only those of the spells expended on it, so
    #   until one is its cantrip is all it casts.
    #
    # The preparation is daily state, kept with the character's daily choices under `staff`. It has no
    # feat's block, so a rest clears it. The charges are on the encounter's copy of the staff: set where
    # they stand when they prepare it, and at a fresh join, which is rested.
    module Staves

      PICK = 'staff'.freeze
      THESIS = 'Staff Nexus'.freeze
      BOOK_CLASS = 'Wizard'.freeze
      MAKESHIFT_SLOTS = %w{cantrip 1}.freeze
      # Chargen's slot for the makeshift staff's spells, in to_assign.
      ASSIGN = 'makeshift staff'.freeze

      # ------------------------------------------------------------------------------
      # What a staff holds

      def self.info(name)
        found = Global.read_config('pf2e_weapons', name.to_s)
        block = found.is_a?(Hash) ? found['staff'] : nil

        block.is_a?(Hash) ? block : nil
      end

      def self.staff?(item)
        item.is_a?(PF2Weapon) && !info(item.name).nil?
      end

      def self.makeshift?(item)
        staff?(item) && !!info(item.name)['makeshift']
      end

      # A rank key as a number, a cantrip being 0.
      def self.rank_of(key)
        key.to_s.casecmp?('cantrip') ? 0 : key.to_s.to_i
      end

      # Its catalogue spells, with every lower tier's: [ { 'name', 'rank' } ], cantrips at rank 0.
      def self.catalogue_spells(name)
        own = info(name)

        return [] unless own

        weapons = Global.read_config('pf2e_weapons') || {}
        level = (weapons[name.to_s] || {})['level'].to_i
        family = own['of'].to_s

        tiers = weapons.select do |_tier, entry|
          entry.is_a?(Hash) && entry['staff'].is_a?(Hash) && entry['staff']['of'].to_s == family && entry['level'].to_i <= level
        end

        tiers.values.flat_map { |entry| (entry['staff']['spells'] || {}).flat_map { |rank, names| Array(names).map { |spell| { 'name' => spell.to_s, 'rank' => rank_of(rank) } } } }
             .uniq.sort_by { |one| [ one['rank'], one['name'] ] }
      end

      # What it holds for them today: its own spells, and for a Staff Nexus wizard their makeshift staff's two.
      def self.spells(char, item)
        own = makeshift?(item) ? [] : catalogue_spells(item.name)
        added = nexus?(char) ? makeshift_spells(char) : []

        (own + added).uniq.sort_by { |one| [ one['rank'], one['name'] ] }
      end

      # ------------------------------------------------------------------------------
      # Staff Nexus

      def self.nexus?(char)
        char.respond_to?(:pf2_base_info) && ((char.pf2_base_info || {})['specialize_info']).to_s.casecmp?(THESIS)
      end

      # How many prepared spells they may expend on the staff they prepare: one for a prepared caster, two
      # for a Staff Nexus wizard from 8th level and three from 16th, none for anyone else.
      def self.expend_limit(char)
        return 0 if prepared_classes(char).empty?
        return 1 unless nexus?(char)

        level = char.pf2_level.to_i

        level >= 16 ? 3 : (level >= 8 ? 2 : 1)
      end

      # The makeshift staff's spells: { 'cantrip' => spell, '1' => spell }, leaving out a slot not yet picked.
      def self.makeshift_picks(char)
        magic = char.respond_to?(:magic) ? char.magic : nil
        held = magic.respond_to?(:makeshift_spells) ? (magic.makeshift_spells || {}) : {}

        held.select { |slot, spell| MAKESHIFT_SLOTS.include?(slot.to_s) && !spell.blank? && !spell.to_s.casecmp?('open') }
      end

      def self.makeshift_spells(char)
        makeshift_picks(char).map { |slot, spell| { 'name' => spell.to_s, 'rank' => rank_of(slot) } }
      end

      # The slot their makeshift staff holds a spell in, or nil.
      def self.makeshift_slot_of(picks, spell)
        found = (picks || {}).find { |_slot, held| held.to_s.casecmp?(spell.to_s) }

        found ? found.first : nil
      end

      # The spells their wizard spellbook holds at a slot: 'cantrip' or '1'.
      def self.spellbook_at(char, slot)
        magic = char.magic

        return [] unless magic

        Pf2emagic::Entries.known_at(magic, BOOK_CLASS, slot).map(&:to_s)
      end

      # 'cantrip' for 'cantrip' or '0', '1' for '1', or nil for a slot the makeshift staff hasn't.
      def self.makeshift_slot(word)
        key = word.to_s.downcase.strip
        key = 'cantrip' if key == '0'

        MAKESHIFT_SLOTS.include?(key) ? key : nil
      end

      # Whether a spell may be the makeshift staff's in that slot: the slot's rank, from their spellbook.
      # Pure, so chargen and staff ask the same question. Nil when it may.
      def self.makeshift_refusal(key, name, details, book)
        return Err.new(:wrong_rank, 'pf2e.staff_makeshift_rank', 'spell' => name, 'slot' => slot_word(key)) unless
          rank_of(details['base_level']) == rank_of(key)
        return Err.new(:not_in_book, 'pf2e.staff_makeshift_book', 'spell' => name, 'slot' => slot_word(key)) unless
          Array(book).any? { |one| one.to_s.casecmp?(name) }

        nil
      end

      # `addspell makeshift/<rank> = <spell>`, and `= <old>/<new>` to swap one, in chargen: a slot chargen
      # opened when they chose the thesis.
      def self.choose_makeshift!(char, slot, old_term, new_term)
        return Err.new(:not_nexus, 'pf2e.staff_not_nexus') unless nexus?(char)

        to_assign = char.pf2_to_assign || {}
        open = to_assign[ASSIGN]

        return Err.new(:no_pick, 'pf2e.staff_makeshift_no_pick') unless open.is_a?(Hash)

        key = makeshift_slot(slot)

        return Err.new(:bad_slot, 'pf2e.staff_makeshift_slot') unless key

        found = SpellItems.spell_named(new_term)

        return found if found.err?

        name, details = found.state
        current = open[key].to_s
        filled = !current.empty? && !current.casecmp?('open')

        if old_term.blank?
          return Err.new(:already, 'pf2e.staff_makeshift_already', 'slot' => slot_word(key), 'spell' => current,
                         'rank' => key) if filled
        else
          return Err.new(:not_held, 'pf2e.staff_makeshift_not_held', 'spell' => old_term) unless
            filled && SpellItems.spell_named(old_term).then { |old| old.ok? && old.state.first.casecmp?(current) }
        end

        refused = makeshift_refusal(key, name, details, spellbook_at(char, key))

        return refused if refused

        write_makeshift!(char, key, name)

        Ok.new(:state => { 'spell' => name, 'slot' => slot_word(key) })
      end

      # Sets one of the makeshift staff's spells, and fills chargen's slot for it if one is open.
      def self.write_makeshift!(char, key, name)
        magic = char.magic

        magic.update(:makeshift_spells => (magic.makeshift_spells || {}).merge(key => name))

        to_assign = char.pf2_to_assign || {}

        return unless to_assign[ASSIGN].is_a?(Hash)

        char.update(:pf2_to_assign => to_assign.merge(ASSIGN => to_assign[ASSIGN].merge(key => name)))
      end

      # Whether chargen still waits on a makeshift staff spell.
      def self.makeshift_open?(to_assign)
        open = (to_assign || {})[ASSIGN]

        open.is_a?(Hash) && open.values.any? { |spell| spell.blank? || spell.to_s.casecmp?('open') }
      end

      # Why a spell can't leave their spellbook, or nil: their makeshift staff holds it. Only a wizard's
      # spellbook, which is the one it comes from.
      def self.leaving_book_refusal(picks, charclass, spell)
        return nil unless charclass.to_s.casecmp?(BOOK_CLASS)

        slot = makeshift_slot_of(picks, spell)

        slot ? { 'spell' => picks[slot], 'slot' => slot_word(slot) } : nil
      end

      # The makeshift spell a rollback to that level would take out of their spellbook, or nil: the
      # spellbook is read from the sheet as it would be after the rollback.
      def self.lost_on_rollback(char, level)
        picks = makeshift_picks(char)

        return nil if picks.empty?

        spells = Ledger.derived(char, :at_level => level.to_i - 1)['spells'] || {}
        book = spells.find { |source, _by_rank| source.to_s.casecmp?(BOOK_CLASS) }&.last || {}
        kept = book.values.flatten.map(&:to_s)
        slot = picks.keys.find { |key| kept.none? { |spell| spell.casecmp?(picks[key].to_s) } }

        slot ? { 'spell' => picks[slot], 'slot' => slot_word(slot) } : nil
      end

      def self.slot_word(key)
        key.to_s == 'cantrip' ? 'cantrip' : "#{SpellItems.ordinal(key.to_i)}-rank spell"
      end

      # ------------------------------------------------------------------------------
      # Preparing a staff

      # Today's preparation: { 'pick' => name, 'item' => id, 'charges', 'expended' => [ { class, rank, spell } ] }.
      def self.prepared(char)
        found = DailyChoices.picks(char)[PICK]

        found.is_a?(Hash) && found['item'] ? found : nil
      end

      # The staff they carry by that name, or nickname: one named exactly, or the one staff whose name
      # holds the words.
      def self.carried(char, term)
        wanted = term.to_s.strip
        staves = Pf2egear::Inventory.all(char, 'weapons').select { |item| staff?(item) }
        exact = staves.select { |item| item.name.to_s.casecmp?(wanted) || item.nickname.to_s.casecmp?(wanted) }

        return exact.first unless exact.empty?

        partial = staves.select { |item| item.name.to_s.downcase.include?(wanted.downcase) }

        partial.size == 1 ? partial.first : nil
      end

      # Their prepared casting classes.
      def self.prepared_classes(char)
        magic = char.respond_to?(:magic) ? char.magic : nil

        return [] unless magic

        Pf2emagic::Entries.casting(magic).map { |entry| entry['name'].to_s }
                          .select { |name| Pf2emagic.get_caster_type(name) == 'prepared' }
      end

      # The rank of their highest spell slot, across what they cast from.
      def self.highest_slot(char)
        magic = char.magic

        return 0 unless magic

        Pf2emagic::Entries.casting(magic).map { |entry| Pf2emagic.max_spell_level_available(char, entry['name']).to_s.to_i }.max.to_i
      end

      # The charges a staff gets for being prepared, before any spell is expended on it. A makeshift staff
      # prepared on its own gets none: its charges come only from the spells expended on it. Merged into
      # another staff, it is that staff that is prepared, and it gets the usual charges.
      def self.starting_charges(char, item)
        makeshift?(item) ? 0 : highest_slot(char)
      end

      def self.listed?(char, item)
        spells(char, item).any? { |one| SpellItems.casting_for(char, one['name']) }
      end

      # Where they stand now: their state in each running encounter.
      def self.standing(char)
        return [] unless char.is_a?(Character)

        PF2Encounter.running_for(char).to_a.filter_map { |encounter| CombatantStates.of(encounter, char) }
      end

      def self.copies(state, item_id)
        state.weapons.to_a.select { |one| one.copied_from.to_s == item_id.to_s }
      end

      # `prepare/staff <staff>[/<rank> = <spell>]`. Once more on the staff already prepared, it expends
      # another spell, up to their limit.
      def self.prepare!(char, term, rank = nil, spell_term = nil)
        item = carried(char, term)

        return Err.new(:no_staff, 'pf2e.staff_not_carried', 'staff' => term) unless item

        inert = BoundItems.inert_for(char, item)

        return Err.new(:inert, 'pf2e.bound_item_cannot_use', 'item' => item.name, 'feat' => inert) if inert

        current = prepared(char)

        if current && current['item'].to_s != item.id.to_s
          return Err.new(:one_a_day, 'pf2e.staff_one_a_day', 'staff' => current['pick'])
        end

        return Err.new(:already, 'pf2e.staff_already', 'staff' => item.name) if current && spell_term.blank?
        return Err.new(:not_listed, 'pf2e.staff_not_on_list', 'staff' => item.name) unless listed?(char, item)

        made = current ? current.dup : { 'pick' => item.name, 'item' => item.id.to_s, 'charges' => starting_charges(char, item),
                                         'expended' => [], 'source' => 'Staff', 'locked' => true }
        expended = nil

        unless spell_term.blank?
          found = expendable(char, made, rank, spell_term)

          return found if found.err?

          expended = found.state
          made = made.merge('expended' => Array(made['expended']) + [ expended ], 'charges' => made['charges'].to_i + expended['rank'])
        end

        char.update(:pf2_daily_choices => DailyChoices.picks(char).merge(PICK => made))

        standing(char).each do |state|
          copies(state, item.id).each do |copy|
            copy.update(:staff_charges => current ? copy.staff_charges.to_i + expended['rank'] : made['charges'])
          end

          take_spell!(state, expended) if expended
        end

        Ok.new(:state => { 'staff' => item.name, 'charges' => made['charges'], 'expended' => expended, 'new' => current.nil? })
      end

      # The prepared spell they would expend: one they prepared at that rank today, not expended already, and
      # not cast in an encounter they are in.
      def self.expendable(char, made, rank, spell_term)
        classes = prepared_classes(char)
        limit = expend_limit(char)

        return Err.new(:not_prepared_caster, 'pf2e.staff_expend_prepared_only') if classes.empty?
        return Err.new(:limit, 'pf2e.staff_expend_limit', 'count' => limit) if Array(made['expended']).size >= limit
        return Err.new(:no_rank, 'pf2e.staff_expend_rank') unless rank.to_i.positive?

        found = SpellItems.spell_named(spell_term)

        return found if found.err?

        name = found.state.first
        key = rank.to_i.to_s
        prepared_spells = char.magic.spells_prepared || {}

        cls = classes.find do |one|
          held = Array((prepared_spells[one] || {})[key]).count { |spell| spell.to_s.casecmp?(name) }
          spent = Array(made['expended']).count { |row| row['class'] == one && row['rank'].to_i == rank.to_i && row['spell'].casecmp?(name) }

          held > spent
        end

        return Err.new(:not_prepared, 'pf2e.staff_expend_not_prepared', 'spell' => name, 'rank' => key) unless cls

        row = { 'class' => cls, 'rank' => rank.to_i, 'spell' => name }
        cast = standing(char).find { |state| !spell_left?(state, row) }

        return Err.new(:cast, 'pf2e.staff_expend_cast', 'spell' => name, 'rank' => key) if cast

        Ok.new(:state => row)
      end

      def self.today_list(state, row)
        Array(((state.spells_today || {})[row['class']] || {})[row['rank'].to_s])
      end

      def self.spell_left?(state, row)
        today_list(state, row).any? { |spell| spell.to_s.casecmp?(row['spell']) }
      end

      # An expended spell gone from what they have left in an encounter.
      def self.take_spell!(state, row)
        today = (state.spells_today || {}).dup
        by_class = (today[row['class']] || {}).dup
        list = Array(by_class[row['rank'].to_s]).dup
        at = list.index { |spell| spell.to_s.casecmp?(row['spell']) }

        return unless at

        list.delete_at(at)
        by_class[row['rank'].to_s] = list
        today[row['class']] = by_class
        state.update(:spells_today => today)
      end

      def self.give_spell!(state, row)
        today = (state.spells_today || {}).dup
        by_class = (today[row['class']] || {}).dup

        by_class[row['rank'].to_s] = (Array(by_class[row['rank'].to_s]) + [ row['spell'] ]).sort
        today[row['class']] = by_class
        state.update(:spells_today => today)
      end

      # `unprepare/staff`: the staff unprepared, and the spells expended on it back, while nothing has been
      # cast from it.
      def self.unprepare!(char)
        current = prepared(char)

        return Err.new(:nothing, 'pf2e.staff_nothing_prepared') unless current

        states = standing(char)
        used = states.any? { |state| copies(state, current['item']).any? { |copy| copy.staff_charges.to_i < current['charges'].to_i } }

        return Err.new(:cast_from, 'pf2e.staff_cast_from', 'staff' => current['pick']) if used

        states.each do |state|
          copies(state, current['item']).each { |copy| copy.update(:staff_charges => 0) }
          Array(current['expended']).each { |row| give_spell!(state, row) }
        end

        char.update(:pf2_daily_choices => DailyChoices.picks(char).reject { |key, _| key == PICK })

        Ok.new(:state => { 'staff' => current['pick'], 'spells' => Array(current['expended']).map { |row| row['spell'] } })
      end

      # A fresh join is rested: the day's preparation in force on their copy of the staff, and the spells it
      # expended gone from what they have left.
      def self.on_join!(state, char)
        current = prepared(char)

        return unless current

        copies(state, current['item']).each { |copy| copy.update(:staff_charges => current['charges'].to_i) }
        Array(current['expended']).each { |row| take_spell!(state, row) }
      end

      # A rest: the charges fade. The preparation itself, with the other daily choices, is cleared.
      def self.rested!(holder)
        return unless Actors.of(holder).carries_items?

        Pf2egear::Inventory.all(holder, 'weapons').select { |one| one.respond_to?(:staff_charges) && one.staff_charges.to_i.positive? }
                           .each { |one| one.update(:staff_charges => 0) }
      end

      # ------------------------------------------------------------------------------
      # Casting from a staff

      # What the words ask it to cast: the first word naming a spell it holds, or its only spell. Answers
      # { 'spell', 'rank', 'words' }, with the rest of the words for the spell itself.
      def self.chosen(char, item, words)
        held = spells(char, item)
        at = Array(words).index { |word| held.any? { |one| one['name'].casecmp?(word.to_s) } }

        if at
          spell = held.find { |one| one['name'].casecmp?(words[at].to_s) }

          return Ok.new(:state => spell.merge('words' => words.reject.with_index { |_one, index| index == at }))
        end

        return Ok.new(:state => held.first.merge('words' => Array(words))) if held.size == 1

        Err.new(:which, 'pf2e.staff_which', 'item' => item.name, 'spells' => held.map { |one| one['name'] }.uniq.join(', '))
      end

      # Whether this is the staff they prepared today, and in hand. An encounter's copy is theirs by
      # `copied_from`.
      def self.refusal(char, item)
        current = prepared(char)
        own = item.respond_to?(:copied_from) && item.copied_from ? item.copied_from.to_s : item.id.to_s

        return Err.new(:unprepared, 'pf2e.staff_unprepared', 'item' => item.name) unless current && current['item'].to_s == own
        return Err.new(:unequipped, 'pf2e.staff_unequipped', 'item' => item.name) unless item.equipped

        nil
      end

      RANK_WORD = /\Arank\s+(\d+)\z/i

      # Outside an encounter: the room is told. Nothing is counted, as for a wand.
      def self.use_outside!(char, item, words)
        refused = refusal(char, item)

        return refused if refused

        picked = chosen(char, item, words)

        return picked if picked.err?

        spell = picked.state

        return Err.new(:not_listed, 'pf2e.spell_item_not_listed', 'item' => item.name, 'spell' => spell['name']) unless
          SpellItems.casting_for(char, spell['name'])

        Ok.new(:state => spell)
      end

      # What a cast costs, and what it is cast with: { 'cost', 'slot', 'class', 'cast' }, or why not.
      def self.costing(holder, item, spell, slot)
        found = SpellItems.casting_for(holder, spell['name'])

        return Err.new(:not_listed, 'pf2e.spell_item_not_listed', 'item' => item.name, 'spell' => spell['name']) unless found

        cls, stats = found
        rank = spell['rank'].to_i

        if rank.zero?
          level = "cantrip/#{Pf2emagic.get_auto_heighten_level(holder)}"

          return Ok.new(:state => { 'cost' => 0, 'class' => cls, 'cast' => stats.merge('spell name' => spell['name'], 'spell level' => level) })
        end

        highest = Pf2emagic.max_spell_level_available(holder, cls).to_s.to_i

        return Err.new(:too_high, 'pf2e.staff_rank_too_high', 'spell' => spell['name'], 'rank' => rank) if rank > highest

        cast = stats.merge('spell name' => spell['name'], 'spell level' => rank.to_s)

        return Ok.new(:state => { 'cost' => rank, 'class' => cls, 'cast' => cast }) unless slot

        return Err.new(:not_spontaneous, 'pf2e.staff_slot_spontaneous_only') unless Pf2emagic.get_caster_type(cls) == 'spontaneous'
        return Err.new(:low_slot, 'pf2e.staff_slot_too_low', 'spell' => spell['name'], 'rank' => rank) if slot < rank
        return Err.new(:no_slot, 'pf2e.staff_slot_empty', 'rank' => slot) unless slots_left(holder, cls, slot).positive?

        Ok.new(:state => { 'cost' => 1, 'slot' => slot, 'class' => cls, 'cast' => cast })
      end

      def self.slot_key(today, slot)
        [ slot.to_s, slot.to_i ].find { |key| today.key?(key) }
      end

      def self.slots_left(holder, cls, slot)
        today = ((holder.magic.spells_today || {})[cls] || {})
        key = slot_key(today, slot)

        key ? today[key].to_i : 0
      end

      def self.spend_slot!(holder, cls, slot)
        all = (holder.magic.spells_today || {}).dup
        today = (all[cls] || {}).dup
        key = slot_key(today, slot)

        return unless key

        today[key] = today[key].to_i - 1
        all[cls] = today
        holder.magic.update(:spells_today => all)
      end

      # In an encounter: cast through the engine `encounter/cast` uses, then the charges are spent.
      def self.cast!(scene, item, targets, words)
        holder = scene.actor.holder
        person = Actors.of(holder).person || holder
        refused = refusal(person, item)

        return refused if refused

        picked = chosen(person, item, words)

        return picked if picked.err?

        spell = picked.state
        slot_word = spell['words'].find { |word| word.to_s.strip.match?(RANK_WORD) }
        slot = slot_word ? slot_word.to_s.strip.match(RANK_WORD)[1].to_i : nil
        said = spell['words'] - [ slot_word ].compact
        costed = costing(holder, item, spell, slot)

        return costed if costed.err?

        cost = costed.state['cost']

        return Err.new(:charges, 'pf2e.staff_no_charges', 'item' => item.name, 'cost' => cost, 'left' => item.staff_charges.to_i) if
          item.staff_charges.to_i < cost

        name = spell['name']
        before = [ Acting.way_needed(name, said), Acting.casting_refused(scene, name, said),
                   Acting.item_needed(scene, name, targets, said) ].find { |one| one&.err? }

        return before if before

        cast = costed.state['cast']
        risked = Acting.casting_risked(scene, name)

        done = if risked && !risked['kept']
                 Acting.casting_lost(scene, name, risked, cast)
               else
                 Acting.cast(scene, name, targets, said, :cast => cast, :noted => risked ? risked['lines'] : [])
               end

        return done if done.err?

        item.update(:staff_charges => item.staff_charges.to_i - cost) if cost.positive?
        spend_slot!(holder, costed.state['class'], slot) if slot
        done.state['lines'] << Telling.event('pf2e.staff_charges_left', :item => item.name, :left => item.staff_charges.to_i)

        done
      end

      # ------------------------------------------------------------------------------
      # What an item view says of one

      def self.describe(char, item)
        return [] unless staff?(item)

        by_rank = spells(char, item).group_by { |one| one['rank'] }.sort.map do |rank, list|
          "#{rank.zero? ? 'Cantrip' : SpellItems.ordinal(rank)}: #{list.map { |one| one['name'] }.join(', ')}"
        end

        lines = [ t('pf2e.staff_holds', :spells => by_rank.empty? ? '---' : by_rank.join('; ')) ]
        note = info(item.name)['note']

        lines << note.to_s if note

        current = prepared(char)
        own = item.respond_to?(:copied_from) && item.copied_from ? item.copied_from.to_s : item.id.to_s

        if current && current['item'].to_s == own
          left = item.respond_to?(:state) && item.state ? item.staff_charges.to_i : current['charges'].to_i
          lines << t('pf2e.staff_prepared_today', :charges => left)
        end

        lines
      end
    end
  end
end
