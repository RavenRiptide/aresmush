module AresMUSH
  module Pf2e

    # The sections of a character sheet, and who has one. Every sheet on Emblem of Ea is open, so
    # anyone may see any section a character has.
    #
    # `sheet` and `sheet/combat` both read from here, so they cannot disagree about which sections
    # exist or what a character needs to have one.
    #
    # One row per section, each saying what the character must have for it to exist.
    module Sheet

      # A section every character has needs no requirement. `requires` is a predicate on the
      # character; `code` and `key` are what a refusal says.
      SECTIONS = [
        { 'name' => 'all' },
        { 'name' => 'info' },
        { 'name' => 'attributes' },
        { 'name' => 'skills' },
        { 'name' => 'feats' },
        { 'name' => 'features' },
        { 'name' => 'languages' },
        { 'name' => 'combat' },
        {
          'name' => 'magic',
          'requires' => lambda { |char| !!char.magic },
          'code' => :not_caster,
          'key' => 'pf2emagic.not_caster'
        }
      ].freeze

      # Reasons a character has no sheet at all, tried before any section is considered - an
      # admin's sheet does not exist, and neither does one whose base info was never locked.
      MISSING = [
        { 'when' => lambda { |char| char.is_admin? }, 'code' => :admin_no_sheet, 'key' => 'pf2e.admin_no_sheet' },
        { 'when' => lambda { |char| !char.pf2_baseinfo_locked }, 'code' => :no_sheet_yet, 'key' => 'pf2e.no_sheet_yet' }
      ].freeze

      def self.sections
        SECTIONS.map { |s| s['name'] }
      end

      def self.section?(name)
        sections.include?(name.to_s.downcase)
      end

      # Whether this character has this section. Ok, or an Err naming what is missing.
      def self.available(char, name)
        missing = MISSING.find { |rule| rule['when'].call(char) }
        return Err.new(missing['code'], missing['key']) if missing

        section = SECTIONS.find { |s| s['name'] == name.to_s.downcase }

        unless section
          return Err.new(:bad_section, 'pf2e.bad_section', 'section' => name)
        end

        requires = section['requires']
        return Ok.new(:state => section['name']) if requires.nil? || requires.call(char)

        Err.new(section['code'], section['key'])
      end
    end
  end
end
