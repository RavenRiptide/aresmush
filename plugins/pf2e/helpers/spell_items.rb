module AresMUSH
  module Pf2e

    # Scrolls and wands: one generic item each, carrying the spell it holds and the rank it holds it at
    # (`spell`, `spell_rank`), rather than a catalogue entry for every spell at every rank. Its level, price,
    # Bulk and traits come from `pf2e_spell_items.yml` (GM Core's tables).
    #
    # - A scroll is a consumable: cast once, then gone.
    # - A wand is a magic item, cast once a day. After the day's casting it can be overcharged: cast again,
    #   then a DC 10 flat check, which breaks it on a success and destroys it on a failure. Overcharging one
    #   already overcharged that day destroys it and casts nothing. A broken wand can't be used until staff
    #   or the GM repair it.
    #
    # Casting from either needs the spell on one of the caster's spell lists: a spellcasting class whose
    # tradition the spell has. It is cast with that class's spell attack and DC, at the item's rank, through
    # the same engine as `encounter/cast` (`Acting.cast`).
    module SpellItems

      FLAT_DC = 10

      def self.table
        Global.read_config('pf2e_spell_items') || {}
      end

      def self.kinds
        table.keys.map(&:to_s)
      end

      # The kind a player names a category with: `scroll`, `scrolls`, `wand`, `wands`.
      def self.kind(word)
        wanted = word.to_s.downcase.strip

        kinds.find { |one| [ one, "#{one}s" ].include?(wanted) }
      end

      def self.spell_item?(item)
        item.respond_to?(:spell) && !item.spell.to_s.empty?
      end

      def self.wand?(item)
        spell_item?(item) && item.is_a?(PF2MagicItem)
      end

      # ------------------------------------------------------------------------------
      # What can be held, and what it costs

      # The spell a player named, by the catalogue's spelling: [ name, details ].
      def self.spell_named(term)
        found = Pf2emagic.get_spell_details(term)

        return Err.new(:no_spell, 'pf2e.spell_item_no_spell', 'spell' => term) unless found.is_a?(Array) && found.last.is_a?(Hash)

        Ok.new(:state => found)
      end

      def self.traits_of(details)
        Array(details['traits']).map { |one| one.to_s.downcase }
      end

      def self.base_rank(details)
        details['base_level'].to_s.to_i
      end

      # Why a spell can't go in a scroll or wand, or nil: a cantrip, a focus spell or a ritual, which the rules
      # leave out, and anything with no tradition, which only a focus pool or a ritual casts.
      def self.unfit(kind, name, details)
        traits = traits_of(details)

        return Err.new(:cantrip, 'pf2e.spell_item_cantrip', 'spell' => name, 'kind' => kind) if
          traits.include?('cantrip') || details['base_level'].to_s.casecmp?('cantrip')
        return Err.new(:focus, 'pf2e.spell_item_focus', 'spell' => name, 'kind' => kind) if
          (traits & %w{focus ritual}).any? || Array(details['tradition']).empty?

        nil
      end

      # The item a spell makes at a rank: its name and what it is, for `Pf2egear.create_item`.
      def self.item(kind, name, details, rank = nil)
        row = table[kind] || {}
        rank = (rank || base_rank(details)).to_i
        at = (row['ranks'] || {})[rank] || (row['ranks'] || {})[rank.to_s]

        return Err.new(:low_rank, 'pf2e.spell_item_low_rank', 'spell' => name, 'rank' => base_rank(details)) if rank < base_rank(details)
        return Err.new(:high_rank, 'pf2e.spell_item_high_rank', 'kind' => kind, 'rank' => row['max_rank']) unless at

        info = { 'level' => at['level'].to_i, 'price' => at['price'].to_i, 'bulk' => row['bulk'].to_f,
                 'traits' => Array(row['traits']), 'spell' => name, 'spell_rank' => rank }

        Ok.new(:state => [ format(row['name'].to_s, :spell => name, :rank => rank), info ])
      end

      # ------------------------------------------------------------------------------
      # Specialty wands: Widening, Continuation

      def self.specialties
        (table['wand'] || {})['specialties'] || {}
      end

      # `Fireball (widening)`: the spell, and the specialty named in brackets after it, if it is one.
      def self.split_specialty(term)
        found = term.to_s.strip.match(/\A(.+?)\s*\(([^)]+)\)\z/)
        key = found ? specialties.keys.find { |one| one.casecmp?(found[2].strip) } : nil

        key ? [ found[1].strip, key ] : [ term.to_s.strip, nil ]
      end

      def self.ordinal(number)
        suffix = { 1 => 'st', 2 => 'nd', 3 => 'rd' }[number % 100 > 10 && number % 100 < 14 ? 0 : number % 10] || 'th'

        "#{number}#{suffix}"
      end

      # Whether a catalogue name is one of the stocked specialty wands, which hold no spell of their own.
      def self.specialty_catalogue?(name)
        specialties.values.any? do |row|
          (1..10).any? { |rank| format(row['catalogue'].to_s, :ordinal => ordinal(rank)).casecmp?(name.to_s) }
        end
      end

      def self.minutes(text)
        found = text.to_s.downcase.strip.match(/\A(\d+) (minute|hour)s?\z/)

        return nil unless found

        found[1].to_i * (found[2] == 'hour' ? 60 : 1)
      end

      AREA = /(\d+)-foot (burst|cone|line)/

      # Why a spell can't go in this specialty, or nil.
      def self.specialty_unfit(key, name, details)
        row = specialties[key]
        refuse = lambda { |why| Err.new(:specialty, 'pf2e.spell_item_specialty_unfit', 'spell' => name, 'specialty' => key, 'why' => t(why)) }

        return refuse.call('pf2e.spell_item_why_actions') unless Array(row['actions']).map(&:to_s).include?(details['actions'].to_s)

        if row['area']
          area = details['area'].to_s.match(AREA)

          return refuse.call('pf2e.spell_item_why_area') unless area && Array(row['area']).include?(area[2])
          return refuse.call('pf2e.spell_item_why_area') if area[2] == 'burst' && area[1].to_i < row['min_burst'].to_i
        end

        duration = details['duration'].to_s.strip

        if row['duration'] == 'none'
          return refuse.call('pf2e.spell_item_why_no_duration') unless duration.empty?
        elsif row['duration'].is_a?(Hash)
          long = minutes(duration)

          return refuse.call('pf2e.spell_item_why_duration') unless long && long >= row['duration']['min_minutes'].to_i &&
                                                                  long <= row['duration']['max_minutes'].to_i
        end

        nil
      end

      def self.specialty_item(key, name, details, rank = nil)
        row = specialties[key]
        rank = (rank || base_rank(details)).to_i

        return Err.new(:low_rank, 'pf2e.spell_item_low_rank', 'spell' => name, 'rank' => base_rank(details)) if rank < base_rank(details)

        stocked = Global.read_config('pf2e_magicitem', format(row['catalogue'].to_s, :ordinal => ordinal(rank)))

        return Err.new(:high_rank, 'pf2e.spell_item_specialty_rank', 'specialty' => key, 'rank' => rank) unless stocked.is_a?(Hash)

        info = { 'level' => stocked['level'].to_i, 'price' => stocked['price'].to_i, 'bulk' => stocked['bulk'].to_f,
                 'traits' => Array(stocked['traits']), 'spell' => name, 'spell_rank' => rank, 'specialty' => key }

        Ok.new(:state => [ format(row['name'].to_s, :spell => name, :rank => rank), info ])
      end

      # A wider area: 5 feet more on a burst of 10 feet or more and on a cone or line of 15 feet or less, 10
      # feet more on a longer cone or line.
      def self.widened(area)
        area.to_s.sub(AREA) do
          feet = Regexp.last_match(1).to_i
          shape = Regexp.last_match(2)
          more = shape != 'burst' && feet > 15 ? 10 : 5

          "#{feet + more}-foot #{shape}"
        end
      end

      # Half again as long.
      def self.lengthened(duration)
        long = minutes(duration)

        long ? "#{(long * 3) / 2} minutes" : duration.to_s
      end

      # After the spell is cast: the extra action, and what the specialty does to the spell. Continuation's
      # longer duration is real where the spell left an effect, which gets half its length again; Widening's
      # area is told, since nothing in an encounter knows where anyone stands.
      def self.specialty_cast!(scene, item, targets, out)
        row = specialties[item.specialty.to_s]

        return unless row

        holder = scene.actor.holder
        details = Global.read_config('pf2e_spells', item.spell.to_s) || {}

        TurnState.spend(holder, item.name, :cost => row['extra'].to_i, :type => 'action') if row['extra'].to_i.positive?

        if item.specialty.to_s == 'widening'
          out['lines'] << Telling.event('pf2e.wand_widened', :item => item.name, :area => widened(details['area']))
          return
        end

        out['lines'] << Telling.event('pf2e.wand_continued', :item => item.name, :duration => lengthened(details['duration']))

        found = Acting.effect_of_spell(item.spell)

        return unless found

        (targets.empty? ? [ scene.actor ] : targets).each do |whom|
          effect = ActiveEffects.named_on(whom.holder, found).max_by { |one| one.id.to_i }
          long = effect ? ActiveEffects.rounds_long(effect) : nil

          effect.update(:started_round => effect.started_round.to_i + long / 2) if long && effect.started_round
        end
      end

      # What a vendor sells: a common spell's scroll or wand no higher in level than the buyer. An uncommon or
      # rare spell's is reached by a request, even where the spell itself was unlocked for them. A wand's spell
      # may name a specialty after it in brackets: `Fireball (widening)`.
      def self.for_sale(char, kind, term, rank = nil)
        spell_term, specialty = kind == 'wand' ? split_specialty(term) : [ term, nil ]
        found = spell_named(spell_term)

        return found if found.err?

        name, details = found.state
        unfit = unfit(kind, name, details) || (specialty && specialty_unfit(specialty, name, details))

        return unfit if unfit

        made = specialty ? specialty_item(specialty, name, details, rank) : item(kind, name, details, rank)

        return made if made.err?

        rarity = ItemAccess.rarity('traits' => traits_of(details))

        return Err.new(:rare, 'pf2e.spell_item_rare', 'spell' => name, 'rarity' => rarity, 'kind' => kind) unless rarity == 'common'
        return Err.new(:too_high, 'pf2e.spell_item_too_high', 'item' => made.state.first, 'level' => made.state.last['level']) if
          made.state.last['level'] > char.pf2_level.to_i

        made
      end

      # ------------------------------------------------------------------------------
      # Casting from them

      # The spellcasting class that has the spell on its list: [ class name, its caster stats ], or nil.
      def self.casting_for(holder, spell)
        details = Global.read_config('pf2e_spells', spell.to_s)
        traditions = Array((details || {})['tradition']).map { |one| one.to_s.downcase }
        magic = holder.magic

        return nil unless magic

        entry = Pf2emagic::Entries.casting(magic).find { |one| traditions.include?(one['tradition'].to_s.downcase) }

        return nil unless entry

        stats = Pf2emagic.get_caster_stats(holder, entry['name'])

        stats.is_a?(Hash) ? [ entry['name'], stats ] : nil
      end

      # Whether they can cast from it at all: a broken wand can't be, and the spell has to be on their list.
      def self.refusal(holder, item)
        return Err.new(:broken, 'pf2e.wand_broken', 'item' => item.name) if wand?(item) && item.broken
        return Err.new(:not_listed, 'pf2e.spell_item_not_listed', 'item' => item.name, 'spell' => item.spell) unless
          casting_for(holder, item.spell)

        nil
      end

      # What the casting engine is handed: the caster's own stats, with the item's spell and rank.
      def self.cast_of(holder, item)
        _class, stats = casting_for(holder, item.spell)

        stats.merge('spell name' => item.spell, 'spell level' => item.spell_rank.to_s)
      end

      # Outside an encounter nothing is rolled: the room is told, and a scroll is used up. A wand's day isn't
      # counted, since the GM's rests that count days happen in encounters.
      def self.use_outside!(char, item)
        refused = refusal(char, item)

        return refused if refused

        if wand?(item)
          nil
        elsif item.quantity.to_i > 1
          item.update(:quantity => item.quantity.to_i - 1)
        else
          item.delete
        end

        Ok.new(:state => { 'spell' => item.spell, 'rank' => item.spell_rank.to_i, 'item' => item.name })
      end

      # In an encounter: cast through the engine `encounter/cast` uses, then the item is spent. `overcharge`
      # casts from a wand already used today, and rolls for what it does to the wand.
      def self.cast!(scene, item, targets, words, overcharge: false)
        holder = scene.actor.holder
        refused = refusal(holder, item)

        return refused if refused

        if wand?(item)
          return Err.new(:used, 'pf2e.wand_used_today', 'item' => item.name) if item.used_today && !overcharge
          return Err.new(:not_used, 'pf2e.wand_overcharge_unused', 'item' => item.name) if overcharge && !item.used_today
          return overcharged_again!(scene, item) if overcharge && item.overcharged
        end

        spell = item.spell
        # Asked as `encounter/cast` asks them, before anything is spent. `way_needed` answers Ok when nothing is
        # needed, and the others nil.
        before = [ Acting.way_needed(spell, words), Acting.casting_refused(scene, spell, words),
                   Acting.item_needed(scene, spell, targets, words) ].find { |one| one&.err? }

        return before if before

        cast = cast_of(holder, item)
        risked = Acting.casting_risked(scene, spell)

        done = if risked && !risked['kept']
                 Acting.casting_lost(scene, spell, risked, cast)
               else
                 Acting.cast(scene, spell, targets, words, :cast => cast, :noted => risked ? risked['lines'] : [])
               end

        return done if done.err?

        specialty_cast!(scene, item, targets, done.state) if wand?(item) && !(risked && !risked['kept'])
        spent!(holder, item, overcharge, done.state)

        done
      end

      def self.spent!(holder, item, overcharge, out)
        unless wand?(item)
          Consumables.spend!(holder, item.id)
          return
        end

        return item.update(:used_today => true) unless overcharge

        roll = Pf2e.roll_dice(1, 20).first.to_i

        if roll >= FLAT_DC
          item.update(:overcharged => true, :broken => true)
          out['lines'] << Telling.event('pf2e.wand_overcharge_broken', :item => item.name, :roll => roll)
        else
          destroy!(holder, item)
          out['lines'] << Telling.event('pf2e.wand_overcharge_destroyed', :item => item.name, :roll => roll)
        end
      end

      # A wand overcharged again the same day: destroyed, and no spell cast.
      def self.overcharged_again!(scene, item)
        destroy!(scene.actor.holder, item)

        out = Acting.report
        out['lines'] << Telling.event('pf2e.wand_overcharged_again', :actor => scene.actor.label, :item => item.name)

        Ok.new(:state => out)
      end

      # Gone from the encounter's copy now, and from their own when the encounter settles.
      DESTROYED = 'destroyed_items'.freeze

      def self.destroy!(holder, item)
        if item.respond_to?(:copied_from) && item.copied_from
          TurnState.write(holder, DESTROYED => (Array(TurnState.of(holder)[DESTROYED]) + [ item.copied_from.to_s ]).uniq)
        end

        item.delete
      end

      # ------------------------------------------------------------------------------
      # A rest, an encounter's end, and repair

      # A rest gives a wand its day back. A broken one stays broken.
      def self.rested!(holder)
        return unless Actors.of(holder).carries_items?

        Pf2egear::Inventory.all(holder, 'magicitem').select { |one| wand?(one) && (one.used_today || one.overcharged) }
                           .each { |one| one.update(:used_today => false, :overcharged => false) }
      end

      # What the encounter did to their own wands: broken or mended, and destroyed. Their day isn't carried
      # back, since whoever joins another fresh joins rested.
      def self.settle!(state)
        state.magic_items.to_a.select { |one| wand?(one) && one.copied_from }.each do |copy|
          own = PF2MagicItem[copy.copied_from]
          own.update(:broken => !!copy.broken) if own && !!own.broken != !!copy.broken
        end

        Array(TurnState.of(state)[DESTROYED]).each { |id| PF2MagicItem[id]&.delete }
        TurnState.write(state, DESTROYED => [])
      end

      # What an item view says of one: the spell it holds, and a wand's day.
      def self.describe(item)
        return [] unless spell_item?(item)

        lines = [ t('pf2e.spell_item_holds', :spell => item.spell, :rank => item.spell_rank.to_i) ]
        lines << t("pf2e.wand_specialty_#{item.specialty}") if wand?(item) && specialties.key?(item.specialty.to_s)

        if wand?(item)
          lines << t('pf2e.wand_is_broken') if item.broken
          lines << t('pf2e.wand_is_used') if item.used_today && !item.broken
        end

        lines
      end

      def self.repair!(item)
        return Err.new(:not_wand, 'pf2e.wand_repair_not_wand', 'item' => item.name) unless wand?(item)
        return Err.new(:not_broken, 'pf2e.wand_repair_not_broken', 'item' => item.name) unless item.broken

        item.update(:broken => false)

        Ok.new(:state => item.name)
      end
    end
  end
end
