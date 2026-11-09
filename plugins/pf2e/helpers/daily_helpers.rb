module AresMUSH
  module Pf2e

    # A night's rest and the day's preparations, for someone as they stand in an encounter: the night's
    # Hit Points, an end to what lasts less than a day, the day's once-a-day uses, a full focus pool, the
    # day's spells from what they have prepared, snares, what they invest, and an alchemist's vials and
    # prepared items. The GM rests them with `+e/rest`, as often as the story says a night has passed.
    def self.rest(holder)
      # What the last day's preparations made lapses before this day's are made.
      Equipment.lapse!(holder, 'rest')
      Pf2eHP.modify_damage(holder, get_daily_healing(holder), true)
      ActiveEffects.rested(holder)
      TurnState.reset(holder, 'rest')

      magic = holder.magic

      if magic
        daily_refresh_focus_pool(magic)
        Pf2emagic.generate_spells_today(holder)
        magic.update(revelation_locked: false)
      end

      daily_refresh_reagents(holder)
      do_daily_investiture(holder)
      # A wand's daily casting, and the day's overcharge, come back.
      SpellItems.rested!(holder)
      WaveFan.rested!(holder)
      # A staff's charges fade, and it is prepared again with the day's other choices.
      Staves.rested!(holder)

      # An alchemist's versatile vials and prepared items for the day, and a rogue's simple injury poisons.
      made = Alchemy.at_rest!(holder)
      WeaponPoison.at_rest!(holder)

      # The day's choices open again. One that should have held but no longer can is said, so the player
      # knows to pick again.
      person = Actors.of(holder).person

      DailyChoices.rested!(holder).each do |dropped|
        next unless person

        Login.emit_ooc_if_logged_in(person, t('pf2e.daily_dropped', :source => dropped['source'],
                                              :pick => dropped['pick'], :switch => dropped['switch']))
      end

      # The day's batches from the picks still in force: a witch's cauldron.
      DailyChoices.brew!(holder)

      # A Shield Paragon's destroyed shield comes back mended.
      repaired = ShieldBlock.paragon_repair!(holder)

      if repaired && person
        Login.emit_ooc_if_logged_in(person, t('pf2e.shield_paragon_repaired', :name => holder.name,
                                              :shield => repaired.nickname || repaired.name))
      end

      # What the alchemist's preparations made, which is what a caller asks of a rest.
      made
    end

    # A full night's rest recovers Constitution modifier times level, doubled by Fast Recovery and its
    # like. Foundry keeps that as a multiplier their rules add to, so what an effect wrote is one less
    # than the multiplier it means (`system.attributes.hp.recoveryMultiplier`).
    # A night's rest: the Constitution modifier, at least 1, for each level - twice over with Fast
    # Recovery.
    def self.get_daily_healing(char)
      con_mod = [ Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, "Constitution")), 1 ].max

      con_mod * [ char.pf2_level.to_i, 1 ].max * recovery_multiplier(char)
    end

    def self.recovery_multiplier(char)
      1 + Pf2e::Paths.held(char, 'recovery_multiplier').to_i
    end

    SNARES_BY_RANK = { 'expert' => 4, 'master' => 6, 'legendary' => 8 }.freeze

    # A snare-maker's snares for the day, `[ total, remaining ]`, kept in `pf2_reagents` under `snares`.
    # An alchemist's day is `Pf2e::Alchemy`'s: the `alchemist` key a legacy alchemist left there is not
    # read.
    def self.daily_refresh_reagents(char)
      reagents = (char.pf2_reagents || {}).dup

      return nil if reagents.empty?

      if reagents['snares']
        # Snares prepared each day, by Crafting: 4 for an expert, 6 for a master, 8 for a legend.
        snares_today = SNARES_BY_RANK[Pf2eSkills.get_skill_prof(char, 'Crafting').to_s.downcase].to_i

        reagents['snares'] = [ snares_today, snares_today ]
      end

      char.update(pf2_reagents: reagents)
    end

    # Daily preparations fill the pool.
    def self.daily_refresh_focus_pool(magic)
      magic.update(focus_pool: { 'current' => Pf2emagic.focus_pool_max(magic) })
    end

    def self.do_daily_investiture(char)

      char_wp_list = Pf2egear::Inventory.held(char, 'weapons')
      char_a_list = Pf2egear::Inventory.held(char, 'armor')
      char_mi_list = Pf2egear.items_in_inventory(char.magic_items.to_a)

      investable_list = char_wp_list + char_a_list + char_mi_list

      investable_list.each { |item| item.update(invested: false) }

      to_invest = investable_list.select {|i| i.invest_on_refresh }

      to_invest.each { |item| item.update(invested: true) }

      return nil
    end

  end
end
