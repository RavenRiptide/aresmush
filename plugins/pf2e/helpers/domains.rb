module AresMUSH
  module Pf2e

    # What a statistic answers to, so an effect can name a group rather than a list of statistics.
    #
    # Frightened is "-1 status penalty to all your checks and DCs". Written against statistics that is
    # a line per skill, per save, per DC, and a line more every time a skill is added. Written against
    # domains it is one row naming `all`, and a skill added tomorrow is covered because it declares
    # `all` itself.
    #
    # The same mechanism carries the cases that are otherwise special: Clumsy penalises
    # Dexterity-based rolls, so it names `dex-based` and every statistic that reads Dexterity picks it
    # up - including a statistic that reads Dexterity only because some other effect said it could.
    #
    # Domains are Foundry's (`document.ts:568`, `752`, `784`, `844`, `1016`) and the slugs are theirs
    # too, so a converted rule element's `selector` needs no translation.
    module Domains

      # Every check and every DC answers to this. Hit points and speed are neither, which is why they
      # are the two kinds below that do not name it.
      ALL = 'all'.freeze

      # A statistic's kind decides its domains; adding a kind is adding a row. `name` is the
      # statistic's own name where it has one, and `ability` the attribute it reads.
      KINDS = [
        { 'name' => 'hp', 'domains' => ->(_name, _ability) { [ 'hp' ] } },
        { 'name' => 'speed', 'domains' => ->(_name, _ability) { [ 'speed', 'land-speed' ] } },
        { 'name' => 'ac', 'domains' => ->(_name, _ability) { [ 'ac', ALL ] } },
        { 'name' => 'perception', 'domains' => ->(_name, _ability) { [ 'perception', ALL ] } },
        { 'name' => 'save',
          'domains' => ->(name, _ability) { [ slug(name), 'saving-throw', ALL ] } },
        { 'name' => 'skill',
          'domains' => ->(name, ability) { [ slug(name), 'skill-check', ALL ] + skill_check(ability) } },
        # A lore is a skill whose name is the player's invention, so it answers to `lore-skill-check`
        # as well and an effect can reach every lore at once.
        { 'name' => 'lore',
          'domains' => ->(name, _ability) {
            [ slug(name), 'skill-check', 'lore-skill-check', ALL ] + skill_check('Intelligence')
          } },
        { 'name' => 'class_dc', 'domains' => ->(_name, _ability) { [ 'class-dc', ALL ] } },
        { 'name' => 'spell_dc', 'domains' => ->(_name, _ability) { [ 'spell-dc', ALL ] } },
        { 'name' => 'spell_attack',
          'domains' => ->(_name, _ability) { [ 'spell-attack', 'attack-roll', ALL ] } },
        { 'name' => 'attack', 'domains' => ->(_name, _ability) { [ 'attack-roll', ALL ] } }
      ].freeze

      BY_KIND = KINDS.each_with_object({}) { |row, out| out[row['name']] = row }.freeze

      # The attribute a statistic reads is a domain of its own, so an effect that penalises an
      # attribute reaches everything that reads it without naming any of them. A statistic may read
      # more than one - a finesse weapon's attack takes the better of Strength and Dexterity, and
      # Clumsy reaches it because it is Dexterity-based whichever of the two won.
      def self.for(kind, name = nil, ability = nil)
        row = BY_KIND[kind.to_s]

        raise ArgumentError, "no such kind of statistic: #{kind.inspect}" unless row

        (row['domains'].call(name, ability) + based(ability)).compact.uniq
      end

      # Whether an effect written against `selector` reaches a statistic with these domains. A selector
      # may name several, as Foundry's do.
      def self.matches?(selector, domains)
        (Array(selector).map { |named| slug(named) } & domains).any?
      end

      def self.based(ability)
        Array(ability).map { |one| abbreviation(one) }.compact.map { |abbr| "#{abbr}-based" }
      end

      def self.skill_check(ability)
        Array(ability).map { |one| abbreviation(one) }.compact.map { |abbr| "#{abbr}-skill-check" }
      end

      # Foundry writes an attribute's domains off its three-letter form: `dex-based`, not
      # `dexterity-based`.
      def self.abbreviation(ability)
        return nil if ability.to_s.strip.empty?

        ability.to_s[0, 3].downcase
      end

      def self.slug(name)
        name.to_s.strip.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
      end
    end
  end
end
