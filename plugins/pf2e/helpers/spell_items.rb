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
      # `held` is the spell and rank of something that casts as a wand without being one (`CeremonialKnife`):
      # { 'spell', 'rank' }.
      def self.refusal(holder, item, held = nil)
        spell = held ? held['spell'] : item.spell

        return Err.new(:broken, 'pf2e.knife_broken', 'item' => item.name) if held && item.broken
        return Err.new(:broken, 'pf2e.wand_broken', 'item' => item.name) if wand?(item) && item.broken
        return Err.new(:not_listed, 'pf2e.spell_item_not_listed', 'item' => item.name, 'spell' => spell) unless
          casting_for(holder, spell)

        nil
      end

      # What the casting engine is handed: the caster's own stats, with the item's spell and rank.
      def self.cast_of(holder, item, held = nil)
        spell = held ? held['spell'] : item.spell
        _class, stats = casting_for(holder, spell)

        stats.merge('spell name' => spell, 'spell level' => (held ? held['rank'] : item.spell_rank).to_s)
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
      # casts from a wand already used today, and rolls for what it does to the wand. `held` casts something
      # that works as a wand holding that spell (`refusal`).
      def self.cast!(scene, item, targets, words, overcharge: false, held: nil)
        holder = scene.actor.holder
        wand = held ? true : wand?(item)
        refused = refusal(holder, item, held)

        return refused if refused

        # A wand of shardstorm's shards, directed this turn for free; trying to activate it any other time
        # while the storm lasts ends the storm.
        ended = nil

        if storm?(item)
          return shards!(scene, item, targets, words) if shard_ready?(scene, item) && !overcharge

          item.update(:lingering => {})
          ended = Telling.event('pf2e.wand_storm_ended', :item => item.name)
        end

        if wand
          return Err.new(:used, 'pf2e.wand_used_today', 'item' => item.name) if item.used_today && !overcharge
          return Err.new(:not_used, 'pf2e.wand_overcharge_unused', 'item' => item.name) if overcharge && !item.used_today
          return overcharged_again!(scene, item) if overcharge && item.overcharged
        end

        spell = held ? held['spell'] : item.spell
        # Asked as `encounter/cast` asks them, before anything is spent. `way_needed` answers Ok when nothing is
        # needed, and the others nil.
        before = [ Acting.way_needed(spell, words), Acting.casting_refused(scene, spell, words),
                   Acting.item_needed(scene, spell, targets, words) ].find { |one| one&.err? }

        return before if before

        cast = cast_of(holder, item, held)
        risked = Acting.casting_risked(scene, spell)
        effect = wand_effect(item)
        alive = targets.reject { |one| slain?(one.holder) }

        done = if risked && !risked['kept']
                 Acting.casting_lost(scene, spell, risked, cast)
               else
                 Acting.cast(scene, spell, targets, words, :cast => cast, :noted => risked ? risked['lines'] : [],
                                                          :adds => effect && effect['outcomes'])
               end

        return done if done.err?

        done.state['lines'].unshift(ended) if ended

        unless risked && !risked['kept']
          specialty_cast!(scene, item, targets, done.state) if wand?(item)
          wand_effect_cast!(scene, item, effect, alive, done.state) if effect
        end
        spent!(holder, item, overcharge, done.state, wand: wand)

        done
      end

      # ------------------------------------------------------------------------------
      # What a wand adds to its spell

      # A stocked wand's `wand_effect`: what is told as it's cast, `outcomes` laid over the spell's by degree
      # (`Acting.cast`), `slain` for what a kill releases, and `next_turn_heal` for healing at the caster's next
      # turn. Nil for a wand that adds nothing.
      def self.wand_effect(item)
        return nil unless wand?(item)

        found = (Pf2egear.catalogue_entry('magicitem', item) || {})['wand_effect']

        found.is_a?(Hash) ? found : nil
      end

      # After the spell: the room is told what the wand adds, a target it slew releases what it releases, and
      # healing at the caster's next turn is noted on the wand. `alive` is who was alive before the casting.
      def self.wand_effect_cast!(scene, item, effect, alive, out)
        out['lines'] << Telling.event('pf2e.wand_effect', :item => item.name, :effect => effect['told']) if effect['told']

        if effect['slain']
          alive.select { |one| slain?(one.holder) && living?(one.holder) }.each do |one|
            out['lines'] << Telling.event('pf2e.wand_slain', :item => item.name, :target => one.label,
                                          :damage => effect['slain']['damage'], :type => effect['slain']['type'],
                                          :area => effect['slain']['area'])
          end
        end

        return unless scene.encounter

        round = scene.encounter.round.to_i

        if effect['storm']
          # The minute counts from this round, so its shards come at the caster's turns in the rounds after.
          item.update(:lingering => { 'storm' => effect['storm']['spell'], 'round' => round,
                                      'until' => round + effect['storm']['rounds'].to_i - 1 })
        elsif effect['next_turn_heal']
          item.update(:lingering => { 'heal' => effect['next_turn_heal'], 'round' => round })
        end
      end

      # Whether a wand of shardstorm's storm is going.
      def self.storm?(item)
        wand?(item) && item.lingering.is_a?(Hash) && !item.lingering['storm'].to_s.empty?
      end

      # Whether this turn's shards are still to be directed: their turn has started since the storm began, and
      # they haven't directed them yet.
      def self.shard_ready?(scene, item)
        round = scene.encounter&.round.to_i

        round.positive? && item.lingering['ready'].to_i == round && item.lingering['shot'].to_i != round
      end

      # The turn's shards, as the 1-action version of the storm's spell at the wand's rank, spending no actions
      # and none of the wand's day.
      def self.shards!(scene, item, targets, words)
        refused = refusal(scene.actor.holder, item)

        return refused if refused

        done = Acting.cast(scene, item.lingering['storm'], targets, [ 'actions 1' ] + Array(words),
                           :cast => cast_of(scene.actor.holder, item), :free => true)

        return done if done.err?

        item.update(:lingering => item.lingering.merge('shot' => scene.encounter.round.to_i))
        done.state['lines'].unshift(Telling.event('pf2e.wand_shards', :actor => scene.actor.label, :item => item.name))

        done
      end

      # Slain: a creature at 0 Hit Points, or a character dead.
      def self.slain?(holder)
        Actors.of(holder).creature? ? holder.hp_left.to_i <= 0 : Pf2e.dead?(holder)
      end

      # Living: neither undead nor a construct.
      def self.living?(holder)
        (Array(holder.pf2_traits).map { |one| one.to_s.downcase } & %w{undead construct}).empty?
      end

      # A turn starting: a wand of shardstorm's storm gives this turn's shards, or ends; and a wand of overflowing
      # life used since this turn's last start heals its caster, once however many there are.
      def self.turn_started(holder, round)
        return [] unless Actors.of(holder).carries_items?

        storms(holder, round.to_i) + overflowing(holder, round.to_i)
      end

      def self.storms(holder, round)
        held = Pf2egear::Inventory.held(holder, 'magicitem')

        held.select { |one| storm?(one) && round > one.lingering['round'].to_i }.map do |one|
          if round > one.lingering['until'].to_i
            one.update(:lingering => {})
            next Turns.event('pf2e.wand_storm_over', 'name' => holder.name, 'item' => one.name)
          end

          one.update(:lingering => one.lingering.merge('ready' => round))
          Turns.event('pf2e.wand_storm_shards', 'name' => holder.name, 'item' => one.name,
                      'number' => held.index { |other| other.id == one.id })
        end
      end

      def self.overflowing(holder, round)
        waiting = Pf2egear::Inventory.held(holder, 'magicitem').select do |one|
          one.lingering.is_a?(Hash) && one.lingering['heal'] && round > one.lingering['round'].to_i
        end

        return [] if waiting.empty?

        first = waiting.first
        thrown = Pf2e.thrown_formula(first.lingering['heal'])

        waiting.each { |one| one.update(:lingering => {}) }
        Harm.heal(holder, thrown['total'])

        [ Turns.event('pf2e.wand_turn_heal', 'name' => holder.name, 'item' => first.name, 'count' => thrown['total'],
                      'dice' => thrown['shown'] || first.lingering['heal']) ]
      end

      def self.spent!(holder, item, overcharge, out, wand: wand?(item))
        unless wand
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

      # Gone from the encounter's copy now, and from their own when the encounter settles. A weapon that casts
      # as a wand (`CeremonialKnife`) is kept apart, since weapons and magic items number their ids apart.
      DESTROYED = 'destroyed_items'.freeze
      DESTROYED_WEAPONS = 'destroyed_weapons'.freeze

      def self.destroy!(holder, item)
        if item.respond_to?(:copied_from) && item.copied_from
          key = item.is_a?(PF2Weapon) ? DESTROYED_WEAPONS : DESTROYED
          TurnState.write(holder, key => (Array(TurnState.of(holder)[key]) + [ item.copied_from.to_s ]).uniq)
        end

        item.delete
      end

      # ------------------------------------------------------------------------------
      # A rest, an encounter's end, and repair

      # A rest gives a wand its day back, and a weapon that casts as one (`CeremonialKnife`). A broken one
      # stays broken.
      def self.rested!(holder)
        return unless Actors.of(holder).carries_items?

        Pf2egear::Inventory.all(holder, 'magicitem').select { |one| wand?(one) && (one.used_today || one.overcharged || one.lingering.present?) }
                           .each { |one| one.update(:used_today => false, :overcharged => false, :lingering => {}) }
        Pf2egear::Inventory.all(holder, 'weapons').select { |one| one.used_today || one.overcharged }
                           .each { |one| one.update(:used_today => false, :overcharged => false) }
      end

      # What the encounter did to their own wands: broken or mended, and destroyed. Their day isn't carried
      # back, since whoever joins another fresh joins rested.
      def self.settle!(state)
        state.magic_items.to_a.select { |one| wand?(one) && one.copied_from }.each do |copy|
          own = PF2MagicItem[copy.copied_from]
          own.update(:broken => !!copy.broken) if own && !!own.broken != !!copy.broken
        end

        state.weapons.to_a.select(&:copied_from).each do |copy|
          own = PF2Weapon[copy.copied_from]
          own.update(:broken => !!copy.broken) if own && !!own.broken != !!copy.broken
        end

        Array(TurnState.of(state)[DESTROYED]).each { |id| PF2MagicItem[id]&.delete }
        Array(TurnState.of(state)[DESTROYED_WEAPONS]).each { |id| PF2Weapon[id]&.delete }
        TurnState.write(state, DESTROYED => [], DESTROYED_WEAPONS => [])
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
