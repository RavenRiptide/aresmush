module AresMUSH
  module Pf2e

    # Apex items (GM Core): an invested apex item raises one attribute modifier by 1, or to +4, whichever is
    # higher. The item names its attribute in its catalogue row (`apex: Constitution`).
    #
    # Only one apex item counts at a time. A character can't invest an apex item while another is invested,
    # and only the first one invested in a day counts: a second one invested after uninvesting the first gives
    # its other effects but no increase until the GM next rests them (house rule, after GM Core's 24 hours).
    # Which one counts is held on the character in `pf2_apex`, as daily state.
    #
    # The increase is worked out whenever a score is read (`Pf2eAbilities.get_score`) and never written, so it
    # comes and goes with the item and leaves the ledger alone. What the sheet's history depends on - a feat's
    # prerequisites, how many picks a choice opens - reads the stored score (`Pf2eAbilities.base_score`).
    #
    # Divine Apex lends the apex trait to a worn item for the day, and works only in an encounter the cleric
    # is a combatant in too (house rule). A character's own apex item, where one counts, wins over it.
    module Apex

      DIVINE_SWITCH = 'divineapex'.freeze

      def self.attribute_of(info)
        info.is_a?(Hash) ? info['apex'] : nil
      end

      def self.info(item)
        Pf2egear.catalogue_entry('magicitem', item) || {}
      end

      def self.apex_item?(item)
        item.is_a?(PF2MagicItem) && !attribute_of(info(item)).to_s.empty?
      end

      # The character's own item an encounter's copy was taken from, or the item itself.
      def self.own_id(item)
        (item.respond_to?(:copied_from) && item.copied_from ? item.copied_from : item.id).to_s
      end

      def self.items(holder)
        Pf2egear::Inventory.held(holder, 'magicitem').select { |one| apex_item?(one) }
      end

      def self.mark(holder)
        holder.respond_to?(:pf2_apex) ? (holder.pf2_apex || {}) : {}
      end

      # ------------------------------------------------------------------------------
      # Investing

      # Why this item can't be invested, or nil: another apex item is invested.
      def self.refusal(holder, item)
        return nil unless apex_item?(item)

        other = items(holder).find { |one| one.invested && one.id != item.id }

        other ? Err.new(:apex_invested, 'pf2egear.apex_already', 'item' => item.name, 'other' => other.name) : nil
      end

      # An apex item invested when none counts yet today is the one that counts.
      def self.invested!(holder, item)
        return unless apex_item?(item) && holder.respond_to?(:pf2_apex) && mark(holder)['item'].nil?

        holder.update(:pf2_apex => { 'item' => own_id(item), 'name' => item.name })
      end

      # A rest starts a new day: the apex item invested now is the one that counts.
      def self.rested!(holder)
        return unless holder.respond_to?(:pf2_apex)

        holder.update(:pf2_apex => {})

        first = items(holder).find(&:invested)
        invested!(holder, first) if first
      end

      # Whether this item is the one that counts today, for `item/view`.
      def self.counts?(holder, item)
        found = in_effect(holder)

        !!found && found['item_id'] == item.id.to_s
      end

      # ------------------------------------------------------------------------------
      # What counts

      # `{ 'attribute', 'source', 'item_id' }` for the apex increase they have now, or nil.
      #
      # Every attribute read asks this, many times outside any command as well as inside one, so it has to be
      # cheap without a cache: `own` reads their own magic items, and `divine` reads only the givers who named
      # them. Inside a command the answer is also kept by the record until the next write (`ReadCache.kept`),
      # because a fight reloads its combatants after every write.
      def self.in_effect(holder)
        # Only a character keeps the day's apex item; a creature has none.
        return nil unless holder.respond_to?(:pf2_apex) && Actors.of(holder).carries_items?

        found = lambda { SheetReads.memo(holder, :apex) { own(holder) || divine(holder) } }

        return found.call unless holder.respond_to?(:id) && holder.id

        ReadCache.kept([ :apex, holder.class.name, holder.id.to_s ], &found)
      end

      # Their own apex item, if one counts: the one marked today if it's invested. One invested before any
      # was marked counts in its place.
      def self.own(holder)
        held = items(holder)
        marked = mark(holder)['item']
        item = marked ? held.find { |one| own_id(one) == marked.to_s } : held.find(&:invested)

        return nil unless item&.invested

        { 'attribute' => attribute_of(info(item)), 'source' => item.name, 'item_id' => item.id.to_s }
      end

      # Divine Apex from a cleric in the same encounter whose pick names them and an item they wear. Only the
      # givers who named them are read, from the list kept on them (`DailyChoices.designate!`), which is empty
      # for almost everyone. Sweeping the encounter's combatants for every attribute read once took more than
      # half of a fight's time. The list is a hint: each giver's picks are still checked.
      def self.divine(holder)
        encounter = Actors.of(holder).encounter
        person = encounter && Actors.of(holder).person

        return nil unless person.respond_to?(:pf2_designated_by)

        Array(person.pf2_designated_by).each do |id|
          giver = Character[id]

          next unless giver && DailyChoices.picks(giver).key?(DIVINE_SWITCH)

          pick, _block = DailyChoices.in_force(giver)[DIVINE_SWITCH]

          next unless pick && Array(pick['names']).any? { |name| name.casecmp?(person.name) }
          next unless DailyChoices.present?(giver, encounter)

          item = worn(holder, pick['item'])

          return { 'attribute' => pick['attribute'], 'source' => "Divine Apex (#{giver.name})", 'item_id' => item.id.to_s } if item
        end

        nil
      end

      # A worn magical item by name, without the apex trait: an invested magic item, or armor they wear.
      def self.worn(holder, name)
        return nil if name.to_s.empty?

        magic = Pf2egear::Inventory.held(holder, 'magicitem').find { |one| one.invested && one.name.casecmp?(name) && !apex_item?(one) }

        magic || Pf2egear::Inventory.held(holder, 'armor').find { |one| one.equipped && one.name.casecmp?(name) && magical?(one) }
      end

      # Armor is magical when it says so or carries a potency rune.
      def self.magical?(armor)
        Pf2e.has_trait?(armor.traits, 'magical') || Pf2egear.get_rune_value(armor, 'fundamental', 'potency').to_i.positive?
      end

      # ------------------------------------------------------------------------------
      # The score

      # A score with the apex increase, where it's for this attribute: the modifier up by 1, or to +4.
      def self.adjust(holder, ability, score)
        found = in_effect(holder)

        return score unless found && found['attribute'].to_s.casecmp?(ability.to_s)

        raised = [ Pf2eAbilities.abilmod(score) + 1, 4 ].max

        [ score, 10 + (2 * raised) ].max
      end

      # ------------------------------------------------------------------------------
      # Intelligence's skill and language

      INTELLIGENCE = 'Intelligence'.freeze

      # An apex item raising Intelligence asks for a skill and a language the first time it's invested, and
      # keeps them (`ItemChoices`). They last while it's the apex item that counts.
      def self.questions(info)
        return [] unless attribute_of(info).to_s.casecmp?(INTELLIGENCE)

        skills = (Global.read_config('pf2e_skills') || {}).keys.map(&:to_s).reject { |one| Pf2eSkills.lore?(one) }.sort
        languages = ((Global.read_config('pf2e_languages') || {})['common'] || {}).keys.map(&:to_s).sort

        [ { 'key' => 'apexSkill', 'answers' => skills.map { |one| [ Domains.slug(one), one ] } },
          { 'key' => 'apexLanguage', 'answers' => languages.map { |one| [ one, one ] } } ]
      end

      # The skill and language the counting apex item was given, as `[ skill, language ]` labels.
      def self.chosen(holder)
        found = in_effect(holder)
        item = found && Pf2egear::Inventory.held(holder, 'magicitem').find { |one| one.id.to_s == found['item_id'] }

        return [ nil, nil ] unless item && found['attribute'].to_s.casecmp?(INTELLIGENCE) && apex_item?(item)

        skill_q, language_q = questions(info(item))
        held = Array(item.answers).map(&:to_s)
        pick = lambda { |question| question['answers'].find { |value, _label| held.include?(value.to_s) }&.last }

        [ pick.call(skill_q), pick.call(language_q) ]
      end

      # Trained in the crown's chosen skill while it counts.
      def self.temporary_rank(holder, skill)
        return nil unless Actors.of(holder).carries_items?

        chosen_skill, _language = chosen(holder)

        chosen_skill && chosen_skill.casecmp?(skill.to_s) ? 'trained' : nil
      end

      # The line `item/view` shows for an apex item: what it raises, and whether it's waiting for a rest.
      def self.describe(holder, item)
        return [] unless apex_item?(item)

        attribute = attribute_of(info(item))
        waiting = item.invested && !counts?(holder, item)

        [ t(waiting ? 'pf2egear.apex_waits' : 'pf2egear.apex_counts', :attribute => attribute) ]
      end

      # The attribute the increase is for, for the sheet to mark, or nil.
      def self.attribute(holder)
        in_effect(holder)&.dig('attribute')
      end
    end
  end
end
