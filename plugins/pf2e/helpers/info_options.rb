module AresMUSH
  module Pf2e

    INFO_FEAT_SLOT_TYPES = %w(general skill ancestry charclass archetype dedication)

    # Lists at or below this go out as a single line; longer ones get the paginated template.
    INFO_PAGINATE_LIMIT = 20

    # Entries per page once paging kicks in. Two columns, so this is 20 rows.
    INFO_PAGE_SIZE = 40

    # `<element>=<filter>`, with either half allowed to be missing. The element may itself hold
    # spaces, and only the first `=` separates the two.
    def self.split_info_filter(args)
      element, _, filter = args.to_s.partition('=')
      element = element.strip
      filter = filter.strip

      [ element.empty? ? nil : element, filter.empty? ? nil : filter ]
    end

    def self.info_options(char, element)
      return nil if element.blank?

      # A pending feat choice, by name. This is the Assurance case: the player is told to run 'cg/info Assurance' when they take it, and gets the skills still open to them.
      pending = pending_feat_choices(char)
      key = pending.keys.find { |k| k.to_s.casecmp?(element.to_s) }

      if key
        block = find_choice_block(char, key)
        return nil unless block

        # A formula choice also hands back its pool filter, so the list can show each formula under
        # its catalogue and level.
        formulas = block['from_formulas'].is_a?(Hash) ? block['from_formulas'] : nil

        return [ key, choice_options(char, key, block), formulas ]
      end

      # A feat slot type. 'general' and 'general feat' both work.
      type = element.to_s.downcase.strip.sub(/\s+feats?\z/, '')

      if INFO_FEAT_SLOT_TYPES.include?(type)
        return [ t('pf2e.info_feat_title', :type => type.capitalize), get_feat_options(char, type) ]
      end

      nil
    end

    # `filter` narrows the pool by substring before paging. A pool of two hundred lores is six
    # pages, which is barely more use to a player than the refusal that sent them here.
    #
    # `formulas` is a formula choice's pool filter. Its options list like the `formulas` screen, by
    # catalogue and item level, at any length, so no name is cut to fit a column.
    def self.info_option_display(title, options, cmd, filter = nil, formulas: nil, client: nil)
      options = Array(options).compact

      return { :error => t('pf2e.info_no_options', :element => title) } if options.empty?

      unless filter.to_s.strip.empty?
        wanted = filter.to_s.strip.downcase
        options = options.select { |option| option.to_s.downcase.include?(wanted) }

        return { :error => t('pf2e.info_no_match', :element => title, :filter => filter.to_s.strip) } if options.empty?
      end

      return formula_option_display(title, options, formulas, cmd, client) if formulas

      if options.size <= INFO_PAGINATE_LIMIT
        return { :text => t('pf2e.cg_info', :element => title, :options => options.join(", ")) }
      end

      paginator = Paginator.paginate(options, cmd.page, INFO_PAGE_SIZE)

      return { :error => paginator.out_of_bounds_msg } if paginator.out_of_bounds?

      { :text => PF2OptionListTemplate.new(paginator, title, 2, cmd).render }
    end

    # Each formula filed under the catalogue a pick of it would go to - the first of the filter's
    # catalogues that holds it - then paged by whole level groups.
    def self.formula_option_display(title, names, formulas, cmd, client = nil)
      fallback = Crafting.pool_categories(formulas).first

      book = names.group_by { |name| (Crafting.pool_category(formulas, name) || [ fallback ]).first }
      ordered = Crafting.pool_categories(formulas).each_with_object({}) do |category, out|
        out[category] = book[category] if book[category]
      end
      book.each { |category, list| ordered[category] ||= list }

      template = PF2FormulaTemplate.new(ordered, nil, client, :title => title, :cmd => cmd, :page_size => INFO_PAGE_SIZE)

      return { :error => template.paginator.out_of_bounds_msg } if template.paginator.out_of_bounds?

      { :text => template.render }
    end

  end
end
