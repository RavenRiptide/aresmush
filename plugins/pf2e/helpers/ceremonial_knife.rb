module AresMUSH
  module Pf2e

    # A witch's ceremonial knife: at daily preparations, a knife-group weapon they carry is made to work as a
    # wand holding one spell their familiar knows, which is their own spell list. A daily choice picks it:
    #
    #   daily_choice:
    #     switch: ceremonialknife    # prepare/ceremonialknife <weapon>: <spell> [<rank>]
    #     pick: knife
    #     class: Witch               # whose spells the familiar knows
    #     items: { weapon_groups: [ knife ] }
    #     max_rank: { level: 6, rank: 1, every: 2 }   # rank 1 at 6th level, 1 more every 2 levels after
    #     lasts: until_changed
    #
    # The pick keeps `knife: { 'weapon', 'name', 'spell', 'rank' }`, the weapon by its id. Nothing is written
    # on the weapon, so there is one knife at a time, only the witch can cast from it (another who carries it
    # holds no pick naming it), and selling it ends the binding, since the pick then names nothing.
    #
    # It casts as a wand (`SpellItems.cast!` with `held:`): once a day, then overcharged, which can break or
    # destroy it. Its day is kept on the weapon (`used_today`, `overcharged`, `broken`).
    module CeremonialKnife

      KIND = 'knife'.freeze

      def self.err(key, block, args = {})
        Err.new(key.to_sym, "pf2e.#{key}", args.merge('source' => block['source'], 'switch' => block['switch']))
      end

      # Whose picks a holder's knife is read from: the character, or the character behind their state in an
      # encounter.
      def self.owner(holder)
        return holder if holder.is_a?(Character)

        holder.respond_to?(:character) ? holder.character : nil
      end

      # Today's knife: { 'weapon', 'name', 'spell', 'rank' }, or nil.
      def self.today(holder)
        char = owner(holder)
        return nil unless char

        found = DailyChoices.in_force(char).values.find { |_pick, block| block['pick'].to_s == KIND }

        found && found.first['knife'].is_a?(Hash) ? found.first['knife'] : nil
      end

      # Whether this is the knife the holder's pick names: their own weapon, or the encounter's copy of it.
      def self.knife?(holder, item)
        held = today(holder)
        return false unless held && item.is_a?(PF2Weapon)

        [ item.id, item.copied_from ].compact.map(&:to_s).include?(held['weapon'].to_s)
      end

      # ------------------------------------------------------------------------------
      # The pick

      def self.max_rank(char, block)
        spec = block['max_rank'].is_a?(Hash) ? block['max_rank'] : {}
        gained = (char.pf2_level.to_i - spec['level'].to_i) / [ spec['every'].to_i, 1 ].max

        spec['rank'].to_i + [ gained, 0 ].max
      end

      def self.group_of(item)
        Domains.slug(item.group.presence || (Pf2eCombat.weapon_info(item.name) || {})['group'])
      end

      # The knife-group weapons they carry.
      def self.weapons(char, block)
        groups = Array((block['items'] || {})['weapon_groups']).map { |one| Domains.slug(one) }

        Pf2egear.carried_items(char).select { |category, item| category == 'weapons' && groups.include?(group_of(item)) }
                .map(&:last)
      end

      # The spells their familiar knows that a wand can hold, at no higher a rank than the knife takes.
      def self.spells(char, block)
        entry = DailySpells.learned_entry(char, block['class'])
        return [] unless entry

        highest = max_rank(char, block)

        (entry['known'] || {}).values.flatten.map(&:to_s).uniq.select do |spell|
          found = Pf2emagic.get_spell_details(spell)

          found.is_a?(Array) && SpellItems.unfit('wand', found[0], found[1]).nil? &&
            SpellItems.base_rank(found[1]).between?(1, highest)
        end.sort
      end

      def self.offer(char, block)
        knives = weapons(char, block).map { |item| item.nickname.presence || item.name }.uniq
        spells = spells(char, block)

        [ t('pf2e.knife_offer_weapons', :weapons => knives.empty? ? '---' : knives.join(', ')),
          t('pf2e.knife_offer_spells', :rank => max_rank(char, block), :spells => spells.empty? ? '---' : spells.join(', ')) ]
      end

      # `<weapon>: <spell> [<rank>]`, the rank the spell's own when it is not given.
      def self.answers(char, block, typed)
        named, rest = typed.to_s.split(':', 2).map(&:strip)

        return err('knife_form', block) if named.blank? || rest.blank?

        wanted = Domains.slug(named)
        weapon = weapons(char, block).find { |item| [ item.name, item.nickname ].compact.any? { |one| Domains.slug(one) == wanted } }

        return err('knife_no_weapon', block, 'weapon' => named) unless weapon

        spell_name, rank = rest.match(/\A(.+?)(?:\s+(\d+))?\z/).captures
        spell = spells(char, block).find { |one| one.casecmp?(spell_name.to_s) }

        return err('knife_no_spell', block, 'spell' => spell_name) unless spell

        base = SpellItems.base_rank(Pf2emagic.get_spell_details(spell)[1])
        highest = max_rank(char, block)
        rank = (rank || base).to_i

        return err('knife_bad_rank', block, 'spell' => spell, 'low' => base, 'high' => highest) unless rank.between?(base, highest)

        shown = weapon.nickname.presence || weapon.name

        Ok.new(:state => { 'pick' => "#{shown}: #{spell} #{rank}",
                           'knife' => { 'weapon' => weapon.id.to_s, 'name' => shown, 'spell' => spell, 'rank' => rank } })
      end

      # Kept through a rest while they still carry that weapon and could still put that spell in it. A rest in
      # an encounter asks of what they carry there, the copy of their own weapon.
      def self.kept?(char, block, pick)
        held = pick['knife']
        return false unless held.is_a?(Hash)

        weapons(char, block).any? { |item| [ item.id, item.copied_from ].compact.map(&:to_s).include?(held['weapon'].to_s) } &&
          spells(char, block).include?(held['spell'].to_s) && held['rank'].to_i <= max_rank(char, block)
      end

      # ------------------------------------------------------------------------------
      # Casting from it

      def self.cast!(scene, item, targets, words, overcharge: false)
        SpellItems.cast!(scene, item, targets, words, :overcharge => overcharge, :held => today(scene.actor.holder))
      end

      # Outside an encounter nothing is rolled and its day isn't counted, as for a wand.
      def self.use_outside!(char, item)
        held = today(char)
        refused = SpellItems.refusal(char, item, held)

        return refused if refused

        Ok.new(:state => { 'spell' => held['spell'], 'rank' => held['rank'].to_i, 'item' => item.nickname.presence || item.name })
      end

      # What an item view says of today's knife.
      def self.describe(holder, item)
        return [] unless knife?(holder, item)

        held = today(holder)
        lines = [ t('pf2e.knife_holds', :spell => held['spell'], :rank => held['rank'].to_i) ]
        lines << t('pf2e.wand_is_broken') if item.broken
        lines << t('pf2e.wand_is_used') if item.used_today && !item.broken

        lines
      end
    end
  end
end
