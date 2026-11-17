module AresMUSH
  module Pf2e

    # Formulas: what a character knows how to make.
    #
    # A formula is knowledge rather than a thing carried, so it belongs to the character and never to an
    # encounter's copy of what they carry. It is sheet state, so it is a grant like any other: the book on
    # the character is folded from the ledger, and `source_type` says how it was come by - bought, crafted,
    # or given by staff.
    #
    # PF2e prices a formula by the level of the item it makes rather than by that item's own price, and a
    # common formula is simply bought (Player Core p. 294).
    module Crafting

      def self.prices
        Global.read_config('pf2e_crafting', 'formula_price') || {}
      end

      # What a formula for an item of this level costs, in copper.
      def self.price(level)
        prices[level.to_i.clamp(0, 20)].to_i
      end

      # The catalogue entry a player named: exactly, or the only one holding the words they typed.
      def self.entry(category, name)
        list = Global.read_config("pf2e_#{category}")

        return Err.new(:bad_category, 'pf2e.bad_option', 'element' => 'category',
                       'options' => Pf2egear::Inventory.categories.join(', ')) unless list

        # What only a class feature makes - a versatile vial - has no formula to buy, learn or prepare from.
        list = list.reject { |_named, info| info.is_a?(Hash) && info['made_only'] }
        wanted = name.to_s.strip.downcase
        found = list.find { |named, _info| named.downcase == wanted } ||
                list.select { |named, _info| named.downcase.include?(wanted) }.then { |some| some.size == 1 ? some.first : nil }

        return Err.new(:not_found, 'pf2e.nothing_to_display', 'elements' => 'formulas') unless found

        Ok.new(:state => found)
      end

      # A choice's pool offers common formulas only; anything rarer is bought with access or given by staff.
      def self.common?(info)
        ItemAccess.common?(info)
      end

      # What a class or feat lets a character pick a formula from: the common items a `from_formulas`
      # filter names, less the formulas they know or have picked in the level they are taking.
      #
      #   category      catalogues to search, in order; consumables when absent
      #   traits        the item carries at least one
      #   all_traits    the item carries every one
      #   subcategory   the item's grouping where no trait marks it, such as an alchemical tool
      #   min_level     a number, or 'level' for the level the character is reaching
      #   max_level     the same
      def self.pool(char, filter)
        filter = {} unless filter.is_a?(Hash)
        reaching = char.pf2_level.to_i + (char.advancing ? 1 : 0)
        bound = lambda { |value| value.to_s.casecmp?('level') ? reaching : value.to_i }

        any = words(filter['traits'])
        every = words(filter['all_traits'])
        groups = words(filter['subcategory'])
        known = known_or_picked(char)
        held = books_or_picked(char)

        found = pool_categories(filter).flat_map do |category|
          (Global.read_config("pf2e_#{category}") || {}).select do |name, info|
            next false unless info.is_a?(Hash) && common?(info)
            next false if info['made_only']
            # Another type of something they know is no new formula.
            next false if Array(held[category]).any? { |one| covers?(category, one, name) }
            next false if filter.key?('min_level') && info['level'].to_i < bound.call(filter['min_level'])
            next false if filter.key?('max_level') && info['level'].to_i > bound.call(filter['max_level'])

            traits = words(info['traits'])
            grouped = groups.include?(info['subcategory'].to_s.downcase)

            next false unless every.all? { |one| traits.include?(one) }
            next false unless (any.empty? && groups.empty?) || (any & traits).any? || grouped

            true
          end.keys
        end

        found.uniq { |name| name.downcase }.reject { |name| known.include?(name.downcase) }.sort
      end

      # The catalogue a pick is filed under, and the name as the catalogue spells it: the first
      # catalogue in the filter's order that holds it.
      def self.pool_category(filter, label)
        pool_categories(filter).each do |category|
          named = (Global.read_config("pf2e_#{category}") || {}).keys.find { |name| name.casecmp?(label.to_s) }

          return [ category, named ] if named
        end

        nil
      end

      def self.pool_categories(filter)
        listed = Array((filter.is_a?(Hash) ? filter : {})['category']).map(&:to_s)

        listed.empty? ? [ 'consumables' ] : listed
      end

      def self.words(list)
        Array(list).map { |one| one.to_s.downcase }
      end

      # Mid-level, a formula picked in this level is staged rather than in the book yet.
      def self.known_or_picked(char)
        books_or_picked(char).values.flatten.map { |one| one.to_s.downcase }
      end

      # The book and this level's staged picks, merged: { category => [ names ] }.
      def self.books_or_picked(char)
        staged = char.advancing ? ((char.pf2_advancement || {})['grants'] || {}).values : []
        books = [ char.pf2_formula_book || {} ] + staged.map { |grants| grants.is_a?(Hash) ? grants['formula'] : nil }.compact

        books.select { |book| book.is_a?(Hash) }.each_with_object({}) do |book, out|
          book.each_pair { |category, names| out[category.to_s] = Array(out[category.to_s]) + Array(names).map(&:to_s) }
        end
      end

      # ------------------------------------------------------------------------------
      # Types of an item
      #
      # One formula makes every type of its item (GM Core p. 223): knowing the minor elixir of life's
      # formula, a crafter makes the lesser, moderate and greater ones too once their level allows. Two
      # exceptions keep a type to its own formula: types so different they are separate items (aeon stones,
      # marvelous miniatures), and a type rarer than the one whose formula they hold.
      #
      # The catalogues carry no field tying the types together, so the item is read from the name, with
      # its grade taken off. Only words on a fixed list of grades come off - a stone's `Preserving` or a
      # miniature's `Boat` is part of what the item is - which is what keeps the different items apart.
      # A name with both keeps what isn't a grade: `Energy Breath Potion (Fire, Lesser)` is a fire potion
      # of any grade, and never a cold one.

      GRADE = /\A(?:minor|lesser|moderate|greater|major|true|type\ [ivx]+|(?:exquisite\ )?(?:low|standard|high)-grade|
                 \d+(?:st|nd|rd|th)-rank\ spell|\+\d+(?:\ (?:greater\ |major\ )?striking)?)\z/xi

      # A rune names its grade in front: `Flaming`, `Greater Flaming`.
      RUNE_GRADE = /\A(?:greater|major|true)\s+/i

      RARITY_ORDER = %w{common uncommon rare unique}.freeze

      # The item a type belongs to, as a name: `Elixir of Life (Lesser)` is `Elixir of Life`.
      def self.family(category, name)
        text = name.to_s.strip
        text = text.sub(RUNE_GRADE, '') if category.to_s == 'runes'
        parts = text.match(/\A(.*\S)\s*\(([^()]*)\)\z/)

        return text unless parts

        inside = parts[2].split(',').map(&:strip)
        kept = inside.reject { |word| word.match?(GRADE) }

        return text if kept.size == inside.size

        kept.empty? ? parts[1] : "#{parts[1]} (#{kept.join(', ')})"
      end

      # Whether the formula for `known` lets them make `wanted`: the same item, or another type of it no
      # rarer than the one they hold.
      def self.covers?(category, known, wanted)
        return true if known.to_s.casecmp?(wanted.to_s)
        return false unless family(category, known).casecmp?(family(category, wanted))

        rarity_rank(info_for(category, known)) >= rarity_rank(info_for(category, wanted))
      end

      def self.rarity_rank(info)
        RARITY_ORDER.index(ItemAccess.rarity(info)) || 0
      end

      # A catalogue entry by any capitalization of its name.
      def self.info_for(category, name)
        list = Global.read_config("pf2e_#{category}") || {}

        list[name.to_s] || list.find { |named, _info| named.casecmp?(name.to_s) }&.last
      end

      # The formula in their book that lets them make the item, nil where none does. The item's own
      # formula comes first, so a message can name the formula they actually hold.
      def self.covering(char, category, name)
        book = Array((char.pf2_formula_book || {})[category]).map(&:to_s)

        book.find { |one| one.casecmp?(name.to_s) } || book.find { |one| covers?(category, one, name) }
      end

      def self.known?(char, category, name)
        !covering(char, category, name).nil?
      end

      # Whether this exact formula is written in their book - what staff can take out of it.
      def self.in_book?(char, category, name)
        Array((char.pf2_formula_book || {})[category]).any? { |one| one.to_s.casecmp?(name.to_s) }
      end

      # Every item in a catalogue their book lets them make, of any level.
      def self.makeable_names(char, category)
        book = Array((char.pf2_formula_book || {})[category]).map(&:to_s)

        return [] if book.empty?

        (Global.read_config("pf2e_#{category}") || {}).select do |name, info|
          info.is_a?(Hash) && !info['made_only'] && book.any? { |one| covers?(category, one, name) }
        end.keys
      end

      # What refuses a formula they don't need: the one they know, or the one that already makes it.
      def self.known_message(char, category, name)
        held = covering(char, category, name)

        return nil unless held
        return t('pf2e.formula_known', :formula => name) if held.casecmp?(name.to_s)

        t('pf2e.formula_covered', :known => held, :formula => name)
      end

      # The character learns it, however they came by it. Sheet state, so it goes through the ledger.
      def self.learn!(char, category, name, source_type:, source_ref:, granted_by: 'System')
        Ledger.write(char, :source_type => source_type, :source_ref => source_ref, :granted_by => granted_by) do |txn|
          txn.grant('grant_formula', 'category' => category, 'formula' => name)
        end
      end

      def self.forget!(char, category, name, by:)
        Ledger.revert_matching!(char, 'grant_formula', { 'category' => category, 'formula' => name }, :by => by)
      end

      # The book itself, which only the ledger's own appliers write.
      def self.write_formula(char, category, name, remove: false)
        book = char.pf2_formula_book || {}
        chapter = Array(book[category])

        book[category] = (remove ? chapter.reject { |one| one.casecmp?(name.to_s) } : (chapter + [ name ]).uniq).sort
        char.update(:pf2_formula_book => book)
      end
    end

    def self.has_formula?(name, enactor, item)
      return false unless enactor.is_admin?

      char = Pf2e.get_character(name, enactor)

      return false unless char

      (char.pf2_formula_book || {}).keys.any? { |category| Crafting.known?(char, category, item) }
    end
  end
end
