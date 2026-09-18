module AresMUSH
  module Pf2e

    # The rule elements we implement, spelled the way Foundry spells them.
    #
    # A feat, an item or a condition carries a `rules:` list, and each row is a rule element: a `key`
    # naming what kind it is, a `selector` naming the domains it reaches, a `value`, and a `predicate`
    # saying when it applies. Those are Foundry's own field names, so a row lifted out of their packs
    # is copied rather than translated - which is the point, since their system is the reference
    # implementation of this game's mechanics and a translation is a place to introduce an error.
    #
    #   rules:
    #     - key: FlatModifier
    #       selector: hp
    #       value: "@actor.level"                # Toughness
    #     - key: FlatModifier
    #       selector: [ cha-based, int-based, wis-based ]
    #       type: status
    #       value: "-@item.badge.value"          # Stupefied, scaled by the condition's own value
    #     - key: DamageDice
    #       selector: strike-damage
    #       diceNumber: 1
    #       dieSize: d6
    #       damageType: fire
    #
    # Foundry ships 42 kinds. A row whose kind is not in the table below is refused rather than
    # ignored: an effect nobody applies is a sheet that is quietly wrong, and the import that wrote
    # these rows refuses the same kinds for the same reason.
    module Rules

      # A row's `slug` is the name other rules call it by: `AdjustModifier` names the modifier it
      # changes, and their data names ours as well as its own - `resilient`, `armor-check-penalty`,
      # `weapon-potency`. A row that does not say is slugged from whatever carries it.
      #
      # `value` and `diceNumber` are read by `Pf2e::Formula`, `predicate` by `Pf2e::Predicate`. Every
      # other field is taken as it stands.
      FORMULA_FIELDS = %w{value diceNumber}.freeze

      KINDS = [
        {
          'key' => 'FlatModifier',
          'fields' => %w{key selector value type ability min max damageType damageCategory critical
                         predicate slug label hideIfDisabled},
          # A number added to whatever the selector reaches, obeying the stacking rule for its type.
          #
          # `min` and `max` clamp it, which is how a bonus that scales with something says how far it
          # goes. `damageType` makes it a bonus to one kind of damage rather than to the whole roll.
          'contribute' => lambda { |row, source, context|
            { 'source' => row['ability'] ? row['ability'].to_s.capitalize : source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'type' => (row['type'] || Modifiers::UNTYPED).to_s.downcase,
              'value' => clamp(Formula.value(row['value'], context), row),
              'damage_type' => row['damageType'],
              'category' => row['damageCategory'],
              'critical' => row['critical'] }
          }
        },
        {
          'key' => 'DamageDice',
          'fields' => %w{key selector diceNumber dieSize damageType category critical predicate slug
                         label hideIfDisabled override tags},
          # Dice added to a damage roll. `category` separates persistent, precision and splash damage,
          # which are rolled and applied apart from the rest.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'dice' => Formula.value(row['diceNumber'] || 1, context),
              'die' => row['dieSize'],
              'damage_type' => row['damageType'],
              'category' => row['category'],
              'critical' => row['critical'] }
          }
        },
        {
          'key' => 'RollOption',
          'fields' => %w{key option domain toggleable value predicate label slug suboptions selection
                         alwaysActive disabledIf disabledValue},
          # Declares a circumstance rather than a number. A rule on the same feat or item is then
          # predicated on it - a Clandestine Cloak declares `clandestine-cloak` and predicates its own
          # bonuses on it - so this contributes an option, not a modifier.
          #
          # `value` decides whether it holds without being asked for. Foundry defaults a toggleable one
          # to off and everything else to on; here an option a character has is on unless they turn it
          # off, because an item you are wearing should do what it says.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'option' => row['option'],
              'domain' => row['domain'] || Domains::ALL,
              'label' => row['label'],
              # A choice among values: a wand set to fire, a gem twisted to frost. Rules are predicated
              # on `<option>:<value>`, so the option holds twice - once bare and once with the choice.
              'choices' => choices_of(row),
              'selection' => row['selection'],
              # A toggle something else locks. While `locked_when` holds, the option reads as
              # `locked_to` whatever the player said - a stance you cannot leave, a rune you cannot turn off.
              'locked_when' => row['disabledIf'],
              'locked_to' => row['disabledValue'],
              'default' => truthy(row['value'], context) }
          }
        },
        {
          'key' => 'ActiveEffectLike',
          'fields' => %w{key path mode value predicate slug label priority phase merge},
          # Writes a value rather than adding a modifier: a feat that makes you trained in a skill, a
          # counter another rule's predicate asks about. `Pf2e::Paths` says which paths may be written
          # and what each mode does; a path it does not know is refused there.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'path' => row['path'],
              'mode' => row['mode'].to_s,
              'value' => writable_value(row['value'], context) }
          }
        },
        {
          'key' => 'MartialProficiency',
          'fields' => %w{key slug definition sameAs maxRank label},
          # "Your proficiency with weapons like this is the same as your <sameAs> proficiency." Goblin
          # Weapon Familiarity makes martial goblin weapons count as simple; Monastic Weaponry makes monk
          # weapons count as your unarmed proficiency, up to master.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'definition' => row['definition'],
              'same_as' => Domains.slug(row['sameAs']),
              'max_rank' => row['maxRank'] }
          }
        },
        {
          'key' => 'CriticalSpecialization',
          'fields' => %w{key predicate slug label},
          # Grants the critical specialisation effect for the attacks its predicate describes. It carries
          # no value: whether it applies is the whole of it.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'definition' => row['predicate'] }
          }
        },
        {
          'key' => 'Sense',
          'fields' => %w{key selector acuity range predicate slug label},
          # A sense the character would not otherwise have: darkvision from a blindfold, low-light vision
          # from a cat's eyes. Not a figure, but a fact the sheet shows and a predicate can ask about.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'sense' => Domains.slug(row['selector']),
              'acuity' => row['acuity'],
              'range' => row['range'] }
          }
        },
        {
          'key' => 'DamageAlteration',
          'fields' => %w{key property mode value selectors selector predicate slug label},
          # Changes a damage roll after it is built rather than adding to it: the kind of damage it
          # deals, how many dice, or how large they are.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'property' => Domains.slug(row['property']),
              'mode' => row['mode'].to_s,
              'value' => alteration_value(row['value'], context) }
          }
        },
        {
          'key' => 'Strike',
          'fields' => %w{key slug label category group baseType damage traits otherTags range
                         predicate img fist},
          # An attack the character would not otherwise have: a shield's lion head, a torch swung as a
          # club, the claws a stance grants. It becomes an unarmed-style attack, described the same way
          # a catalogue weapon is, so everything that reads an attack reads this one too.
          'contribute' => lambda { |row, source, _context|
            base = (row['damage'] || {})['base'] || {}

            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(row['label'] || source['name']),
              'name' => row['label'] || source['name'],
              'category' => row['category'],
              'group' => row['group'],
              'base' => row['baseType'] || Domains.slug(row['label'] || source['name']),
              'traits' => Array(row['traits']),
              'dice' => base['dice'] || 1,
              'die' => base['die'],
              'damage_type' => base['damageType'],
              'range' => row['range'] }
          }
        },
        {
          'key' => 'AdjustStrike',
          'fields' => %w{key property mode value definition predicate slug label},
          # Changes an attack rather than the roll: adds a trait to it. A trait is not decoration - a
          # weapon that gains `finesse` may be attacked with Dexterity and one that gains `thrown` adds
          # Strength to its damage - so the trait is what this reads and the other properties it can
          # change are refused at import.
          #
          # `definition` says which attack, tested against that attack's own options rather than the
          # character's.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'property' => Domains.slug(row['property']),
              'mode' => row['mode'].to_s,
              'trait' => Domains.slug(row['value']),
              'definition' => row['definition'] }
          }
        },
        {
          'key' => 'BaseSpeed',
          'fields' => %w{key selector value predicate slug label},
          # A speed of a kind the character would not otherwise have, or a better one: a Ring of
          # Swimming gives a swim speed of half their land speed. `selector` is the kind of movement,
          # and the highest candidate is the one that counts.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'movement' => Domains.slug(row['selector']),
              'value' => Formula.value(row['value'], context) }
          }
        },
        {
          'key' => 'AdjustModifier',
          'fields' => %w{key selector selectors slug mode value suppress relabel damageType
                         maxApplications predicate label priority},
          # Changes a modifier that already exists rather than adding one: Intimidating Prowess raises
          # the Strength modifier on Intimidation, and a feat that says you need no crowbar suppresses
          # the penalty for not having one.
          #
          # A row with no slug adjusts *every* modifier the selector reaches
          # (`rules/helpers.ts:47`), which is why the slug is carried as nil rather than defaulted.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'],
              'mode' => (row['suppress'] ? 'override' : row['mode']).to_s,
              'value' => row['value'] ? Formula.value(row['value'], context) : nil,
              'suppress' => !!row['suppress'],
              'relabel' => row['relabel'],
              'max' => row['maxApplications'] }
          }
        },
        {
          'key' => 'AdjustDegreeOfSuccess',
          'fields' => %w{key selector adjustment predicate type slug label},
          # Turns one outcome into another: Assurance makes a failure a success, Deafened drops an
          # auditory Perception check to a critical failure. `Pf2e::Degree` applies it.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'adjustment' => row['adjustment'],
              'check' => row['type'] }
          }
        },
        {
          'key' => 'Immunity',
          'fields' => %w{key type value predicate label definition exceptions},
          'contribute' => lambda { |row, source, context| declaration_of(row, source, context) }
        },
        {
          'key' => 'Weakness',
          'fields' => %w{key type value predicate label definition exceptions},
          'contribute' => lambda { |row, source, context| declaration_of(row, source, context) }
        },
        {
          'key' => 'Resistance',
          'fields' => %w{key type value predicate label definition exceptions doubleVs},
          'contribute' => lambda { |row, source, context| declaration_of(row, source, context) }
        }
      ].freeze

      # Fields that position a toggle in Foundry's character sheet. They are neither read nor complained
      # about: a field we ignore that changes the mechanics is a sheet that is quietly wrong, and one
      # that describes where a control sits in an interface we do not have is neither.
      # `placement` and `mergeable` position a toggle in Foundry's character sheet. `phase` and `priority`
      # order a rule against their data-preparation passes, which have no counterpart here: ours are
      # ordered by mode where order matters and by when they are asked for otherwise.
      PRESENTATION = { 'RollOption' => %w{placement mergeable phase priority},
                       'ActiveEffectLike' => %w{phase priority},
                       'AdjustModifier' => %w{priority},
                       'FlatModifier' => %w{priority},
                       'DamageDice' => %w{priority},
                       'AdjustStrike' => %w{priority},
                       'DamageAlteration' => %w{priority} }.freeze

      BY_KEY = KINDS.each_with_object({}) { |row, out| out[row['key']] = row }.freeze

      # A RollOption's `value` is a boolean or a formula, not a number: `true` and `false` mean what they
      # say, and anything else is read as arithmetic and true when it comes to something other than zero.
      # An option that says nothing is on, which is this game's default rather than Foundry's.
      # A written value may be a flag, a word or a number. Only a number goes through the formula reader;
      # anything else is what it says, since `override` writes words and flags as readily as numbers.
      def self.writable_value(value, context)
        return value unless value.is_a?(Numeric) || value.is_a?(String)
        return value unless value.is_a?(Numeric) || value.match?(/[\d@(]/)

        Formula.value(value, context)
      rescue StandardError
        value
      end

      # Only suboptions that say what they are. Their data has a few whose list is a string, which reads
      # as a list of single letters and means nothing.
      def self.choices_of(row)
        Array(row['suboptions']).select { |one| one.is_a?(Hash) && one['value'] }
                                .map { |one| { 'value' => one['value'].to_s, 'label' => one['label'] } }
      end

      def self.truthy(value, context)
        return true if value.nil?
        return value if value == true || value == false

        !Formula.value(value, context).to_i.zero?
      rescue StandardError
        false
      end

      def self.clamp(value, row)
        low = row['min'] ? Formula.value(row['min']) : nil
        high = row['max'] ? Formula.value(row['max']) : nil

        value = [ value, low ].max if low
        value = [ value, high ].min if high

        value
      end

      # An immunity, a weakness or a resistance: a kind of thing and, for the latter two, how much of it.
      def self.declaration_of(row, source, context)
        { 'source' => source['name'],
          'slug' => row['slug'] || Domains.slug(source['name']),
          'type' => row['type'],
          # A resistance may describe what it resists rather than naming a kind: Sacred Defender resists
          # physical damage from an unholy source. Tested against the damage's own facts.
          'definition' => row['definition'],
          'value' => row['value'] ? Formula.value(row['value'], context) : nil }
      end

      # Every declaration of a kind whose circumstances are met. Neither a modifier nor a write, so it
      # has no selector and no stacking: `Pf2e::IWR` decides which of them wins.
      def self.declarations(sources, options, key)
        return [] unless known?(key)

        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, key).select { |row| Predicate.test(row['predicate'], held) }
                             .map { |row| contribute(row, source, {}) }
                             .compact
        end
      end

      # Everything an effect writes, in the order the modes are meant to run: a multiply before an add,
      # and an override last, so an override wins whatever else said (`ae-like.ts`).
      MODE_ORDER = %w{multiply add subtract remove downgrade upgrade override}.freeze

      def self.writes(sources, options)
        gathered = Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, 'ActiveEffectLike')
            .select { |row| Predicate.test(row['predicate'], held) }
            .map { |row| contribute(row, source, {}) }
            .compact
        end

        gathered.select { |write| Paths.writable?(write['path']) }
                .sort_by { |write| MODE_ORDER.index(write['mode']) || MODE_ORDER.size }
      end

      # Rules that change how a check turned out. A row may restrict itself to a kind of check - a save
      # or a skill - which the check itself declares as `check:type:…`, so the restriction is read the
      # same way any other circumstance is.
      CHECK_TYPES = { 'save' => 'saving-throw', 'skill' => 'skill', 'perception' => 'perception',
                      'attack' => 'attack-roll' }.freeze

      def self.adjustments(sources, domains, options)
        gather(sources, domains, options, 'AdjustDegreeOfSuccess') do |row|
          wanted = CHECK_TYPES[row['type'].to_s] || row['type']

          next nil if row['type'] && !Array(options).include?("check:type:#{wanted}")

          row['adjustment']
        end
      end

      # A value on a damage alteration is a kind of damage, a number, or nothing at all - `dice-faces`
      # with no value means "one step larger".
      def self.alteration_value(value, context)
        return nil if value.nil?
        return value unless value.is_a?(Numeric) || value.to_s.match?(/\A[-\d@(]/)

        Formula.value(value, context)
      rescue StandardError
        value
      end

      # Proficiencies a feat gives over a kind of weapon, each capped where it says.
      def self.martial_proficiencies(sources, options)
        declarations(sources, options, 'MartialProficiency')
      end

      # Whether anything grants the critical specialisation effect for an attack.
      #
      # The predicate is about the weapon as much as the character - "monk weapons, if you have Expert
      # Strikes" - so it is tested once against both sets of facts rather than filtered against the
      # character's first.
      def self.critical_specialization?(sources, options, attack_options)
        Array(sources).any? do |source|
          held = Array(options) + Array(source['options']) + Array(attack_options)

          of_kind(source, 'CriticalSpecialization').any? { |row| Predicate.test(row['predicate'], held) }
        end
      end

      def self.senses(sources, options)
        declarations(sources, options, 'Sense')
      end

      # Alterations to a damage roll that reaches these domains.
      def self.damage_alterations(sources, domains, options, context = {})
        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, 'DamageAlteration')
            .select { |row| Domains.matches?(selectors_of(row), domains) }
            .select { |row| Predicate.test(row['predicate'], held) }
            .map { |row| contribute(row, source, context) }
            .compact
        end
      end

      # Attacks something granted the character. Each is described the way a catalogue weapon is, so
      # nothing that reads an attack has to know it came from a rule.
      def self.strikes(sources, options)
        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, 'Strike').select { |row| Predicate.test(row['predicate'], held) }
                                   .map { |row| contribute(row, source, {}) }
                                   .compact
        end
      end

      # Traits an effect adds to an attack. `definition` is a predicate over the attack's own options, so a
      # rune reaches the weapon it is on and a feat reaches every weapon of a base type.
      TRAIT_PROPERTIES = %w{traits weapon-traits}.freeze

      def self.strike_traits(sources, options, attack_options)
        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, 'AdjustStrike')
            .select { |row| Predicate.test(row['predicate'], held) }
            .map { |row| contribute(row, source, {}) }
            .compact
            .select { |one| TRAIT_PROPERTIES.include?(one['property']) && one['mode'] == 'add' }
            .select { |one| Predicate.test(one['definition'], attack_options) }
            .map { |one| one['trait'] }
        end.uniq
      end

      # Speeds a character has because something gave them one, by kind of movement. The highest for a
      # kind wins, which is Foundry's own rule (`creature/document.ts` `selectCandidate`) - two rings
      # that both grant a swim speed are the better swim speed, not the sum.
      def self.speeds(sources, options, context = {})
        gathered = Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, 'BaseSpeed').select { |row| Predicate.test(row['predicate'], held) }
                                      .map { |row| contribute(row, source, context) }
                                      .compact
        end

        gathered.group_by { |one| one['movement'] }
                .transform_values { |ones| ones.max_by { |one| one['value'].to_i } }
      end

      # Rules that change a modifier that already exists. A row naming several selectors reaches a
      # statistic answering to any of them, which is why `selectors` is read alongside `selector`.
      def self.modifier_adjustments(sources, domains, options, context = {})
        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, 'AdjustModifier')
            .select { |row| Domains.matches?(selectors_of(row), domains) }
            .map { |row| contribute(row, source, context)&.merge('when' => row['predicate'],
                                                                 'held' => held) }
            .compact
        end
      end

      def self.selectors_of(row)
        Array(row['selector']) + Array(row['selectors'])
      end

      # Text shown with a roll. `Note` is likewise not implemented yet.
      def self.notes(sources, domains, options)
        gather(sources, domains, options, 'Note') { |row| row['text'] }
      end

      # Every row of a kind that reaches these domains and whose circumstances are met, as whatever the
      # block makes of it. The kinds above are read here rather than through `Effects.rows_of` because
      # they contribute neither a modifier nor dice: there is nothing to stack.
      def self.gather(sources, domains, options, key)
        return [] unless known?(key)

        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, key).select { |row| Domains.matches?(selectors_of(row), domains) }
                              .select { |row| Predicate.test(row['predicate'], held) }
                              .map { |row| yield(row) }
                              .compact
        end
      end

      def self.known?(key)
        BY_KEY.key?(key.to_s)
      end

      # Every row of a kind across every source, whether or not its circumstances are met. For the one
      # case that needs the unconditional list: a sense's own predicate is tested against the character's
      # facts, and the senses are among those facts.
      def self.of_kind_across(sources, key)
        Array(sources).flat_map { |source| of_kind(source, key) }
      end

      # The rows of one kind that a source carries, whatever else it carries.
      def self.of_kind(source, key)
        Array(source['rules']).select { |row| row['key'].to_s == key.to_s }
      end

      # What this row is worth, or nil when its kind is one we do not implement.
      def self.contribute(row, source, context)
        kind = BY_KEY[row['key'].to_s]

        return nil unless kind

        kind['contribute'].call(row, source, context)
      end

      # A field nobody reads is a rule that silently does something other than what it says, so it is
      # reported. Checked against the kind's own field list rather than one list for all of them,
      # because `dieSize` means nothing on a FlatModifier.
      def self.complain(name, row)
        kind = BY_KEY[row['key'].to_s]

        unless kind
          Global.logger.warn "PF2e rule on #{name.inspect} is a #{row['key'].inspect}, which nothing applies."
          return
        end

        strays = row.keys.map(&:to_s) - kind['fields'] -
                 Array(PRESENTATION[row['key'].to_s])

        return if strays.empty?

        Global.logger.warn "PF2e #{row['key']} on #{name.inspect} has fields nothing reads: #{strays.join(', ')}."
      end
    end
  end
end
