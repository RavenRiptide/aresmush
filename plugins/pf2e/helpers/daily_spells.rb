module AresMUSH
  module Pf2e

    # The daily choices that change a character's spells, three kinds of pick in `DailyChoices::KINDS`:
    #
    #   daily_choice:                # Versatile Signature: one signature spell swapped for another
    #     switch: versatile          # spell of its rank from the repertoire, as `<signature>: <new>`
    #     pick: signature
    #     class: Bard
    #     lasts: until_changed
    #
    #   daily_choice:                # Paradoxical Mystery: a focus spell lent for the day
    #     switch: paradox
    #     pick: focus_spell
    #     focus_type: revelation     # the focus spells it joins
    #     pool: [ domains, other_mysteries ]
    #     lasts: day
    #
    #   daily_choice:                # Scroll Adept: temporary scrolls made at each rest, as
    #     switch: scrolladept        # `<spell> <rank>, <spell> <rank>`
    #     pick: scrolls
    #     class: Wizard
    #     below_top: 2               # each rank at least this far below the highest the class casts
    #     count: { trained: 2, master: 3, legendary: 4 }   # how many, by spell DC rank
    #     lasts: until_changed
    #
    # A swapped signature spell and a lent focus spell are laid over the character's spellcasting entries
    # as they are read (`adjust`, from `Pf2emagic::Entries.for_magic`), so casting, the magic display and
    # the focus pool all see them, and nothing is written to the sheet. The scrolls are items, made by
    # `DailyChoices.brew!` beside Cauldron's batch and gone at the next rest.
    module DailySpells

      # ------------------------------------------------------------------------------
      # Laid over the entries

      # The entries with today's swapped signature spell and lent focus spell in them.
      def self.adjust(magic, entries)
        char = magic.respond_to?(:character) ? magic.character : nil
        return entries unless char && !DailyChoices.picks(char).empty?

        forces = DailyChoices.in_force(char).values
        swaps = forces.filter_map { |pick, block| block['pick'].to_s == 'signature' ? pick['swap'] : nil }
        lent = forces.filter_map { |pick, block| block['pick'].to_s == 'focus_spell' ? pick['lent'] : nil }

        return entries if swaps.empty? && lent.empty?

        entries.map do |entry|
          entry = swapped(entry, swaps)
          lent_to(entry, lent)
        end
      end

      def self.swapped(entry, swaps)
        swap = swaps.find { |one| entry['category'].to_s != Pf2emagic::Entries::FOCUS && one['class'].to_s.casecmp?(entry['name'].to_s) }
        return entry unless swap

        signature = (entry['signature'] || {}).dup
        rank = swap['rank'].to_s
        list = Array(signature[rank]).map { |spell| spell.to_s.casecmp?(swap['from'].to_s) ? swap['to'] : spell }

        entry.merge('signature' => signature.merge(rank => list))
      end

      def self.lent_to(entry, lent)
        return entry unless entry['category'].to_s == Pf2emagic::Entries::FOCUS

        mine = lent.select { |one| one['type'].to_s.casecmp?(entry['name'].to_s) }.map { |one| one['spell'] }
        return entry if mine.empty?

        known = entry['known'] || {}

        entry.merge('known' => known.merge('spell' => (Array(known['spell']) + mine).uniq))
      end

      # ------------------------------------------------------------------------------
      # Versatile Signature

      # Every swap on offer, as `<signature>: <new>`: each signature spell they learned, for each other
      # spell of its rank in the repertoire.
      def self.signature_offer(char, block)
        entry = learned_entry(char, block['class'])
        return [] unless entry

        known = entry['known'] || {}

        (entry['signature'] || {}).flat_map do |rank, spells|
          Array(spells).flat_map do |from|
            Array(known[rank.to_s]).reject { |to| to.to_s.casecmp?(from.to_s) || Array(spells).include?(to) || to.to_s.casecmp?(Pf2emagic::Entries::OPEN) }
                                   .map { |to| "#{from}: #{to}" }
          end
        end.sort
      end

      def self.learned_entry(char, charclass)
        return nil unless char.magic

        Pf2emagic::Entries.for_magic(char.magic, :familiar => false).find do |entry|
          entry['name'].to_s.casecmp?(charclass.to_s) && entry['category'].to_s != Pf2emagic::Entries::FOCUS
        end
      end

      def self.signature_answers(char, block, typed)
        from, to = typed.to_s.split(':', 2).map(&:strip)
        offered = signature_offer(char, block)
        found = offered.find { |one| one.casecmp?("#{from}: #{to}") }

        unless found
          return Err.new(:not_offered, 'pf2e.daily_not_offered', 'source' => block['source'], 'pick' => typed,
                         'options' => offered.empty? ? '---' : offered.join(', '))
        end

        from, to = found.split(': ', 2)
        rank = ((learned_entry(char, block['class']) || {})['signature'] || {}).find { |_rank, spells| Array(spells).include?(from) }&.first

        Ok.new(:state => { 'pick' => found, 'swap' => { 'class' => block['class'].to_s, 'rank' => rank.to_s, 'from' => from, 'to' => to } })
      end

      def self.signature_kept?(char, block, pick)
        signature_offer(char, block).any? { |one| one.casecmp?(pick['pick'].to_s) }
      end

      # ------------------------------------------------------------------------------
      # Paradoxical Mystery

      # Where a focus spell pick finds its spells. Each takes the character.
      POOLS = {
        # The initial and advanced spells of every domain from Player Core, of each domain their mystery
        # grants, and of any other domain they already have a spell of.
        'domains' => lambda { |char|
          base = char.pf2_base_info || {}
          mystery = Global.read_config('pf2e_specialty', base['charclass'].to_s, base['specialize'].to_s) || {}
          granted = Array(mystery['domains']).map { |domain| domain.to_s.downcase }
          held = Pf2e.held_focus_spells(char).map(&:downcase)

          (Global.read_config('pf2e_magic', 'domains') || {}).flat_map do |name, domain|
            next [] unless domain.is_a?(Hash)

            spells = [ domain['initial'], domain['advanced'] ]
            open = domain['source'].to_s.casecmp?('Player Core') || granted.include?(name.to_s.downcase) ||
                   spells.any? { |spell| held.include?(spell.to_s.downcase) }

            open ? spells : []
          end
        },
        # The initial and advanced revelation spells of every mystery but their own.
        'other_mysteries' => lambda { |char|
          own = (char.pf2_base_info || {})['specialize'].to_s

          (Global.read_config('pf2e_specialty', 'Oracle') || {}).reject { |name, _info| name.to_s.casecmp?(own) }.flat_map do |_name, info|
            next [] unless info.is_a?(Hash)

            initial = (((info['chargen'] || {})['magic_stats'] || {})['focus_spell'] || {})['revelation']
            advanced = (info['advanced_focus_spell'] || {})['revelation']

            Array(initial) + Array(advanced)
          end
        }
      }.freeze

      def self.focus_offer(char, block)
        type = block['focus_type'].to_s
        held = char.magic ? Pf2emagic::Entries.focus_entries(char.magic, type).flat_map { |e| Array((e['known'] || {})['spell']) } : []

        pooled = Array(block['pool']).flat_map do |pool|
          reader = POOLS[pool.to_s]

          unless reader
            Global.logger.error "A focus spell pick draws on '#{pool}', which is not one of #{POOLS.keys.join(', ')}."
            next []
          end

          Array(reader.call(char))
        end

        pooled.compact.map(&:to_s).uniq.reject { |spell| held.any? { |one| one.to_s.casecmp?(spell) } }
              .select { |spell| Pf2emagic.get_spell_details(spell).is_a?(Array) }.sort
      end

      def self.focus_detail(_char, block, spell, _said)
        Ok.new(:state => { 'lent' => { 'type' => block['focus_type'].to_s, 'spell' => spell } })
      end

      # ------------------------------------------------------------------------------
      # Scroll Adept

      # The spells they may scribe: arcane spells from the class's spellbook that a scroll can hold.
      def self.scroll_offer(char, block)
        entry = learned_entry(char, block['class'])
        return [] unless entry

        (entry['known'] || {}).values.flatten.map(&:to_s).uniq.select do |spell|
          found = Pf2emagic.get_spell_details(spell)

          found.is_a?(Array) && Array(found[1]['tradition']).include?('arcane') && SpellItems.unfit('scroll', found[0], found[1]).nil?
        end.sort
      end

      # How many scrolls they make: the block's count for their best spell DC rank.
      def self.scroll_count(char, block)
        counts = block['count'].is_a?(Hash) ? block['count'] : {}
        rank = DailyChoices::RANKS.index(DailyChoices.spell_dc_rank(char)).to_i
        reached = counts.select { |named, _many| DailyChoices::RANKS.index(named.to_s).to_i <= rank }
                        .max_by { |named, _many| DailyChoices::RANKS.index(named.to_s).to_i }

        reached ? reached.last.to_i : 0
      end

      # `Fireball 3, Haste 4`: each a spell they may scribe, at a rank no lower than its own, no higher than
      # `below_top` under the highest the class casts, and no two at one rank.
      def self.scroll_answers(char, block, typed)
        wanted = typed.to_s.split(',').map(&:strip).reject(&:empty?)
        many = scroll_count(char, block)
        highest = Pf2emagic::SlotFeats.top_rank(char, block['class']) - block['below_top'].to_i
        offered = scroll_offer(char, block)

        return scroll_err('scroll_adept_how_many', block, 'count' => many) if wanted.empty? || wanted.size > many

        scrolls = wanted.map do |one|
          name, rank = one.match(/\A(.+?)\s+(\d+)\z/)&.captures

          return scroll_err('scroll_adept_say_rank', block, 'scroll' => one) unless name

          spell = offered.find { |spell| spell.casecmp?(name) }

          return scroll_err('scroll_adept_not_offered', block, 'spell' => name) unless spell

          base = SpellItems.base_rank(Pf2emagic.get_spell_details(spell)[1])

          return scroll_err('scroll_adept_bad_rank', block, 'spell' => spell, 'low' => base, 'high' => highest) unless rank.to_i.between?(base, highest)

          [ spell, rank.to_i ]
        end

        return scroll_err('scroll_adept_same_rank', block) if scrolls.map(&:last).uniq.size < scrolls.size

        Ok.new(:state => { 'pick' => scrolls.map { |spell, rank| "#{spell} #{rank}" }.join(', '), 'scrolls' => scrolls })
      end

      def self.scroll_err(key, block, args = {})
        Err.new(key.to_sym, "pf2e.#{key}", args.merge('source' => block['source'], 'switch' => block['switch']))
      end

      def self.scrolls_kept?(char, block, pick)
        scroll_answers(char, block, pick['pick']).ok?
      end

      # The day's scrolls for one pick, made again: what the pick made before is taken away first. Answers
      # [ "Scroll of Fireball (Rank 3)" ].
      def self.scribe!(holder, switch, block, pick)
        category = SpellItems.table['scroll']['category']
        made_by = DailyChoices.brewed_by(switch)

        Pf2egear::Inventory.all(holder, category).select { |item| item.granted_by == made_by }.each(&:delete)

        return [] unless pick

        Array(pick['scrolls']).filter_map do |spell, rank|
          found = Pf2emagic.get_spell_details(spell.to_s)
          next nil unless found.is_a?(Array)

          made = SpellItems.item('scroll', found[0], found[1], rank)
          next nil if made.err?

          name, info = made.state

          # A temporary scroll is worth nothing if sold.
          Equipment.grant!(holder, category, name, 1, info.merge('price' => 0), :granted_by => made_by, :expires => 'rest')

          name
        end
      end
    end
  end
end
