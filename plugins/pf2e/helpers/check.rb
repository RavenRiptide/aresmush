module AresMUSH
  module Pf2e

    # One check: what is being rolled, against what, and how it went.
    #
    # Everything up to now has assembled *figures* - a number on a sheet. A roll is not a figure: it has
    # a die in it, a DC it is measured against, an outcome, and circumstances of its own. Three kinds of
    # rule element in Foundry's data attach to the roll rather than to the figure, and none of them can
    # be read without something like this to attach to:
    #
    #   * `Note` - text shown with a roll when it went a particular way.
    #   * `AdjustDegreeOfSuccess` - a rule that turns a failure into a success.
    #   * `RollOption` - a circumstance declared for the duration of a roll.
    #
    # A check also supplies circumstances nothing else can. Deafened's own rule is predicated on
    # `check:type:skill` and `check:statistic:base:perception` - it penalises a Perception check and an
    # auditory skill check, not every check - and those facts are true of the roll, not of the
    # character. Their spelling is Foundry's (`statistic/statistic.ts:520`), so their predicates read
    # here unchanged.
    #
    # The check is built, then rolled. Building it is free of dice, so the sheet can ask what a check
    # would be worth and a roll can ask what it came to, off the same object.
    class Check

      attr_reader :char, :kind, :name, :options, :domains, :breakdown

      # A check on one of the character's figures. `options` are the circumstances the roller named.
      def self.of(char, kind, name = nil, options = [], extra_domains = [])
        new(char, kind, name, options, extra_domains)
      end

      def initialize(char, kind, name, options, extra_domains)
        @char = char
        @kind = kind.to_s
        @name = name
        @extra_domains = Array(extra_domains)

        @breakdown = Stat.of(char, @kind, name, Array(options) + own_options, @extra_domains)
        @domains = Domains.for(@kind, domain_name, ability) + @extra_domains
        @options = Effects.options(char, @domains) + Array(options) + own_options
      end

      def total
        @breakdown['total']
      end

      # The circumstances the roll itself establishes, which are true of no figure and of no character.
      #
      # An attack carries the weapon's own facts too, because a rule about the attack is written against
      # them: a keen rune turns a near miss into a critical hit for a slashing or piercing weapon.
      def own_options
        @own_options ||= [ "check:statistic:#{statistic_slug}",
                           "check:type:#{check_type}" ] + base_statistic_options + attack_facts
      end

      def attack_facts
        return [] unless @name.is_a?(Hash)

        Pf2eCombat.attack_options(@name, @char)
      end

      # `skill`, `perception`, `saving-throw`, `attack-roll`: what kind of check this is, which is what
      # a rule about a kind of check is written against.
      TYPES = { 'skill' => 'skill', 'lore' => 'skill', 'perception' => 'perception',
                'save' => 'saving-throw', 'attack' => 'attack-roll', 'initiative' => 'initiative',
                'spell_attack' => 'spell-attack-roll', 'class_dc' => 'class-dc',
                'spell_dc' => 'spell-dc' }.freeze

      # A check built on another statistic is that check, not the one underneath: rolling initiative off
      # Perception is an initiative check whose base statistic is Perception, and Deafened's own rule
      # distinguishes the two. Initiative is the only such check there is.
      BUILT_ON = 'initiative'.freeze

      def statistic_slug
        return BUILT_ON if @extra_domains.include?(BUILT_ON)
        # A descriptor names the thing being rolled where it has a name - a weapon does, an archetype's
        # class DC does not, and then the kind of statistic is what it is called.
        return Domains.slug(@name['name'] || @kind) if @name.is_a?(Hash)

        @name ? Domains.slug(domain_name) : Domains.slug(@kind)
      end

      def base_statistic_options
        return [] unless @extra_domains.include?(BUILT_ON)

        [ "check:statistic:base:#{Domains.slug(@name || @kind)}" ]
      end

      def check_type
        return BUILT_ON if @extra_domains.include?(BUILT_ON)

        TYPES.fetch(@kind, @kind)
      end

      def domain_name
        return @name unless @kind == 'save'

        Pf2e.canonical_save(@name)
      end

      def ability
        row = Stat::BY_KIND[@kind]

        row && row['ability'].call(@char, @name)
      end

      # ------------------------------------------------------------------------------

      # How the roll went. `die` is the face of the d20, which shifts the outcome by a degree either
      # way; `dc` is what it was measured against, and without one there is no outcome to speak of.
      def outcome(total, dc, die = nil)
        return nil unless dc

        Degree.adjusted(Degree.of(total, dc, die), adjustments(rolled(total, dc, die)))
      end

      # What the roll itself establishes once it has been rolled, which is what a rule about a near miss
      # asks about: a keen weapon turns a 19 into a critical hit. Their spelling (`check/check.ts:187`).
      def rolled(total, dc, die)
        [ "check:total:#{total}",
          die ? "check:total:natural:#{die}" : nil,
          die ? "check:roll:total:natural:#{die}" : nil,
          dc ? "check:total:delta:#{total - dc}" : nil ].compact
      end

      # Rules that turn one outcome into another: Assurance makes a failure a success, Deafened drops an
      # auditory Perception check to a critical failure.
      def adjustments(rolled = [])
        Rules.adjustments(Effects.sources(@char), @domains, @options + Array(rolled))
      end

      # Text to show with the roll. `Note` is the one kind of rule element attached to a roll that is not
      # read yet, and asking for notes here is what makes reading it a change to one table rather than
      # to this.
      def notes
        Rules.notes(Effects.sources(@char), @domains, @options)
      end
    end
  end
end
