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

        wanted = name.to_s.strip.downcase
        found = list.find { |named, _info| named.downcase == wanted } ||
                list.select { |named, _info| named.downcase.include?(wanted) }.then { |some| some.size == 1 ? some.first : nil }

        return Err.new(:not_found, 'pf2e.nothing_to_display', 'elements' => 'formulas') unless found

        Ok.new(:state => found)
      end

      # Only a common formula is simply bought; anything rarer is the GM's to hand out. A rune says so in
      # its own `rarity` rather than in its traits.
      def self.common?(info)
        rarity = info['rarity'].to_s.downcase

        (Array(info['traits']).map(&:to_s).map(&:downcase) & %w{uncommon rare unique}).empty? &&
          (rarity.empty? || rarity == 'common')
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

        found = pool_categories(filter).flat_map do |category|
          (Global.read_config("pf2e_#{category}") || {}).select do |name, info|
            next false unless info.is_a?(Hash) && common?(info)
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
        staged = char.advancing ? ((char.pf2_advancement || {})['grants'] || {}).values : []
        books = [ char.pf2_formula_book || {} ] + staged.map { |grants| grants.is_a?(Hash) ? grants['formula'] : nil }.compact

        books.flat_map { |book| book.is_a?(Hash) ? book.values : [] }.flatten.map { |one| one.to_s.downcase }
      end

      def self.known?(char, category, name)
        Array((char.pf2_formula_book || {})[category]).any? { |one| one.casecmp?(name.to_s) }
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

      Array((char.pf2_formula_book || {}).values).flatten.any? { |one| one.to_s.casecmp?(item.to_s) }
    end
  end
end
