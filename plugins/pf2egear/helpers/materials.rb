module AresMUSH
  module Pf2egear

    # Weapons, armor, and shields made of a precious material (GM Core), from `pf2e_materials.yml`.
    #
    # A material is chosen when the item is bought or given and never changes, so what it does to the item's
    # own stats is worked out once and written onto the item: its price and level, a lighter material's
    # Bulk, dawnsilver and duskwood armor's Strength and Speed penalty, and a shield's Hardness and Hit
    # Points. Everything that reads those stats then reads the material's without knowing about it. What a
    # material does beyond its stats is read from the item's `material` where it applies: a weapon's material
    # in a Strike's damage, orichalcum's extra property-rune slot, and a material's own rules.
    module Materials

      GRADES = %w{low standard high}.freeze

      def self.table
        Global.read_config('pf2e_materials') || {}
      end

      def self.materials
        table['materials'] || {}
      end

      # A material by its name, ignoring case and spaces against hyphens: `cold iron`, `Cold-Iron`.
      def self.named(typed)
        wanted = Pf2e::Domains.slug(typed.to_s)

        materials.find { |name, _row| Pf2e::Domains.slug(name) == wanted }
      end

      def self.grade_named(typed)
        wanted = typed.to_s.downcase.strip.sub(/[\s-]*grade\z/, '')

        GRADES.find { |one| one == wanted }
      end

      # Which row of the material's table an item reads.
      def self.kind(category, name)
        case Inventory.canonical(category)
        when 'weapons' then 'weapon'
        when 'armor' then 'armor'
        when 'shields'
          return 'buckler' if name.to_s =~ /buckler/i
          return 'tower_shield' if name.to_s =~ /tower shield/i

          'shield'
        end
      end

      # What an item is made of, as GM Core sorts it: `:metal`, `:wood`, `:none` for what takes no precious
      # material (leather armor, a whip), or `:any` for a shield in neither shield list, such as a buckler,
      # which takes any material the table lists.
      def self.substance(category, name, info)
        case kind(category, name)
        when 'weapon'
          return :none if Array(table['no_material_weapons']).include?(name)
          return :wood if Array(table['wooden_weapons']).include?(name)

          :metal
        when 'armor'
          group = info['group'].to_s
          return :metal if Array(table['metal_armor_groups']).any? { |one| one.casecmp?(group) }
          return :wood if Array(table['wooden_armor_groups']).any? { |one| one.casecmp?(group) }

          :none
        else
          return :wood if Array(table['wooden_shields']).include?(name)
          return :metal if Array(table['metal_shields']).include?(name)

          :any
        end
      end

      # Traits that mark a specific magic item, which has its own price and takes no material.
      MAGIC_TRAITS = %w{magical invested arcane divine occult primal intelligent artifact cursed relic}.freeze

      # A catalogue row that is an ordinary item rather than a specific magic one. Its level doesn't say:
      # full plate is a 2nd-level ordinary item.
      def self.base_item?(info)
        # A row that is already made of a material (Sildanyari Chain) is a specific item too.
        !info['runes'] && !info['staff'] && !info['made_only'] && !info['material'] &&
          Array(info['traits']).none? { |one| MAGIC_TRAITS.include?(one.to_s.downcase) }
      end

      # The item as it would be made of the material: `{ 'material', 'info', 'rarity', 'rpp' }`, where
      # `info` is the catalogue row with the material's stats written in. An Err when the item can't be made
      # of it.
      def self.prepare(category, name, info, typed_material, typed_grade)
        found = named(typed_material)

        return Pf2e::Err.new(:no_material, 'pf2egear.material_unknown', 'material' => typed_material,
                             'materials' => materials.keys.join(', ')) unless found

        material, row = found
        grade = grade_named(typed_grade)

        return Pf2e::Err.new(:no_grade, 'pf2egear.material_bad_grade', 'grade' => typed_grade) unless grade
        return Pf2e::Err.new(:specific, 'pf2egear.material_specific', 'item' => name) unless base_item?(info)

        unfit = unfit(category, name, info, material, row)

        return unfit if unfit

        item_kind = kind(category, name)
        at = ((row['grades'] || {})[item_kind] || {})[grade]

        return Pf2e::Err.new(:no_such_grade, 'pf2egear.material_no_grade', 'material' => material, 'grade' => grade,
                             'item' => name, 'grades' => ((row['grades'] || {})[item_kind] || {}).keys.join(', ')) unless at

        rarity = row['rarity'].to_s

        Pf2e::Ok.new(:state => { 'material' => { 'name' => material, 'grade' => grade },
                                 'info' => made_of(info, item_kind, row, at),
                                 'rarity' => rarity,
                                 'rpp' => ((table['rpp'] || {})[rarity]).to_i })
      end

      # What `buy/material` would sell this character: `{ 'category', 'name', 'info', 'material', 'cost',
      # 'rpp' }`, or an Err. The item's own rarity goes through item access as any purchase does. The
      # material's rarity doesn't block it, and costs RPP instead (house rule).
      def self.quote(char, typed_category, typed_name, typed_material, typed_grade)
        category = Inventory.shop_category(typed_category)

        return Pf2e::Err.new(:bad_category, 'pf2egear.material_category') unless %w{weapons armor shields}.include?(category)

        found = ItemGiving.entry(category, typed_name)

        return found if found.err?

        name, info = found.state

        unless Pf2e::ItemAccess.accessible?(char, category, name, info)
          return Pf2e::Err.new(:no_access, 'pf2egear.no_access', 'item' => name, 'rarity' => Pf2e::ItemAccess.rarity(info))
        end

        made = prepare(category, name, info, typed_material, typed_grade)

        return made if made.err?

        level = made.state['info']['level'].to_i
        label = label(name, made.state['material'])

        return Pf2e::Err.new(:too_high, 'pf2egear.material_too_high', 'item' => label, 'level' => level) if level > char.pf2_level.to_i

        cost = made.state['info']['price'].to_i

        return Pf2e::Err.new(:poor, 'pf2egear.material_cant_afford', 'item' => label,
                             'cost' => Pf2egear.display_money(cost)) if cost > char.pf2_money.to_i

        rpp = made.state['rpp']
        held = char.player ? char.player.available_rpp.to_i : 0

        return Pf2e::Err.new(:no_rpp, 'pf2egear.material_needs_rpp', 'item' => label, 'rpp' => rpp,
                             'rarity' => made.state['rarity'], 'held' => held) if rpp > held

        Pf2e::Ok.new(:state => made.state.merge('category' => category, 'name' => name, 'cost' => cost))
      end

      # "Longsword (cold iron, standard grade)".
      def self.label(name, material)
        "#{name} (#{material['name'].downcase}, #{material['grade']} grade)"
      end

      # Makes it on their sheet with its material.
      def self.make!(char, prepared)
        item = Pf2egear.create_item(char, prepared['category'], prepared['name'], 1, prepared['info'])
        item.update(:material => prepared['material'])

        item
      end

      # Why an item can't be made of a material, or nil.
      def self.unfit(category, name, info, material, row)
        made = substance(category, name, info)

        return Pf2e::Err.new(:no_substance, 'pf2egear.material_none', 'item' => name) if made == :none
        return Pf2e::Err.new(:wood_only, 'pf2egear.material_wood_only', 'item' => name) if made == :wood && !row['wood']
        return Pf2e::Err.new(:metal_only, 'pf2egear.material_metal_only', 'item' => name, 'material' => material) if made == :metal && row['wood']

        nil
      end

      # The catalogue row with the material's stats written in.
      def self.made_of(info, item_kind, row, at)
        made = info.dup
        shield = %w{shield buckler tower_shield}.include?(item_kind)

        made['price'] = shield ? at['price'].to_i : at['price'].to_i + (at['price'].to_i * [ info['bulk'].to_f, 1 ].max / 10).round
        made['level'] = [ info['level'].to_i, at['level'].to_i ].max
        made['bulk'] = lighter(info['bulk'].to_f) if row['lighter']

        if shield
          made['hardness'] = at['hardness'].to_i
          made['hp'] = at['hp'].to_i
        end

        if item_kind == 'armor' && row['armor']
          made['min_str'] = [ info['min_str'].to_i - row['armor']['strength'].to_i, 0 ].max if info['min_str'].to_i.positive?
          made['speed_penalty'] = [ info['speed_penalty'].to_i + row['armor']['speed'].to_i, 0 ].min
        end

        made
      end

      # One Bulk less: 1 becomes light, and light or negligible stays as it is.
      def self.lighter(bulk)
        return bulk if bulk < 1
        return 0.1 if bulk == 1

        bulk - 1
      end

      # The material's row for an item that has one, or nil.
      def self.of(item)
        made = item.respond_to?(:material) ? (item.material || {}) : {}

        made['name'] ? named(made['name']) : nil
      end

      # A weapon's material as damage knows it: `cold-iron`. A shield boss or spikes attached to a shield also
      # carries the shield's, since a shield bash counts as a weapon of the shield's material.
      def self.slugs(item)
        found = [ of(item), of(shield_of(item)) ].compact

        found.map { |name, _row| Pf2e::Domains.slug(name) }.uniq
      end

      # The shield a weapon is attached to, or nil.
      def self.shield_of(weapon)
        return nil unless weapon.is_a?(PF2Weapon)

        PF2Shield.find(:weapon_id => weapon.id).first
      end

      # An adamantine weapon's own Hardness at its grade, or nil.
      def self.weapon_hardness(item)
        found = of(item)
        grade = found && item.material['grade']

        found ? (found.last['weapon_hardness'] || {})[grade] : nil
      end

      def self.rune_slots(item)
        found = of(item)

        found ? found.last['rune_slots'].to_i : 0
      end

      # Whether a property rune costs half as much on this item: quickstrike on orichalcum.
      def self.half_price_rune?(item, rune)
        found = of(item)

        !!found && Array(found.last['half_price_runes']).any? { |one| one.casecmp?(rune.to_s) }
      end

      # The rule elements an item of its material carries, for its kind: orichalcum armor's initiative.
      def self.rules(category, item)
        found = of(item)

        return [] unless found

        Array((found.last['rules'] || {})[kind(category, item.name)])
      end

      # A rest gives an orichalcum shield back its survival.
      def self.rested!(holder)
        return unless Pf2e::Actors.of(holder).carries_items?

        Inventory.held(holder, 'shields').select(&:survived_today).each { |one| one.update(:survived_today => false) }
      end

      # The line `item/view` shows.
      def self.describe(item)
        made = item.respond_to?(:material) ? (item.material || {}) : {}

        return [] unless made['name']

        [ t('pf2egear.material_line', :material => made['name'], :grade => made['grade']) ]
      end
    end
  end
end
