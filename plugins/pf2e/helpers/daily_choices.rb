module AresMUSH
  module Pf2e

    # Choices the character makes during their daily preparations, other than spells: a skill Ancestral
    # Longevity trains them in, the sword an egalrin practices with, the fighter feat Combat Flexibility
    # lends them for the day. A feat declares one in config, or a class does for its class features
    # (whose own config is generated), each with the `prepare` switch the player makes it with:
    #
    #   daily_choice:
    #     switch: longevity          # prepare/longevity <skill>
    #     pick: skill                # what is picked: a row of KINDS
    #     trains: true               # a skill pick makes them temporarily trained in it
    #     lasts: day                 # day: a rest clears it. until_changed: it holds until a new pick.
    #
    #   daily_choice:
    #     switch: swordpractice
    #     pick: weapon
    #     group: sword               # only weapons of this group they have with them
    #     familiarity: true          # a weapon pick counts one category simpler for proficiency
    #     lasts: until_changed
    #
    #   daily_choice:                # a class's blocks are a list
    #     - switch: improvedflexibility
    #       pick: feat
    #       feature: Improved Flexibility         # only while they hold this class feature
    #       from_feats: { ..., max_level: 14 }    # the pool, as a feat_choice's `from_feats`
    #       also_counts: [ flexibility ]          # today's pick there counts towards prerequisites here
    #       lasts: day
    #
    #   daily_choice:
    #     switch: cauldron
    #     pick: formula              # a formula they know, brewed as a batch for the day
    #     formulas: { category: consumables, traits: [ oil, potion ] }
    #     brews: { trained: 1, master: 2, legendary: 3 }   # copies, by spell DC rank
    #     lasts: until_changed
    #
    #   daily_choice:
    #     switch: rootmagic
    #     pick: creature             # approved characters by name, or creatures in their encounter
    #     count: 1                   # a feat may raise it: daily_choice_count: { charge: { plus: Intelligence } }
    #     not_self: true
    #     gives: "Effect: Root Magic"         # put on each named creature where they stand in an encounter
    #     limits_action: Inspired Stratagem   # an action that reaches only them, each once a day
    #     lasts: day
    #
    # A block may also say `subclass:` (an alchemist's research field), `subclass_option:` (a wizard's thesis)
    # or `min_level:`. A class's block gated by
    # `feature:` is open to anyone holding that feature, whatever their class. A feat may say
    # `daily_reprepare:`, the switches `encounter/reprepare` opens again (Ultimate Flexibility's hour of
    # training, Radiant Armament's ten minutes to change the rune).
    #
    # A pick takes effect at once and is locked until the GM next rests the character, which unlocks it
    # for a new one. It is daily state rather than sheet history, so it is held on the character in
    # `pf2_daily_choices` and never written to the ledger:
    #
    #   { switch => { 'pick' =>, 'choice' =>, 'source' =>, 'locked' =>, 'previous' => } }
    #
    # `choice` is what a picked feat's own choice was answered with (Advanced Weapon Training's group).
    # `previous` is a pick still in force from an earlier day that a new one replaced, which taking the
    # new one back puts back.
    #
    # What a pick gives is read only where the game is played: checks, rolls, rules and actions. A
    # temporary rank or feat never counts as a prerequisite or towards a skill increase, because the
    # sources all say it can't.
    module DailyChoices

      LASTS = %w{day until_changed}.freeze

      # What each kind of pick offers a character, and, for a feat, what its own choice was answered with.
      KINDS = {
        'skill' => {
          'options' => lambda { |char, _block|
            (Global.read_config('pf2e_skills') || {}).keys.map(&:to_s)
              .reject { |name| Pf2eSkills.lore?(name) }
              .select { |name| Pf2eSkills.get_skill_prof(char, name).to_s.casecmp?('untrained') }
              .sort
          }
        },
        'weapon' => {
          'options' => lambda { |char, block|
            Pf2egear::Inventory.all(char, 'weapons').map { |item| item.name.to_s }.uniq.select do |name|
              group = (Pf2eCombat.weapon_info(name) || {})['group']

              block['group'].blank? || Domains.slug(group) == Domains.slug(block['group'])
            end.sort
          }
        },
        'feat' => {
          'options' => lambda { |char, block| DailyChoices.feat_pool(char, block) },
          'detail' => lambda { |char, _block, feat, said| DailyChoices.feat_choice(char, feat, said) }
        },
        # One of a fixed list, which may make something true of them: Nudge the Scales' death side gives
        # void healing (`facts: { death: [ self:void-healing ] }`).
        'listed' => {
          'options' => lambda { |_char, block| Array(block['choices']).map(&:to_s) }
        },
        # Something they carry, picked by what it is: a polearm, or anything named a broom or a staff
        # (`items: { weapon_groups: [ polearm ], name_includes: [ broom ] }`).
        'item' => {
          'options' => lambda { |char, block| DailyChoices.carried_matching(char, block['items'] || {}) }
        },
        # An effect for the day, its questions answered by the pick in order, each after a colon:
        # Blessed Armament's `<weapon>: <rune>`. The effect's own rules then apply, as one the character
        # is under would.
        'effect' => {
          'options' => lambda { |char, block| DailyChoices.effect_offer(char, block) },
          'resolve' => lambda { |char, block, typed| DailyChoices.effect_answers(char, block, typed) }
        },
        # A formula they know, which the day's preparations brew a batch of: Cauldron's oil or potion
        # (`formulas: { category:, traits: }`, no higher than their level). `brews:` says how many copies,
        # by spell DC rank.
        'formula' => {
          'options' => lambda { |char, block| DailyChoices.known_formulas(char, block['formulas'] || {}) }
        },
        # Creatures they designate for the day, named with commas: approved characters by name, or a
        # creature in their encounter by its label there. `count` caps how many, `not_self` refuses
        # themselves, `gives:` puts an effect on each where they stand in an encounter, and
        # `limits_action:` lets an action reach only them.
        'creature' => {
          'options' => lambda { |char, block| DailyChoices.creature_offer(char, block) },
          'resolve' => lambda { |char, block, typed| DailyChoices.creature_answers(char, block, typed) }
        }
      }.freeze

      # A source's blocks: one, or a class's list.
      def self.blocks_of(info)
        return [] unless info.is_a?(Hash)

        found = info['daily_choice']

        return [ found ] if found.is_a?(Hash)

        Array(found).select { |one| one.is_a?(Hash) }
      end

      # Whether any feat or class declares this switch, for routing `prepare/<switch>`.
      def self.switch?(switch)
        return false if switch.blank?

        declared.any? { |_source, block| block['switch'].to_s.casecmp?(switch.to_s) }
      end

      # Every block in config, with the feat or class declaring it: [ [ source, block ] ].
      def self.declared
        [ 'pf2e_feats', 'pf2e_class' ].flat_map do |section|
          (Global.read_config(section) || {}).flat_map do |name, info|
            blocks_of(info).map { |block| [ name, block ] }
          end
        end
      end

      # The daily choices open to the character: { switch => block, with 'source' }. Their feats' blocks,
      # and their class's blocks for the features and thesis they hold.
      def self.held(char)
        SheetReads.memo(char, :daily_choices_held) do
          feats = (char.pf2_feats || {}).values.flatten.map(&:to_s).uniq.flat_map do |name|
            blocks_of(Global.read_config('pf2e_feats', name)).map { |block| [ name, block ] }
          end

          # Their own class's blocks, and another class's that a feature they hold opens: the Champion
          # archetype's Devout Blessing can give Blessed Armament.
          charclass = (char.pf2_base_info || {})['charclass'].to_s
          klass = (Global.read_config('pf2e_class') || {}).flat_map do |name, info|
            blocks_of(info).select { |block| name.to_s == charclass || block['feature'] }
                           .map { |block| [ block['feature'] || block['subclass_option'] || name, block ] }
          end

          (feats + klass).each_with_object({}) do |(source, block), out|
            next unless open_to?(char, block)

            out[block['switch'].to_s.downcase] = block.merge('source' => source)
          end
        end
      end

      def self.open_to?(char, block)
        return false if block['min_level'] && char.pf2_level.to_i < block['min_level'].to_i

        return false if block['feature'] && !Pf2e.holds_feature?(char, block['feature'])
        return false if block['subclass'] && !((char.pf2_base_info || {})['specialize']).to_s.casecmp?(block['subclass'].to_s)

        return true unless block['subclass_option']

        ((char.pf2_base_info || {})['specialize_info']).to_s.casecmp?(block['subclass_option'].to_s)
      end

      def self.for_switch(char, switch)
        held(char)[switch.to_s.downcase]
      end

      def self.picks(char)
        char.respond_to?(:pf2_daily_choices) ? (char.pf2_daily_choices || {}) : {}
      end

      # The picks whose source the character still holds, each with its block: { switch => [ pick, block ] }.
      def self.in_force(char)
        SheetReads.memo(char, :daily_choices_in_force) do
          current = picks(char)
          # A creature holds no picks, and has no feats to ask about.
          blocks = current.empty? ? {} : held(char)

          current.each_with_object({}) do |(switch, pick), out|
            block = blocks[switch.to_s]
            out[switch.to_s] = [ pick, block ] if block && pick.is_a?(Hash) && pick['pick']
          end
        end
      end

      def self.options(char, block)
        kind = KINDS[block['pick'].to_s]

        kind ? kind['options'].call(char, block) : []
      end

      # ------------------------------------------------------------------------------
      # Feats for the day

      # The feats a feat pick may take: the block's pool, less the feats picked today by their other
      # switches. Today's picks named by `also_counts` count towards the prerequisites, which is how
      # Improved Flexibility's second feat may build on the first.
      def self.feat_pool(char, block)
        today = in_force(char).reject { |switch, _| switch == block['switch'].to_s.downcase }
        counted = Array(block['also_counts']).filter_map { |switch| (today[switch.to_s.downcase] || []).first }
                                             .map { |pick| pick['pick'] }
        taken = today.values.select { |_pick, held| held['pick'].to_s == 'feat' }.map { |pick, _| pick['pick'].to_s.downcase }

        pool = DraftSheet.counting(counted) { Pf2e.choice_feat_pool(char, block['from_feats'] || {}) }

        pool.reject { |name| taken.include?(name.to_s.downcase) }
      end

      # What a picked feat's own choice was answered with, for a feat that asks one: Advanced Weapon
      # Training's weapon group, typed after a colon.
      def self.feat_choice(char, feat, said)
        details = Global.read_config('pf2e_feats', feat)
        block = Pf2e.feat_choice_def(details)

        return Ok.new(:state => {}) unless block

        offered = Pf2e.choice_options(char, feat, block)
        found = offered.find { |one| one.to_s.casecmp?(said.to_s.strip) }

        return Ok.new(:state => { 'choice' => found }) if found

        Err.new(:needs_choice, 'pf2e.daily_needs_choice', 'feat' => feat, 'summary' => Pf2e.choice_summary(block),
                'options' => offered.empty? ? '---' : offered.join(', '))
      end

      # The feats their picks lend them today: [ { 'feat', 'choice', 'source' } ].
      def self.feats(char)
        in_force(char).filter_map do |_switch, (pick, block)|
          next nil unless block['pick'].to_s == 'feat'

          { 'feat' => pick['pick'], 'choice' => pick['choice'], 'source' => block['source'] }
        end
      end

      def self.feat_names(char)
        feats(char).map { |one| one['feat'] }
      end

      # ------------------------------------------------------------------------------
      # Things they carry, and effects for the day

      def self.carried_matching(char, filter)
        groups = Array(filter['weapon_groups']).map { |one| Domains.slug(one) }
        words = Array(filter['name_includes']).map { |one| one.to_s.downcase }

        Pf2egear.carried_items(char).select { |category, item|
          name = item.name.to_s.downcase
          group = category == 'weapons' ? Domains.slug((Pf2eCombat.weapon_info(item.name) || {})['group']) : nil

          (group && groups.include?(group)) || words.any? { |word| name.include?(word) }
        }.map { |_category, item| item.name.to_s }.uniq.sort
      end

      # The questions an effect for the day asks, in the order a pick answers them.
      def self.effect_sets(block)
        name = block['effect'].to_s
        rules = Array(ActiveEffects.info(name)['rules'])

        Rules.choice_sets(Effects.source(name, rules)).select { |set| set['flag'] }
      end

      # What each question would take now, as the player types it.
      def self.effect_names(set, char, offered)
        return Choices.owned_names(set, char, offered.map(&:to_s)) + (offered.include?('unarmed') ? [ 'unarmed' ] : []) if
          set['owned']

        Array(set['choices']).select { |one| offered.map(&:to_s).include?(one['value'].to_s) }
                             .map { |one| (one['label'] || one['value']).to_s }
      end

      def self.effect_offer(char, block)
        effect_sets(block).map do |set|
          names = effect_names(set, char, Choices.offer(set, char))

          "#{set['flag'].to_s.capitalize}: #{names.empty? ? '---' : names.join(', ')}"
        end
      end

      # The pick's answers, each checked against what its question would take now. Recorded as the answers
      # the effect's rules read - a weapon by its id - and as the words a player would read back.
      def self.effect_answers(char, block, typed)
        said = typed.to_s.split(':').map(&:strip)
        sets = effect_sets(block)
        form = sets.map { |set| "<#{set['flag']}>" }.join(': ')

        answers = []
        words = []

        sets.each_with_index do |set, index|
          offered = Choices.offer(set, char).map(&:to_s)
          given = said[index].to_s
          answer = set['owned'] ? Choices.owned_answer(set, char, given) : Choices.listed_answer(set, given)

          unless !given.empty? && answer && offered.include?(answer.to_s)
            names = effect_names(set, char, offered)

            return Err.new(:needs_answer, 'pf2e.daily_effect_answer', 'source' => block['source'], 'form' => form,
                           'question' => set['flag'].to_s, 'options' => names.empty? ? '---' : names.join(', '))
          end

          answers << answer.to_s
          words << (effect_names(set, char, [ answer.to_s ]).first || given)
        end

        Ok.new(:state => { 'pick' => words.join(': '), 'answers' => answers })
      end

      # The rules sources their effect picks bring today: each effect, with the pick's answers as its own.
      def self.sources(char)
        in_force(char).filter_map do |switch, (pick, block)|
          next nil unless block['pick'].to_s == 'effect'

          item = { 'id' => "daily-#{switch}", '_id' => "daily-#{switch}", 'level' => char.pf2_level.to_i }

          ActiveEffects.source_and_derived(char, block['effect'].to_s, item, Array(pick['answers']), 0)
        end.flatten
      end

      # What their listed picks make true of them today: Nudge the Scales' death side, void healing.
      def self.facts(char)
        in_force(char).flat_map do |_switch, (pick, block)|
          facts = block['facts'].is_a?(Hash) ? block['facts'] : {}
          key = facts.keys.find { |one| one.to_s.casecmp?(pick['pick'].to_s) }

          key ? Array(facts[key]).map(&:to_s) : []
        end
      end

      # The movement their picks give today, as movement entries: Witch's Broom's fly Speed.
      def self.movement(char)
        in_force(char).flat_map do |_switch, (pick, block)|
          Array(block['movement']).select { |entry| entry.is_a?(Hash) }
                                  .map { |entry| { 'source' => "#{block['source']} (#{label(pick)})" }.merge(entry) }
        end
      end

      # ------------------------------------------------------------------------------
      # Brewing a batch

      # The formulas they know in a category that carry one of the traits, no higher than their level.
      def self.known_formulas(char, filter)
        category = (filter['category'] || 'consumables').to_s
        traits = Crafting.words(filter['traits'])

        Array((char.pf2_formula_book || {})[category]).map(&:to_s).uniq.select { |name|
          info = Global.read_config("pf2e_#{category}", name)

          info.is_a?(Hash) && info['level'].to_i <= char.pf2_level.to_i &&
            (traits.empty? || (Crafting.words(info['traits']) & traits).any?)
        }.sort
      end

      RANKS = %w{untrained trained expert master legendary}.freeze

      # Their best spell DC rank, across every source they cast from.
      def self.spell_dc_rank(holder)
        ranks = Pf2emagic::Entries.for_magic(holder.magic).map { |entry| entry['proficiency'].to_s.downcase }

        ranks.max_by { |rank| RANKS.index(rank) || -1 } || 'untrained'
      end

      # How many copies a pick's batch is: the `brews:` count for the highest rank they reach, times what
      # their feats multiply it by (Double, Double's `daily_brew_copies: { cauldron: 2 }`).
      def self.batch_size(holder, switch, block)
        counts = block['brews'].is_a?(Hash) ? block['brews'] : {}
        rank = RANKS.index(spell_dc_rank(holder)).to_i
        reached = counts.select { |named, _many| RANKS.index(named.to_s).to_i <= rank }
                        .max_by { |named, _many| RANKS.index(named.to_s).to_i }
        many = reached ? reached.last.to_i : counts.values.map(&:to_i).min.to_i

        copies = (holder.pf2_feats || {}).values.flatten.map(&:to_s).uniq.map { |name|
          info = Global.read_config('pf2e_feats', name)
          found = info.is_a?(Hash) && info['daily_brew_copies'].is_a?(Hash) ? info['daily_brew_copies'] : {}

          (found.find { |key, _times| key.to_s.casecmp?(switch.to_s) } || [ nil, 1 ]).last.to_i
        }.max

        many * [ copies.to_i, 1 ].max
      end

      # What a pick under this switch made, which is how one batch is told from another.
      def self.brewed_by(switch)
        "daily:#{switch}"
      end

      # The day's batches, for someone as they stand in an encounter: what each formula pick made is taken
      # away and brewed again from the pick in force, so a changed pick replaces its batch. Only the
      # switches named, or all of them. Answers [ "2 Oil of Potency" ].
      def self.brew!(holder, only = nil)
        return [] unless Actors.of(holder).carries_items? && holder.respond_to?(:pf2_daily_choices)

        forces = in_force(holder)

        held(holder).select { |switch, block| block['pick'].to_s == 'formula' && (only.nil? || switch == only.to_s) }
                    .filter_map do |switch, block|
          category = Pf2egear::Inventory.canonical((block['formulas'] || {})['category'] || 'consumables')

          Pf2egear::Inventory.all(holder, category).select { |item| item.granted_by == brewed_by(switch) }.each(&:delete)

          pick = (forces[switch] || []).first

          next nil unless pick

          info = Global.read_config(Pf2egear::Inventory.config(category), pick['pick'].to_s)
          many = batch_size(holder, switch, block)

          next nil unless info.is_a?(Hash) && many.positive?

          Equipment.grant!(holder, category, pick['pick'].to_s, many, info, :granted_by => brewed_by(switch), :expires => 'rest')

          "#{many} #{pick['pick']}"
        end
      end

      # A pick made or taken back while they are in a running encounter brews there at once.
      def self.brew_where_standing!(char, switch)
        return [] unless char.is_a?(Character)

        PF2Encounter.running_for(char).to_a.filter_map { |encounter| CombatantStates.of(encounter, char) }
                    .flat_map { |state| brew!(state, switch) }
      end

      # ------------------------------------------------------------------------------
      # Creatures they designate

      # How many a creature pick may name: the block's `count`, or more where a feat raises it by switch
      # (Witch's Communion's `daily_choice_count: { charge: { plus: Intelligence } }`).
      def self.creature_count(char, switch, block)
        raised = (char.pf2_feats || {}).values.flatten.map(&:to_s).uniq.filter_map do |name|
          info = Global.read_config('pf2e_feats', name)
          found = info.is_a?(Hash) && info['daily_choice_count'].is_a?(Hash) ? info['daily_choice_count'] : {}
          spec = found.find { |key, _spec| key.to_s.casecmp?(switch.to_s) }

          spec ? Alchemy.count(char, spec.last) : nil
        end

        ([ Alchemy.count(char, block['count'] || 1) ] + raised).max
      end

      # Who they could name now: the approved characters where they are, and the creatures in their encounter.
      # A pick isn't limited to these, since a charge may be elsewhere.
      def self.creature_offer(char, block)
        here = char.respond_to?(:room) && char.room ? char.room.characters.to_a : []
        people = here.select { |one| one.is_approved? && !(block['not_self'] && one.id == char.id) }.map(&:name)

        encounter = char.is_a?(Character) ? Combatants.encounter_here(char) : nil
        creatures = encounter ? Combatants.all(encounter).select { |one| one.holder && Actors.of(one.holder).creature? }.map(&:label) : []

        (people.sort + creatures).uniq
      end

      # One name, as a character or as a creature in their encounter.
      def self.creature_named(char, block, name)
        found = ClassTargetFinder.find(name, Character, char)

        if found.found?
          who = found.target

          return Err.new(:self, 'pf2e.daily_not_self', 'source' => block['source']) if block['not_self'] && who.id == char.id
          return Err.new(:unapproved, 'pf2e.daily_unapproved', 'name' => who.name, 'source' => block['source']) unless who.is_approved?

          return Ok.new(:state => { 'name' => who.name })
        end

        encounter = Combatants.encounter_here(char)
        hit = encounter ? Combatants.find(encounter, name) : nil

        if hit&.ok? && hit.state.holder && Actors.of(hit.state.holder).creature?
          return Ok.new(:state => { 'creature' => hit.state.label, 'encounter' => encounter.id.to_s })
        end

        Err.new(:nobody, 'pf2e.daily_no_creature', 'name' => name, 'source' => block['source'])
      end

      def self.creature_answers(char, block, typed)
        said = typed.to_s.split(',').map(&:strip).reject(&:empty?)
        most = creature_count(char, block['switch'], block)

        return Err.new(:nobody, 'pf2e.daily_no_creature', 'name' => typed.to_s, 'source' => block['source']) if said.empty?

        found = said.map { |name| creature_named(char, block, name) }
        failed = found.find(&:err?)

        return failed if failed

        picked = found.map(&:state).uniq
        names = picked.filter_map { |one| one['name'] }
        creatures = picked.select { |one| one['creature'] }

        if picked.size > most
          return Err.new(:too_many, 'pf2e.daily_too_many', 'source' => block['source'], 'count' => most, 'named' => picked.size)
        end

        words = names + creatures.map { |one| one['creature'] }

        Ok.new(:state => { 'pick' => words.join(', '), 'names' => names, 'creatures' => creatures })
      end

      # Whether a creature pick names this holder: a character by name, or a creature by its label in its
      # encounter.
      def self.names?(pick, holder, encounter = nil)
        person = Actors.of(holder).person

        return Array(pick['names']).any? { |one| one.casecmp?(person.name) } if person

        Array(pick['creatures']).any? do |one|
          encounter && one['encounter'].to_s == encounter.id.to_s && Combatants.holder_named(encounter, one['creature'])&.id == holder.id
        end
      end

      # Whom a pick names, as they stand now: each named character in every running encounter they're in,
      # and each named creature in its encounter while that runs.
      def self.holders_named(pick)
        people = Array(pick['names']).flat_map do |name|
          who = Character.named(name)

          who ? PF2Encounter.running_for(who).to_a.filter_map { |encounter| CombatantStates.of(encounter, who) } : []
        end

        creatures = Array(pick['creatures']).filter_map do |one|
          encounter = PF2Encounter[one['encounter']]

          encounter&.is_active ? Combatants.holder_named(encounter, one['creature']) : nil
        end

        people + creatures
      end

      # What an effect a pick gives says it came from, which is how it is found to take back.
      def self.given_by(char, block)
        "#{char.name}'s #{block['source']}"
      end

      def self.give_to!(char, block, holder)
        name = block['gives'].to_s
        tag = given_by(char, block)

        return if ActiveEffects.on(holder).any? { |one| one.name == name && one.granted_by == tag }

        origin = ActiveEffects.origin(:by => char, :skills => ActiveEffects.reads_origin_skills?(name))
        encounter = holder.respond_to?(:encounter) ? holder.encounter : nil

        ActiveEffects.apply(holder, name, :applied_by => char.name, :granted_by => tag, :encounter => encounter, :origin => origin)
      end

      # A pick that gives an effect puts it on everyone it names who is in an encounter now, and remembers on
      # each named character who named them, for when they join one later.
      def self.give!(char, switch)
        block = for_switch(char, switch)
        pick = (in_force(char)[switch.to_s.downcase] || []).first

        return [] unless block && pick && block['gives']

        Array(pick['names']).each do |name|
          who = Character.named(name)
          next unless who

          who.update(:pf2_designated_by => (Array(who.pf2_designated_by) + [ char.id.to_s ]).uniq)
        end

        holders_named(pick).each { |holder| give_to!(char, block, holder) }
      end

      # What a pick gave, taken back from everyone it named.
      def self.take_back!(char, block, pick)
        return unless block && pick.is_a?(Hash) && block['gives']

        tag = given_by(char, block)

        holders_named(pick).each do |holder|
          ActiveEffects.on(holder).select { |one| one.name == block['gives'].to_s && one.granted_by == tag }
                       .each { |one| ActiveEffects.remove(holder, one) }
        end
      end

      # Someone joins an encounter fresh: whatever a designation of them gives today. Who named them is kept
      # on them as a hint, checked against the giver's picks, and a giver whose picks no longer name them is
      # dropped from it.
      def self.given_on_join!(state, char)
        return unless char.respond_to?(:pf2_designated_by)

        kept = Array(char.pf2_designated_by).select do |id|
          giver = Character[id]
          next false unless giver

          naming = in_force(giver).select do |_switch, (pick, block)|
            block['pick'].to_s == 'creature' && block['gives'] && Array(pick['names']).any? { |one| one.casecmp?(char.name) }
          end

          naming.each_value { |(_pick, block)| give_to!(giver, block, state) }
          naming.any?
        end

        char.update(:pf2_designated_by => kept) if kept.size != Array(char.pf2_designated_by).size
      end

      # An action a creature pick limits (`limits_action:`): Inspired Stratagem reaches only the allies they
      # reviewed stratagems with, each once until their next daily preparations.
      def self.limiting(holder, action)
        held(holder).find { |_switch, block| block['pick'].to_s == 'creature' && block['limits_action'].to_s.casecmp?(action.to_s) }
      end

      # Nil where the action may reach the target, or why not. A creature has no daily choices to limit it.
      def self.limit_refusal(holder, action, target, encounter)
        person = Actors.of(holder).person

        return nil unless person

        switch, block = limiting(person, action)

        return nil unless block

        pick = picks(person)[switch]

        return Err.new(:unpicked, 'pf2e.daily_limited_unpicked', 'source' => block['source'], 'switch' => switch) unless
          pick.is_a?(Hash) && pick['pick']
        return Err.new(:no_target, 'pf2e.daily_limited_no_target', 'action' => action) unless target && target.holder
        return Err.new(:not_named, 'pf2e.daily_limited_not_named', 'target' => target.label, 'source' => block['source']) unless
          names?(pick, target.holder, encounter)
        return Err.new(:immune, 'pf2e.daily_limited_immune', 'target' => target.label, 'action' => action) if
          TurnState.used(holder, immunity(action, target)).positive?

        nil
      end

      # Whom an action has reached since the last rest is kept with the actor's uses in the encounter, for
      # the rest to clear. A fresh join is rested, so it starts with none. Not on the character: the act
      # command writes the character it began with when it ends, which would put the picks back as they were.
      def self.immunity(action, target)
        "#{action}@#{target.label}"
      end

      # The action reached them, so they're immune to it until the actor's next rest.
      def self.limit_used!(holder, action, target)
        person = Actors.of(holder).person

        return unless person && target && limiting(person, action)

        uses = TurnState.of(holder)['uses'] || {}

        TurnState.write(holder, 'uses' => uses.merge(immunity(action, target) => { 'count' => 1, 'period' => 'rest' }))
      end

      # ------------------------------------------------------------------------------
      # Pure: what picking, taking back and resting do to the picks.

      def self.choose(picks, switch, block, options, typed, detail = {})
        current = picks[switch]

        if current.is_a?(Hash) && current['locked']
          return Err.new(:already_picked, 'pf2e.daily_already_picked', 'source' => block['source'], 'pick' => current['pick'])
        end

        found = Array(options).find { |one| one.to_s.casecmp?(typed.to_s.strip) }

        unless found
          return Err.new(:not_offered, 'pf2e.daily_not_offered', 'source' => block['source'], 'pick' => typed,
                         'options' => options.empty? ? '---' : options.join(', '))
        end

        made = { 'pick' => found, 'source' => block['source'], 'locked' => true }.merge(detail)
        made['previous'] = current['pick'] if current.is_a?(Hash) && current['pick'] && current['pick'] != found

        Ok.new(:state => picks.merge(switch => made))
      end

      # `needed_by` names the sources whose picks today count this one towards their prerequisites, which
      # keep it from being taken back from under them.
      def self.unchoose(picks, switch, block, needed_by = [])
        current = picks[switch]

        unless current.is_a?(Hash) && current['locked']
          return Err.new(:nothing_picked, 'pf2e.daily_nothing_picked', 'source' => block['source'])
        end

        if needed_by.any?
          return Err.new(:needed, 'pf2e.daily_needed', 'source' => block['source'], 'pick' => current['pick'],
                         'by' => needed_by.join(', '))
        end

        rest = picks.reject { |key, _| key == switch }

        return Ok.new(:state => rest) unless current['previous']

        Ok.new(:state => rest.merge(switch => { 'pick' => current['previous'], 'source' => current['source'],
                                                'locked' => false }))
      end

      # A rest unlocks every pick. A pick that lasts a day is cleared; one that holds until changed is kept
      # while it is still one the character could make, and dropped otherwise - a sword since sold. A pick
      # whose source has gone goes with it. Returns [ picks, dropped ], `dropped` being the picks lost that
      # were meant to hold.
      def self.rest(picks, blocks, still_offered)
        dropped = []

        kept = picks.each_with_object({}) do |(switch, pick), out|
          block = blocks[switch]

          next unless block && pick.is_a?(Hash) && pick['pick']
          next if block['lasts'].to_s != 'until_changed'

          unless still_offered.call(switch, pick['pick'])
            dropped << pick.merge('switch' => switch)
            next
          end

          out[switch] = { 'pick' => pick['pick'], 'source' => block['source'], 'locked' => false }
        end

        [ kept, dropped ]
      end

      # ------------------------------------------------------------------------------
      # Writing the picks.

      # `typed` is the pick, and for a feat that asks its own choice, the answer after a colon:
      # `Advanced Weapon Training: Sword`.
      def self.pick!(char, switch, typed)
        block = for_switch(char, switch)

        return Err.new(:not_held, 'pf2e.daily_not_held', 'switch' => switch) unless block

        key = switch.to_s.downcase
        kind = KINDS[block['pick'].to_s] || {}

        if kind['resolve']
          # A pick of several answers is checked whole, and is then the one thing on offer.
          detail = kind['resolve'].call(char, block, typed)

          return detail unless detail.ok?

          name = detail.state['pick']
          options = [ name ]
          detail = Ok.new(:state => detail.state.reject { |field, _| field == 'pick' })
        else
          name, said = kind['detail'] ? typed.to_s.split(':', 2).map(&:strip) : [ typed, nil ]
          options = options(char, block)
          found = options.find { |one| one.to_s.casecmp?(name.to_s) }

          detail = Ok.new(:state => {})
          detail = kind['detail'].call(char, block, found, said) if kind['detail'] && found

          return detail unless detail.ok?
        end

        outcome = choose(picks(char), key, block, options, name, detail.state)

        return outcome unless outcome.ok?

        char.update(:pf2_daily_choices => outcome.state)

        brewed = block['pick'].to_s == 'formula' ? brew_where_standing!(char, key) : []
        give!(char, key) if block['gives']

        Ok.new(:state => outcome.state[key].merge('brewed' => brewed))
      end

      def self.unpick!(char, switch)
        block = for_switch(char, switch)

        return Err.new(:not_held, 'pf2e.daily_not_held', 'switch' => switch) unless block

        key = switch.to_s.downcase
        current = picks(char)
        needed_by = held(char).select { |other, one|
          current[other] && Array(one['also_counts']).any? { |counted| counted.to_s.casecmp?(key) }
        }.values.map { |one| one['source'] }

        taken = current[key]
        outcome = unchoose(current, key, block, needed_by)

        return outcome unless outcome.ok?

        # What it gave the creatures it named goes with it.
        take_back!(char, block, taken)

        char.update(:pf2_daily_choices => outcome.state)

        # The batch it brewed goes with it, and one the pick put back is brewed again.
        brew_where_standing!(char, key) if block['pick'].to_s == 'formula'

        Ok.new(:state => { 'taken' => taken['pick'], 'source' => block['source'],
                           'restored' => (outcome.state[key] || {})['pick'] })
      end

      # The rest step, for someone as they stand in an encounter. The picks are the character's, so they
      # hold from one encounter to the next until the GM rests them.
      def self.rested!(holder)
        return [] unless holder.respond_to?(:pf2_daily_choices)

        current = picks(holder)

        return [] if current.empty?

        blocks = held(holder)
        kept, dropped = rest(current, blocks, lambda { |switch, pick|
          options(holder, blocks[switch]).any? { |one| one.casecmp?(pick.to_s) }
        })

        holder.update(:pf2_daily_choices => kept)

        dropped
      end

      # The switches a feat they hold lets them pick again without a rest: Ultimate Flexibility's hour of
      # training (`daily_reprepare: [ flexibility, ... ]`), Radiant Armament's ten minutes to change the rune.
      def self.reopenable(char)
        (char.pf2_feats || {}).values.flatten.map(&:to_s).uniq.flat_map do |name|
          info = Global.read_config('pf2e_feats', name)

          info.is_a?(Hash) ? Array(info['daily_reprepare']) : []
        end.map { |one| one.to_s.downcase }.uniq
      end

      # Opens again the picks a feat lets them make over without a rest, for `encounter/reprepare`. The GM
      # decides it, because the time it takes, and what they have already spent of what they would give up,
      # are the story's to say.
      def self.reopen!(holder)
        return Err.new(:nothing_to_reopen, 'pf2e.reprepare_nothing', 'name' => holder.name) unless holder.respond_to?(:pf2_daily_choices)

        switches = reopenable(holder)

        return Err.new(:nothing_to_reopen, 'pf2e.reprepare_nothing', 'name' => holder.name) if switches.empty?

        current = picks(holder)
        cleared = current.select { |switch, _| switches.include?(switch) }
        blocks = held(holder)

        cleared.each { |switch, pick| take_back!(Actors.of(holder).person || holder, blocks[switch], pick) }

        holder.update(:pf2_daily_choices => current.reject { |switch, _| switches.include?(switch) })

        Ok.new(:state => { 'cleared' => cleared.values.map { |pick| label(pick) }, 'switches' => switches })
      end

      # ------------------------------------------------------------------------------
      # What the picks do.

      # What they picked for a switch, where the pick is in force: a Bomber's vial material.
      def self.pick(char, switch)
        found = in_force(char)[switch.to_s.downcase]

        found ? found.first['pick'] : nil
      end

      # 'trained' for a skill a pick trains them in, or nil.
      def self.temporary_rank(char, skill)
        trained = in_force(char).any? do |_switch, (pick, block)|
          block['pick'].to_s == 'skill' && block['trains'] && pick['pick'].to_s.casecmp?(skill.to_s)
        end

        trained ? 'trained' : nil
      end

      # Whether a weapon pick gives familiarity with this weapon.
      def self.familiar?(char, weapon)
        in_force(char).any? do |_switch, (pick, block)|
          block['pick'].to_s == 'weapon' && block['familiarity'] && pick['pick'].to_s.casecmp?(weapon.to_s)
        end
      end

      # `item:daily-choice:<switch>` for each weapon pick naming this weapon, so a rule can ask about the
      # weapon picked: Egalrin Weapon Familiarity's critical specialization reaches the practiced sword.
      def self.weapon_options(char, weapon)
        in_force(char).select { |_switch, (pick, block)|
          block['pick'].to_s == 'weapon' && pick['pick'].to_s.casecmp?(weapon.to_s)
        }.map { |switch, _| "item:daily-choice:#{switch}" }
      end

      # A pick as a player reads it: the feat, with its own choice after it.
      def self.label(pick)
        pick['choice'] ? "#{pick['pick']} (#{pick['choice']})" : pick['pick'].to_s
      end

      # One line per daily choice open to the character, for `prepared`.
      def self.listing(char)
        current = picks(char)

        held(char).sort.map do |switch, block|
          pick = current[switch]
          made = pick.is_a?(Hash) && pick['pick']

          t('pf2e.daily_line', :switch => switch, :source => block['source'],
                               :pick => made ? label(pick) : t('pf2e.daily_unpicked'),
                               :state => made ? t(pick['locked'] ? 'pf2e.daily_locked' : 'pf2e.daily_open') : '')
        end
      end
    end
  end
end
