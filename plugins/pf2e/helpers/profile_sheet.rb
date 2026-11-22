module AresMUSH
  module Pf2e

    # The Pathfinder 2e section of a character's profile on the web portal. Each tab is the sheet as it
    # stands when the page loads, outside any encounter, and each is asked for the first time it is opened.
    #
    # One row per tab, each saying what the character must have for the tab to exist. Every tab also needs
    # an approved character with a sheet, and a viewer the game lets see sheets (`refusal`).
    module ProfileSheet

      TABS = [
        { 'name' => 'sheet' },
        { 'name' => 'combat' },
        {
          'name' => 'spells',
          'requires' => lambda { |char| Sheet.available(char, 'magic').ok? && Pf2emagic::Entries.for_magic(char.magic).any? },
          'code' => :not_caster,
          'key' => 'pf2e.profile_sheet_no_spells'
        },
        { 'name' => 'inventory' },
        {
          'name' => 'familiar',
          'requires' => lambda { |char| Familiar.approved?(char) },
          'code' => :no_familiar,
          'key' => 'pf2e.profile_sheet_no_familiar'
        }
      ].freeze

      def self.tabs
        TABS.map { |tab| tab['name'] }
      end

      # Whether a logged-out visitor may see sheets. One setting, so it can change without a code change.
      def self.anonymous?
        Global.read_config('pf2e', 'profile_sheet_anonymous') == true
      end

      # Why `viewer` may not see this tab of `char`'s sheet, or nil when they may. `viewer` is nil for a
      # visitor who isn't logged in.
      def self.refusal(char, viewer, tab)
        return Err.new(:not_found, 'pf2e.profile_sheet_not_found') unless char

        row = TABS.find { |one| one['name'] == tab.to_s }
        return Err.new(:bad_tab, 'pf2e.profile_sheet_bad_tab', 'tab' => tab) unless row

        named = { 'name' => char.name }
        return Err.new(:no_sheet, 'pf2e.profile_sheet_none', named) if char.is_admin? || !char.is_approved?
        return Err.new(:no_sheet, 'pf2e.profile_sheet_none', named) unless Sheet.available(char, 'all').ok?
        return Err.new(:login, 'pf2e.profile_sheet_login') if viewer.nil? && !anonymous?

        requires = row['requires']
        return nil if requires.nil? || requires.call(char)

        Err.new(row['code'], row['key'], named)
      end

      # Which tabs the profile draws, as `{ sheet: true, spells: false, ... }`, or nil for no section at all.
      # Nothing of the sheet is built here: only enough to decide which tabs to draw.
      def self.flags(char, viewer)
        return nil if refusal(char, viewer, 'sheet')

        tabs.to_h { |tab| [ tab.to_sym, refusal(char, viewer, tab).nil? ] }
      end

      # A named thing on the sheet: a feat, a feature, a spell, an item, a trait, a language or a skill. Each
      # travels with its kind so that a later popup can look it up without the views changing. `label` is
      # how the sheet shows it where that isn't its name: a feat with the choice it was taken for.
      def self.item(name, kind, label = nil)
        found = { name: name.to_s, kind: kind.to_s }
        label && label.to_s != name.to_s ? found.merge(label: label.to_s) : found
      end

      def self.items(names, kind)
        Array(names).map { |name| item(name, kind) }
      end

      # A refusal as the portal shows it.
      def self.error(err)
        { error: t(err.key, **err.args.transform_keys(&:to_sym)) }
      end

      # What a tab's request answers: its view, or why it may not be seen. The view is built with the
      # character's rows read once (`SheetReads.holding`).
      def self.answer(request, tab)
        char = Character[request.args['id']]
        viewer = request.enactor

        # A logged-in viewer's session is checked. A visitor who isn't logged in is refused below unless
        # anonymous viewing is on.
        login = viewer ? Website.check_login(request) : nil
        return login if login

        refused = refusal(char, viewer, tab)
        return error(refused) if refused

        SheetReads.holding(char) { yield(char) }
      end
    end
  end
end
