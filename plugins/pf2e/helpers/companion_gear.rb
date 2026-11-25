module AresMUSH
  module Pf2e
    module Companion

      # What an animal companion wears (Player Core's Companion Items): barding, and items with the companion
      # trait, such as a collar or horseshoes. Staff may put on an item without the trait. A companion never
      # activates an item, so activation stays the character's (`use`).
      #
      # A worn item stays in the character's inventory, at the same number, with `companion` set to the
      # companion's id. Its Bulk isn't the character's (`Pf2egear::Bulk`), and it can't be sold, stowed in a
      # bag, or invested by the character until it comes off. Wearing one of a stack splits it, and taking it
      # off joins it back to a matching stack.
      #
      # An item with the invested trait is invested by the companion as it goes on, and stays invested while
      # it's worn: `companion_invested`, never the character's `invested` or `invest_on_refresh`. A companion
      # can have 2 items invested.
      #
      # What the catalogues say:
      #   companion_armor   barding's AC bonus, Dex cap, penalties and Strength, and `sizes`, the companion sizes
      #                     it fits (none: it adjusts to fit)
      #   companion_bonus   item bonuses it gives the companion: `speed`, to its land Speed
      #   companion_needs   `quadruped`: only a type marked `quadruped` in pf2e_animal_companions.yml can wear it
      #
      # What the companion can no longer wear (barding it has outgrown; horseshoes on a new companion that isn't
      # four-legged), and anything worn by a companion they no longer have, comes off and goes back to the
      # inventory (`settle!`), each time the ledger writes the finished sheet.
      module Gear

        CATEGORIES = %w{gear magicitem}.freeze
        INVEST_LIMIT = 2
        MODELS = { 'PF2Gear' => 'gear', 'PF2MagicItem' => 'magicitem' }.freeze

        # ------------------------------------------------------------------------------------------------
        # The pure core
        # ------------------------------------------------------------------------------------------------

        def self.worn?(item)
          item.respond_to?(:companion) && !item.companion.to_s.empty?
        end

        def self.armor_of(info)
          found = (info || {})['companion_armor']
          found.is_a?(Hash) ? found : nil
        end

        # Whether barding fits a companion of that size.
        def self.fits?(armor, size)
          sizes = Array((armor || {})['sizes'])
          sizes.empty? || sizes.include?(size.to_s)
        end

        # The item bonuses worn items give together. Item bonuses don't stack, so the highest of each counts.
        def self.item_bonuses(facts)
          facts.each_with_object({}) do |one, out|
            (one['bonus'] || {}).each { |kind, value| out[kind.to_s] = [ out[kind.to_s].to_i, value.to_i ].max }
          end
        end

        def self.invested_count(facts)
          facts.count { |one| one['invested'] }
        end

        # Whether a worn item can stay on a companion of that type (its catalogue entry) and size. Without a
        # type or size yet, it stays.
        def self.stays_on?(item, type_info, size)
          return false if item['armor'] && size && !fits?(item['armor'], size)
          return false if item['needs'].include?('quadruped') && type_info && type_info['quadruped'] != true

          true
        end

        # Why the companion can't wear an item, as an Err, or nil. `item` and each of `worn` are `facts`;
        # `type_info` is the companion's type from the catalogue; `size` its size now; `names` is `wearer`'s.
        # `staff` allows an item without the companion trait.
        def self.refusal(item, worn:, type_info:, type:, size:, names:, staff: false)
          unless staff || Pf2e.has_trait?(item['traits'], 'companion')
            return Err.new(:companion_gear_not_companion, 'pf2e.companion_gear_not_companion', { 'item' => item['name'] }.merge(names))
          end

          if item['armor']
            barding = worn.find { |one| one['armor'] }
            if barding
              return Err.new(:companion_gear_second_barding, 'pf2e.companion_gear_second_barding',
                             { 'barding' => barding['name'] }.merge(names))
            end

            unless fits?(item['armor'], size)
              return Err.new(:companion_gear_wrong_size, 'pf2e.companion_gear_wrong_size',
                             { 'item' => item['name'], 'sizes' => Array(item['armor']['sizes']).join(' or '), 'size' => size.to_s }.merge(names))
            end
          end

          if item['needs'].include?('quadruped') && (type_info || {})['quadruped'] != true
            return Err.new(:companion_gear_needs_quadruped, 'pf2e.companion_gear_needs_quadruped',
                           { 'item' => item['name'], 'type' => type.to_s.downcase }.merge(names))
          end

          if item['investable'] && invested_count(worn) >= INVEST_LIMIT
            held = worn.select { |one| one['invested'] }.map { |one| one['name'] }
            return Err.new(:companion_gear_invest_full, 'pf2e.companion_gear_invest_full',
                           { 'max' => INVEST_LIMIT, 'items' => held.join(' and ') }.merge(names))
          end

          nil
        end

        # ------------------------------------------------------------------------------------------------
        # Reading a character
        # ------------------------------------------------------------------------------------------------

        def self.category_of(item)
          MODELS[item.class.name.split('::').last]
        end

        # An item as `refusal` and the stats take it.
        def self.facts(item)
          info = Pf2egear.catalogue_entry(category_of(item), item) || {}

          { 'name' => Pf2egear.get_item_name(item),
            'traits' => Array(item.traits),
            'armor' => armor_of(info),
            'bonus' => info['companion_bonus'].is_a?(Hash) ? info['companion_bonus'] : {},
            'needs' => Array(info['companion_needs']).map(&:to_s),
            'investable' => Pf2e.has_trait?(item.traits, 'invested'),
            'invested' => !!item.companion_invested }
        end

        # Everything any companion of theirs wears, bags aside (a worn item is never in one).
        def self.worn_items(char)
          CATEGORIES.flat_map { |category| Pf2egear::Inventory.all(char, category) }.select { |item| worn?(item) }
        end

        def self.worn(char, companion)
          return [] unless companion

          worn_items(char).select { |item| item.companion.to_s == companion['id'].to_s }
        end

        # What the stats take from what it wears: `barding` and `item_bonuses`. Only invested items give
        # their bonuses.
        def self.stat_args(char, companion)
          facts = worn(char, companion).map { |item| facts(item) }
          barding = facts.find { |one| one['armor'] }

          { :barding => barding ? { 'name' => barding['name'], 'companion_armor' => barding['armor'] } : nil,
            :item_bonuses => item_bonuses(facts.select { |one| one['invested'] || !one['investable'] }) }
        end

        # Who wears an item, by name: "Ash", or "your animal companion" before it has one or once it's gone.
        # For staff, "Rowan's animal companion".
        def self.wearer_name(char, item = nil, staff: false)
          companion = Companion.main(char)
          same = companion && (item.nil? || item.companion.to_s == companion['id'].to_s)
          named = same && Companion.name_of(char, companion)
          return named if named

          staff ? t('pf2e.companion_subject_unnamed_of', :char => char.name) : t('pf2e.companion_subject_unnamed_mid')
        end

        # Who wears an item, for messages: `name` to open a sentence ("Ash", "Your animal companion"), and
        # `mid` within one.
        def self.wearer(char, item = nil, staff: false)
          mid = wearer_name(char, item, :staff => staff)
          { 'name' => mid.sub(/\A\p{L}/) { |first| first.upcase }, 'mid' => mid }
        end

        # The staff forms of wear and remove: each message that speaks to the owner ("your"), and what staff
        # see in its place, given the character's name as `char`.
        STAFF_KEYS = {
          'pf2e.companion_none_yours' => 'pf2e.companion_none',
          'pf2e.companion_gear_untyped' => 'pf2e.companion_gear_untyped_staff',
          'pf2e.companion_gear_category' => 'pf2e.companion_gear_category_staff',
          'pf2e.companion_gear_already' => 'pf2e.companion_gear_already_staff',
          'pf2e.companion_gear_invested_yours' => 'pf2e.companion_gear_invested_yours_staff',
          'pf2e.companion_gear_not_worn' => 'pf2e.companion_gear_not_worn_staff',
          'pf2e.companion_gear_second_barding' => 'pf2e.companion_gear_second_barding_staff',
          'pf2e.companion_gear_invest_full' => 'pf2e.companion_gear_invest_full_staff',
          'pf2egear.item_in_encounter' => 'pf2e.companion_gear_in_encounter_staff'
        }.freeze

        # The outcome as staff see it: the same code, with the staff message.
        def self.for_staff(outcome, char)
          return outcome unless outcome.err? && STAFF_KEYS[outcome.key]

          Err.new(outcome.code, STAFF_KEYS[outcome.key], outcome.args.merge('char' => char.name))
        end

        # Why a command can't touch an item the companion wears (sell, bag/store, invest), or nil.
        def self.worn_refusal(item)
          return nil unless worn?(item)

          char = item.respond_to?(:character) ? item.character : nil
          names = char ? wearer(char, item) : { 'name' => t('pf2e.companion_subject_unnamed'), 'mid' => t('pf2e.companion_subject_unnamed_mid') }
          Err.new(:on_companion, 'pf2egear.item_on_companion', { 'item' => Pf2egear.get_item_name(item) }.merge(names))
        end

        # ------------------------------------------------------------------------------------------------
        # Putting things on and taking them off
        # ------------------------------------------------------------------------------------------------

        # Puts the item at `index` of `category` (as `gear` numbers them) on their companion. An Ok carries
        # the worn item and how many the companion has invested. `staff` allows an item without the companion
        # trait, and words what it says for staff.
        def self.wear!(char, category, index, staff: false)
          outcome = wearing!(char, category, index, staff)
          staff ? for_staff(outcome, char) : outcome
        end

        def self.wearing!(char, category, index, staff)
          companion = Companion.main(char)
          return Err.new(:companion_none, 'pf2e.companion_none_yours') unless companion
          return Err.new(:companion_gear_untyped, 'pf2e.companion_gear_untyped') unless companion['type']

          category = Pf2egear::Inventory.canonical(category)
          return Err.new(:companion_gear_category, 'pf2e.companion_gear_category') unless CATEGORIES.include?(category)

          found = Pf2egear::Inventory.item(char, category, index)
          return found if found.err?

          item = found.state
          names = wearer(char, :staff => staff)
          shown = Pf2egear.get_item_name(item)
          held = Pf2e::Equipment.held_by(item)

          return Err.new(:in_encounter, 'pf2egear.item_in_encounter', 'item' => item.name, 'id' => held.id) if held
          return Err.new(:companion_gear_already, 'pf2e.companion_gear_already', { 'item' => shown }.merge(names)) if worn?(item)

          if (item.respond_to?(:invested) && item.invested) || (item.respond_to?(:invest_on_refresh) && item.invest_on_refresh)
            return Err.new(:companion_gear_invested_yours, 'pf2e.companion_gear_invested_yours', { 'item' => shown }.merge(names))
          end

          stats = Companion.stats(char, companion, :draft => false)
          wearing = worn(char, companion).map { |one| facts(one) }
          about = facts(item)
          refused = refusal(about, :worn => wearing, :type_info => Stats.type_info(companion['type']), :type => companion['type'],
                            :size => stats && stats['size'], :names => names, :staff => staff)
          return refused if refused

          on = put_on!(item, companion, :invest => about['investable'])

          Ok.new(:state => { 'item' => on, 'shown' => shown, 'invested' => about['investable'],
                             'count' => invested_count(wearing) + (about['investable'] ? 1 : 0) }.merge(names))
        end

        # One of a stack goes on, and the rest stay in the inventory.
        def self.put_on!(item, companion, invest:)
          worn = { :companion => companion['id'], :companion_invested => invest ? true : nil }

          if item.respond_to?(:quantity) && item.quantity.to_i > 1
            on = item.class.create(item.attributes.except(:created_at, :updated_at).merge(worn).merge(:quantity => 1))
            item.update(:quantity => item.quantity.to_i - 1)
            return on
          end

          item.update(worn)
          item
        end

        # Takes the item at `index` of `category` off whichever companion wears it. `staff` words what it
        # says for staff.
        def self.remove!(char, category, index, staff: false)
          outcome = removing!(char, category, index, staff)
          staff ? for_staff(outcome, char) : outcome
        end

        def self.removing!(char, category, index, staff)
          category = Pf2egear::Inventory.canonical(category)
          return Err.new(:companion_gear_category, 'pf2e.companion_gear_category') unless CATEGORIES.include?(category)

          found = Pf2egear::Inventory.item(char, category, index)
          return found if found.err?

          item = found.state
          names = wearer(char, item, :staff => staff)
          shown = Pf2egear.get_item_name(item)

          unless worn?(item)
            return Err.new(:companion_gear_not_worn, 'pf2e.companion_gear_not_worn', { 'item' => shown }.merge(wearer(char, :staff => staff)))
          end

          held = Pf2e::Equipment.held_by(item)
          return Err.new(:in_encounter, 'pf2egear.item_in_encounter', 'item' => item.name, 'id' => held.id) if held

          take_off!(char, item)
          Ok.new(:state => { 'shown' => shown }.merge(names))
        end

        # Back in the inventory, uninvested, joining a matching stack there.
        def self.take_off!(char, item)
          category = category_of(item)

          if Pf2egear::Inventory.stackable?(category)
            same = Pf2egear::Inventory.held(char, category).find do |one|
              one.id != item.id && !worn?(one) && Pf2egear::Stowing.alike?(one, item)
            end

            if same
              same.update(:quantity => same.quantity.to_i + item.quantity.to_i)
              item.delete
              return same
            end
          end

          item.update(:companion => nil, :companion_invested => nil)
          item
        end

        # What would come off if the companion became `type` at `size`: barding that wouldn't fit, and items
        # that need a four-legged companion. By name.
        def self.coming_off(char, companion, type:, size:)
          info = Stats.type_info(type)
          worn(char, companion).map { |item| facts(item) }.reject { |one| stays_on?(one, info, size) }.map { |one| one['name'] }
        end

        # What comes off when they finish the level they're advancing, worked out while it's still open.
        def self.coming_off_at_level(char)
          companion = Companion.list(char).first
          found = Companion.stats(char, companion)
          found ? coming_off(char, companion, :type => companion['type'], :size => found['size']) : []
        end

        # Takes off what can't stay on: what the companion can no longer wear, and anything worn by a companion
        # they no longer have. Answers the names of what came off.
        def self.settle!(char)
          items = worn_items(char)
          return [] if items.empty?

          companions = Companion.list(char, :draft => false).to_h do |companion|
            found = Companion.stats(char, companion, :draft => false)
            [ companion['id'].to_s, { 'info' => Stats.type_info(companion['type']), 'size' => found && found['size'] } ]
          end

          items.filter_map do |item|
            held = companions[item.companion.to_s]
            next nil if held && stays_on?(facts(item), held['info'], held['size'])

            shown = Pf2egear.get_item_name(item)
            take_off!(char, item)
            shown
          end
        end
      end
    end
  end
end
