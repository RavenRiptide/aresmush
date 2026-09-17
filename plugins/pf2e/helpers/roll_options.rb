module AresMUSH
  module Pf2e

    # The circumstances a character has switched on.
    #
    # A `RollOption` rule declares a circumstance rather than a number: a Clandestine Cloak declares
    # `clandestine-cloak` and predicates its own bonuses on it, so the cloak works only when the option
    # holds. Two hundred and nineteen rules on the things we stock are declarations of this kind, and
    # eighty-nine of them are asked about by another rule on the same item or feat.
    #
    # Foundry defaults a toggleable option to off and leaves the player to flip it. Here it is on
    # instead, because an item a character is wearing should do what it says without being asked - and a
    # player who wants it off can say so, which is what this store is for. Only a deliberate choice is
    # written down; an option nobody has touched follows the rule's own default.
    module RollOptions

      # `sheet/option <name>` writes one of these. Anything not held follows the declaration.
      OFF = false
      ON = true

      # Every option the character's feats, items and conditions declare, newest source last.
      #
      #   [ { 'option' =>, 'label' =>, 'source' =>, 'domain' =>, 'default' =>, 'on' => } ]
      def self.declared(char)
        chosen = char.pf2_roll_options || {}

        Effects.sources(char).flat_map do |source|
          Rules.of_kind(source, 'RollOption').map do |row|
            declaration(char, source, row, chosen)
          end
        end.compact
      end

      def self.declaration(char, source, row, chosen)
        held = Rules.contribute(row, source, Effects.context(char))

        return nil unless held && held['option']

        # A declaration with circumstances of its own is one we cannot establish, so it is offered and
        # left off rather than presumed.
        reachable = Predicate.test(row['predicate'], Effects.options_of(char, source))

        held.merge('on' => chosen.key?(held['option']) ? chosen[held['option']] : (held['default'] && reachable),
                   'chosen' => chosen.key?(held['option']),
                   'reachable' => reachable)
      end

      # The options that hold, as a predicate reads them.
      def self.active(char)
        declared(char).select { |one| one['on'] }.map { |one| one['option'] }.uniq
      end

      def self.set(char, option, on)
        held = (char.pf2_roll_options || {}).merge(option.to_s => !!on)

        char.update(:pf2_roll_options => held)
      end

      # Back to following the declaration, rather than off.
      def self.clear(char, option)
        held = char.pf2_roll_options || {}

        char.update(:pf2_roll_options => held.reject { |name, _| name == option.to_s })
      end

      # What the player may name, matched the way a player would type it.
      def self.find(char, term)
        wanted = Domains.slug(term)

        declared(char).find { |one| Domains.slug(one['option']) == wanted } ||
          declared(char).find { |one| Domains.slug(one['option']).include?(wanted) }
      end
    end
  end
end
