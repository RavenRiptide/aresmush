module AresMUSH
  module Pf2e

    # An alchemist's day, as the remaster has it (Player Core 2, p. 56): two allowances, counted apart.
    #
    # - **Prepared items** (Advanced Alchemy): a list on their sheet, the way a prepared caster's spells are.
    #   `alchemy/prepare` writes it, and each rest makes it into the day's items, which last until their next
    #   preparations. It spends nothing.
    # - **Versatile vials:** each rest gives them their vials, of the highest type their level reaches. A vial
    #   is a bomb to throw, or the fuel Quick Alchemy spends to make one item on the spot.
    #
    # How many of each comes from config, in an `alchemy:` block on the Alchemist class entry or on a feat:
    #
    #   alchemy:
    #     prepared: { base: 4, plus: Intelligence }   # a number, or a base plus an attribute modifier
    #     vials: { base: 2, plus: Intelligence }
    #     gathers: true                               # may regain vials in exploration
    #
    # Where two sources give the same allowance, the higher counts: the remaster's rule for vials from more
    # than one source.
    #
    # Everything made lives in the encounter's copy of what they carry (`Pf2e::Equipment`), which a rest or
    # a fresh join fills. Nothing made ever reaches their sheet.
    module Alchemy

      # What made an item, so the alchemy screen can say which it was and a rest can find the day's vials.
      PREPARED = 'advanced alchemy'.freeze
      QUICK = 'quick alchemy'.freeze
      VIALS = 'versatile vials'.freeze

      # The highest type of vial a level reaches, highest first.
      VIAL_TYPES = [ [ 18, 'Major' ], [ 12, 'Greater' ], [ 4, 'Moderate' ], [ 1, 'Lesser' ] ].freeze

      # ------------------------------------------------------------------------------
      # Allowances

      def self.allowances(holder)
        SheetReads.memo(holder, :alchemy_allowances) do
          blocks = sources(holder).map { |info| info['alchemy'] }.select { |block| block.is_a?(Hash) }

          { 'vials' => blocks.map { |block| count(holder, block['vials']) }.max.to_i,
            'prepared' => blocks.map { |block| count(holder, block['prepared']) }.max.to_i,
            'gathers' => blocks.any? { |block| block['gathers'] } }
        end
      end

      # Their own class's entry and the feats in play for them.
      def self.sources(holder)
        charclass = (holder.pf2_base_info || {})['charclass'].to_s
        klass = charclass.empty? ? [] : [ Global.read_config('pf2e_class', charclass) ]
        feats = Pf2e.feats_in_play(holder).uniq.map { |name| Global.read_config('pf2e_feats', name) }

        (klass + feats).select { |info| info.is_a?(Hash) }
      end

      # A count is a number, or `{ base:, plus: <attribute> }`, which adds that attribute's modifier.
      def self.count(holder, spec)
        return spec.to_i unless spec.is_a?(Hash)

        modifier = spec['plus'] ? Pf2eAbilities.abilmod(Pf2eAbilities.get_score(holder, spec['plus'].to_s)) : 0

        [ spec['base'].to_i + modifier, 0 ].max
      end

      def self.alchemist?(holder)
        allowances(holder)['vials'].positive? || allowances(holder)['prepared'].positive?
      end

      def self.max_vials(holder)
        allowances(holder)['vials']
      end

      def self.prepared_limit(holder)
        allowances(holder)['prepared']
      end

      # ------------------------------------------------------------------------------
      # Versatile vials

      # The catalogue's name for the vial a level makes.
      def self.vial_name(level)
        found = VIAL_TYPES.find { |from, _type| level.to_i >= from } || VIAL_TYPES.last

        "Versatile Vial (#{found.last})"
      end

      # The day's vials they hold, which only an encounter does.
      def self.vials(holder)
        Array(holder.consumables.to_a).select { |one| one.granted_by == VIALS }
      end

      def self.left(holder)
        vials(holder).sum { |one| one.quantity.to_i }
      end

      # What the day holds. In an encounter that is what they have left; out of one they are rested, so it
      # is all of them.
      def self.day(holder)
        standing = !Gm.encounter_of(holder).nil?

        { 'vials' => max_vials(holder), 'left' => standing ? left(holder) : max_vials(holder),
          'prepared' => prepared_limit(holder) }
      end

      # What they hold that they made today, and how long each lasts.
      def self.made(holder)
        Array(holder.consumables.to_a).select { |one| [ PREPARED, QUICK, QUICK_VIAL ].include?(one.granted_by) }
      end

      # ------------------------------------------------------------------------------
      # Prepared items

      # What they have said they will make: `{ "Alchemist's Fire (Lesser)" => 2 }`.
      def self.plan(char)
        char.pf2_alchemy_plan || {}
      end

      def self.planned(char)
        plan(char).values.sum(&:to_i)
      end

      # An item is theirs to make where it is an alchemical consumable, no higher level than they are, and
      # they know its formula.
      def self.makeable(holder, name)
        found = Crafting.entry('consumables', name)

        return found if found.err?

        named, info = found.state

        return Err.new(:not_alchemical, 'pf2e.alchemy_not_alchemical', 'item' => named) unless makes?(holder, named, info)
        return Err.new(:too_high, 'pf2e.alchemy_too_high', 'item' => named, 'level' => info['level']) if info['level'].to_i > holder.pf2_level.to_i
        return Err.new(:no_formula, 'pf2e.alchemy_no_formula', 'item' => named) unless Crafting.known?(holder, 'consumables', named)

        found
      end

      def self.prepare!(char, name, quantity)
        return Err.new(:not_alchemist, 'pf2e.alchemy_not_alchemist') unless alchemist?(char)
        return Err.new(:cannot_prepare, 'pf2e.alchemy_cannot_prepare') if prepared_limit(char).zero?

        found = makeable(char, name)

        return found if found.err?

        named = found.state.first
        wanted = plan(char).merge(named => plan(char)[named].to_i + quantity.to_i).reject { |_name, many| many.to_i < 1 }

        return Err.new(:too_many, 'pf2e.alchemy_too_many', 'items' => prepared_limit(char)) if
          wanted.values.sum(&:to_i) > prepared_limit(char)

        char.update(:pf2_alchemy_plan => wanted)

        Ok.new(:state => wanted)
      end

      def self.consumable?(info)
        Array(info['traits']).map { |one| one.to_s.downcase }.include?('consumable')
      end

      def self.alchemical?(info)
        Array(info['traits']).map { |one| one.to_s.downcase }.include?('alchemical')
      end

      # What they can make: any alchemical consumable, and a potion they took through Improbable Elixirs,
      # which they make as an alchemical elixir.
      def self.makes?(holder, named, info)
        (alchemical?(info) && consumable?(info)) ||
          Pf2e.choice_labels_for(holder, 'Improbable Elixirs').any? { |one| one.to_s.casecmp?(named) }
      end

      def self.clear!(char, name = nil)
        char.update(:pf2_alchemy_plan => name ? plan(char).reject { |one, _many| one.casecmp?(name) } : {})
      end

      # The list as a rest makes it: in its own order, up to what they can make. What is past the cap is left
      # off, which a list written before the cap was lowered can be. Answers [ made, left off ].
      def self.capped(holder)
        room = prepared_limit(holder)

        plan(holder).each_with_object([ {}, {} ]) do |(name, many), (made, left_off)|
          taken = [ many.to_i, room ].min
          room -= taken

          made[name] = taken if taken.positive?
          left_off[name] = many.to_i - taken if many.to_i > taken
        end
      end

      # ------------------------------------------------------------------------------
      # Powerful Alchemy (5th)

      POWERFUL_ALCHEMY = 'Powerful Alchemy'.freeze

      # The DC an alchemist with Powerful Alchemy stamps on what they make: their class DC, which a save
      # against the item uses where it is higher than the item's own. Nil without the feature.
      def self.stamp(holder)
        Pf2e.holds_feature?(holder, POWERFUL_ALCHEMY) ? Stat.total(holder, 'class_dc') : nil
      end

      # An item made, with the stamp on it where there is one.
      def self.make!(holder, name, many, info, granted_by:, expires:, dc: nil)
        made = Equipment.grant!(holder, 'consumables', name, many, info, :granted_by => granted_by, :expires => expires)
        made.update(:dc => dc) if dc && made.respond_to?(:dc)
        made
      end

      # ------------------------------------------------------------------------------
      # A rest, and Quick Alchemy

      # A rest, or joining an encounter fresh: the day's vials, and the items on their list. What the last
      # day made has already lapsed. Answers what was made, as events for whoever tells it.
      def self.at_rest!(holder)
        return [] unless alchemist?(holder)

        vial = vial_name(holder.pf2_level)

        if max_vials(holder).positive?
          Equipment.grant!(holder, 'consumables', vial, max_vials(holder),
                           Global.read_config('pf2e_consumables', vial), :granted_by => VIALS, :expires => 'rest')
        end

        made, left_off = capped(holder)
        dc = stamp(holder)

        names = made.map do |name, many|
          found = Crafting.entry('consumables', name)

          next nil if found.err?

          make!(holder, found.state.first, many, found.state.last, :granted_by => PREPARED, :expires => 'rest', :dc => dc)

          "#{many} #{found.state.first}"
        end.compact

        events = []
        events << Turns.event('pf2e.alchemy_prepared', 'name' => holder.name, 'items' => names.join(', ')) if names.any?
        events << Turns.event('pf2e.alchemy_left_off', 'name' => holder.name, 'items' => left_off.map { |name, many| "#{many} #{name}" }.join(', '),
                              'cap' => prepared_limit(holder)) if left_off.any?
        events
      end

      TOOLKIT = "Alchemist's Toolkit".freeze

      # Quick Alchemy needs an alchemist's toolkit held or worn. Gear is never equipped here and hands
      # aren't tracked, so a toolkit carried outside a bag is as near as the game comes.
      def self.toolkit?(holder)
        Pf2egear::Inventory.held(holder, 'gear').any? { |item| item.name.to_s.casecmp?(TOOLKIT) }
      end

      # Quick Alchemy, in an encounter: a vial spent for each item, to hand until the start of their next
      # turn. Two items at once with Double Brew, from 9th level; one otherwise. Answers the names made.
      def self.quick!(holder, names)
        names = Array(names).map { |one| one.to_s.strip }.reject(&:empty?)

        return Err.new(:not_alchemist, 'pf2e.alchemy_not_alchemist') unless alchemist?(holder)
        return Err.new(:no_toolkit, 'pf2e.alchemy_no_toolkit') unless toolkit?(holder)
        return Err.new(:too_many_at_once, 'pf2e.alchemy_one_at_a_time') if names.size > brews(holder)

        found = names.map { |name| makeable(holder, name) }
        failed = found.find(&:err?)

        return failed if failed
        return Err.new(:no_vials_left, 'pf2e.alchemy_none_left', 'needed' => names.size) if left(holder) < names.size

        dc = stamp(holder)

        found.map do |made|
          named, info = made.state

          Consumables.spend!(holder, vials(holder).first.id)
          make!(holder, named, 1, info, :granted_by => QUICK, :expires => 'turn', :dc => dc)

          named
        end.then { |made| Ok.new(:state => made) }
      end

      # Gathering reagents in exploration: for every 10 minutes, 2 vials back, or 3 from Alchemical Expertise
      # at 9th level, up to their maximum. Only an alchemist whose allowance says `gathers`; the archetype
      # can't. The GM says how long they spent, so this is the GM's to call.
      ALCHEMICAL_EXPERTISE = 'Alchemical Expertise'.freeze

      def self.per_gathering(holder)
        Pf2e.holds_feature?(holder, ALCHEMICAL_EXPERTISE) ? 3 : 2
      end

      def self.gather!(holder, periods = 1)
        return Err.new(:not_alchemist, 'pf2e.alchemy_not_alchemist') unless alchemist?(holder)
        return Err.new(:cannot_gather, 'pf2e.gather_cannot', 'name' => holder.name) unless allowances(holder)['gathers']

        room = max_vials(holder) - left(holder)

        return Err.new(:full, 'pf2e.gather_full', 'name' => holder.name, 'max' => max_vials(holder)) unless room.positive?

        gained = [ per_gathering(holder) * [ periods.to_i, 1 ].max, room ].min
        name = vial_name(holder.pf2_level)

        Equipment.grant!(holder, 'consumables', name, gained, Global.read_config('pf2e_consumables', name),
                         :granted_by => VIALS, :expires => 'rest')

        Ok.new(:state => { 'gained' => gained, 'left' => left(holder) })
      end

      DOUBLE_BREW = 'Double Brew'.freeze

      # How many items one Quick Alchemy may make.
      def self.brews(holder)
        Pf2e.holds_feature?(holder, DOUBLE_BREW) ? 2 : 1
      end

      # Quick Vial: a versatile vial that spends nothing, and lasts until the end of their turn. It is only
      # a bomb, or a research field's vial use - never fuel for Quick Alchemy, which it isn't counted as.
      QUICK_VIAL = 'quick vial'.freeze

      def self.quick_vial!(holder)
        return Err.new(:not_alchemist, 'pf2e.alchemy_not_alchemist') unless alchemist?(holder)
        return Err.new(:no_toolkit, 'pf2e.alchemy_no_toolkit') unless toolkit?(holder)

        name = vial_name(holder.pf2_level)

        Equipment.grant!(holder, 'consumables', name, 1, Global.read_config('pf2e_consumables', name),
                         :granted_by => QUICK_VIAL, :expires => 'turn_end')

        Ok.new(:state => name)
      end
    end
  end
end
