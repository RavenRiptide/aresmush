module AresMUSH
  module Pf2e

    # A figure on the sheet, and the arithmetic behind it.
    #
    # Each of these used to be assembled by hand in whichever model owned it, and they did not agree
    # on shape: a save counted its armour rune and the class DC counted no item bonus, a skill's item
    # bonus was added by the roll parser but not by the skill reader, and nothing anywhere could say
    # "these two bonuses do not stack" because nothing carried a type.
    #
    # Now a kind of statistic is a row: what its base is, and which modifiers are intrinsic to it -
    # the attribute it reads, the rune on the armour worn for it. Everything else reaches it through
    # `Pf2e::Domains`, so a feat or a condition that changes it is config rather than code.
    #
    #   Pf2e::Stat.of(char, 'save', 'Fortitude')
    #   # => { 'base' => 12, 'modifiers' => [ … ], 'total' => 15 }
    #
    # The list is the point as much as the total: a player can see that the ring was counted and the
    # spell was overridden, rather than being handed a number and asked to trust it.
    module Stat

      # One row per kind of figure. `base` is what the figure is before anything modifies it;
      # `intrinsic` are the modifiers the figure carries by its own nature, which are typed so they
      # obey the same stacking rule as everything else; `ability` names the attribute it reads, which
      # decides its `<attr>-based` domain. `domain_name` is for a figure a caller may name more than
      # one way - a save is asked for as both `fort` and `fortitude`, and both have to answer to the
      # same domain.
      KINDS = [
        { 'name' => 'hp',
          'ability' => ->(_char, _name) { nil },
          # Constitution is inside the base because it is per level. Drained's own row multiplies by
          # level to match, which is what adopting a formula language buys.
          'base' => ->(char, _name) { Pf2eHP.base_max_hp(char) },
          'intrinsic' => ->(_char, _name) { [] } },

        { 'name' => 'speed',
          'ability' => ->(_char, _name) { nil },
          'base' => ->(char, _name) { Pf2e.ancestry_speed(char) },
          # Armour slows a character by its own untyped amount, so Encumbered's status penalty is on
          # top of it rather than competing with it.
          'intrinsic' => ->(char, _name) { [ armor_penalty(char) ] } },

        { 'name' => 'ac',
          'ability' => ->(_char, _name) { 'Dexterity' },
          'base' => ->(char, _name) { Pf2eCombat.base_ac(char) },
          'intrinsic' => ->(char, _name) { Pf2eCombat.ac_modifiers(char) } },

        { 'name' => 'perception',
          'ability' => ->(_char, _name) { 'Wisdom' },
          'base' => ->(char, _name) { Pf2e.get_prof_bonus(char, char.combat&.perception) },
          'intrinsic' => ->(char, _name) { [ ability_mod(char, 'Wisdom') ] } },

        { 'name' => 'save',
          'ability' => ->(_char, name) { Pf2e::LINKED_ABILITY[name.to_s.downcase] },
          'domain_name' => ->(name) { Pf2e.canonical_save(name) },
          'base' => ->(char, name) {
            Pf2e.get_prof_bonus(char, Pf2eCombat.get_save_from_char(char, name))
          },
          'intrinsic' => ->(char, name) {
            [ ability_mod(char, Pf2e::LINKED_ABILITY[name.to_s.downcase]),
              # This game's armour carries `potency` for AC and `power` for saves, which is what the
              # rules call resilient.
              rune(char, 'power') ]
          } },

        { 'name' => 'skill',
          'ability' => ->(_char, name) { Pf2eSkills.get_linked_attr(name) },
          'base' => ->(char, name) { Pf2e.get_prof_bonus(char, Pf2eSkills.get_skill_prof(char, name)) },
          'intrinsic' => ->(char, name) { [ ability_mod(char, Pf2eSkills.get_linked_attr(name)) ] } },

        { 'name' => 'lore',
          'ability' => ->(_char, _name) { 'Intelligence' },
          'base' => ->(char, name) { Pf2e.get_prof_bonus(char, Pf2eSkills.get_skill_prof(char, name)) },
          'intrinsic' => ->(char, _name) { [ ability_mod(char, 'Intelligence') ] } },

        # Here `name` is a descriptor rather than a name: `Pf2eCombat.attack_descriptor` builds one
        # from a weapon and one from an unarmed attack, so both go through the same arithmetic.
        #
        # A ranged attack reads Dexterity, a finesse attack the better of Strength and Dexterity -
        # which is not a comparison here, because both are offered as `ability` modifiers and the
        # stacking rule takes the better of them by itself.
        { 'name' => 'attack',
          'ability' => ->(_char, attack) { attack_abilities(attack) },
          'base' => ->(char, attack) { Pf2e.get_prof_bonus(char, attack['prof']) },
          'intrinsic' => ->(char, attack) {
            attack_abilities(attack).map { |ability| ability_mod(char, ability) } +
              [ item(attack['rune'], 'potency rune', 'weapon-potency') ]
          } },

        # `name` is the caster stats block `Pf2emagic.get_caster_stats` returns, which already carries
        # the proficiency and the casting attribute.
        { 'name' => 'spell_dc',
          'ability' => ->(_char, caster) { caster['spell_abil'] },
          'base' => ->(char, caster) { 10 + Pf2e.get_prof_bonus(char, caster['prof_level']) },
          'intrinsic' => ->(char, caster) { [ ability_mod(char, caster['spell_abil']) ] } },

        { 'name' => 'spell_attack',
          'ability' => ->(_char, caster) { caster['spell_abil'] },
          'base' => ->(char, caster) { Pf2e.get_prof_bonus(char, caster['prof_level']) },
          'intrinsic' => ->(char, caster) { [ ability_mod(char, caster['spell_abil']) ] } },

        { 'name' => 'class_dc',
          'ability' => ->(char, _name) { char.combat&.key_abil || 'Strength' },
          'base' => ->(char, _name) { 10 + Pf2e.get_prof_bonus(char, char.combat&.class_dc) },
          'intrinsic' => ->(char, _name) {
            [ ability_mod(char, char.combat&.key_abil || 'Strength') ]
          } }
      ].freeze

      BY_KIND = KINDS.each_with_object({}) { |row, out| out[row['name']] = row }.freeze

      # `options` are the circumstances a predicate is tested against beyond what is true of the
      # character anyway - what the player said they are doing. A roll supplies them; a sheet does not,
      # which is why a sheet reports a conditional bonus rather than counting it.
      #
      # `extra` are domains this reading of the figure also answers to. Initiative is a Perception check
      # that also answers to `initiative`, which is how Foundry composes it: the base statistic's
      # domains plus its own.
      def self.of(char, kind, name = nil, options = [], extra = [])
        row = BY_KIND[kind.to_s]

        raise ArgumentError, "no such kind of statistic: #{kind.inspect}" unless row

        ability = row['ability'].call(char, name)
        named = row['domain_name'] ? row['domain_name'].call(name) : name
        domains = Domains.for(kind, named, ability) + Array(extra)

        effects = Effects.modifiers(Effects.sources(char), domains, Effects.context(char),
                                    Effects.options(char) + Array(options))
        met, unmet = effects.partition { |effect| effect['met'] }

        # An unmet row is kept out of the stacking, so it cannot override one that applies, but it is
        # still reported: "+2, but only while picking a lock" is what a player wants to know.
        Modifiers.breakdown(row['base'].call(char, name).to_i,
                            row['intrinsic'].call(char, name).compact + met)
                 .merge('conditional' => unmet)
      end

      def self.total(char, kind, name = nil, options = [], extra = [])
        of(char, kind, name, options, extra)['total']
      end

      # What a player means by a figure's name. Tried in order, so `fort` reaches the save rather than
      # a skill, and anything the catalogue does not hold is a lore - which is what a lore is.
      NAMED = [
        { 'match' => ->(term) { %w{hp hitpoints health}.include?(term) },
          'stat' => ->(_term) { [ 'hp', nil ] } },
        { 'match' => ->(term) { %w{ac armor armour}.include?(term) },
          'stat' => ->(_term) { [ 'ac', nil ] } },
        { 'match' => ->(term) { term == 'speed' },
          'stat' => ->(_term) { [ 'speed', nil ] } },
        { 'match' => ->(term) { %w{perception per}.include?(term) },
          'stat' => ->(_term) { [ 'perception', nil ] } },
        { 'match' => ->(term) { Pf2e::SAVES.include?(term) },
          'stat' => ->(term) { [ 'save', term ] } },
        { 'match' => ->(term) { [ 'class dc', 'classdc', 'class' ].include?(term) },
          'stat' => ->(_term) { [ 'class_dc', nil ] } },
        # Before skills, because most of the catalogue is lores and a lore wants the domain that
        # reaches every lore at once.
        { 'match' => ->(term) { Pf2eSkills.lore?(term) },
          'stat' => ->(term) { [ 'lore', skill_named(term) || titleize(term) ] } },
        { 'match' => ->(term) { skill_named(term) },
          'stat' => ->(term) { [ 'skill', skill_named(term) ] } }
      ].freeze

      def self.identify(term)
        wanted = term.to_s.strip.downcase

        row = NAMED.find { |candidate| candidate['match'].call(wanted) }

        row && row['stat'].call(wanted)
      end

      def self.titleize(term)
        term.to_s.split.map(&:capitalize).join(' ')
      end

      def self.skill_named(term)
        Global.read_config('pf2e_skills').keys.find { |name| name.casecmp?(term) }
      end

      # An attribute's contribution is typed `ability`, so the best one applies and no two stack. That
      # is what lets an effect offer a different attribute for a figure without anything special-casing
      # which attribute the figure "really" uses.
      #
      # Foundry slugs an attribute modifier with the attribute's short name (`modifiers.ts`), which is
      # what a rule adjusting one names, so ours are slugged the same way.
      def self.ability_mod(char, ability, source = nil)
        return nil unless ability

        { 'source' => source || ability, 'slug' => Domains.abbreviation(ability),
          'type' => Modifiers::ABILITY, 'value' => Pf2e.ability_mod(char, ability) }
      end

      def self.attack_abilities(attack)
        return [ 'Dexterity' ] if attack['ranged']

        Pf2e.has_trait?(attack['traits'], 'finesse') ? [ 'Strength', 'Dexterity' ] : [ 'Strength' ]
      end

      def self.item(value, source, slug = nil)
        return nil if value.to_i.zero?

        { 'source' => source, 'slug' => slug || Domains.slug(source), 'type' => 'item',
          'value' => value.to_i }
      end

      # Their slug, because a feat that lets a character ignore armour's speed penalty names it
      # (`character/document.ts:933`).
      def self.armor_penalty(char)
        armor = Pf2eCombat.get_equipped_armor(char)
        penalty = armor ? armor.speed_penalty.to_i : 0

        return nil if penalty.zero?

        { 'source' => armor.name, 'slug' => 'armor-speed-penalty', 'type' => Modifiers::UNTYPED,
          'value' => penalty }
      end

      # This game's armour carries `potency` for AC and `power` for saves. The save rune is what the
      # rules call resilient, and `resilient` is the slug their data adjusts.
      RUNE_SLUGS = { 'potency' => 'armor-potency', 'power' => 'resilient' }.freeze

      def self.rune(char, subtype)
        item(Pf2egear.get_rune_value(Pf2eCombat.get_equipped_armor(char), 'fundamental', subtype),
             "#{subtype} rune", RUNE_SLUGS[subtype])
      end
    end
  end
end
