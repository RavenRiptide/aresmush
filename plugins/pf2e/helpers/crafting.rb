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

      # The DC of working on something of this level, and what its rarity adds.
      def self.craft_dc(info)
        table = Global.read_config('pf2e_crafting') || {}
        rarity = Array(info['traits']).map(&:to_s).map(&:downcase).find { |trait| (table['rarity_dc'] || {}).key?(trait) }

        (table['craft_dc'] || {})[info['level'].to_i.clamp(0, 25)].to_i + (table['rarity_dc'] || {})[rarity].to_i
      end

      # Only a common formula is simply bought; anything rarer is the GM's to hand out.
      def self.common?(info)
        (Array(info['traits']).map(&:to_s).map(&:downcase) & %w{uncommon rare unique}).empty?
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
