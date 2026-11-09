module AresMUSH
  module Pf2e

    # What an alchemist's research field changes about the things they make and do (Player Core 2, p. 59),
    # beyond what Foundry's imported rules for the field already carry. The class features' config is
    # generated, so what those rules can't say is said here, by field.
    #
    # A field is the alchemist's subclass (`pf2_base_info['specialize']`). Each ability is gated by the class
    # feature it comes with: Field Discovery at 5th, Advanced Vials at 11th, Greater Field Discovery at 13th.
    module ResearchField

      FIELD_DISCOVERY = 'Field Discovery'.freeze
      ADVANCED_VIALS = 'Advanced Vials'.freeze
      GREATER_FIELD_DISCOVERY = 'Greater Field Discovery'.freeze

      # The Bomber's Advanced Vials: the materials a vial can be made of, as a daily choice.
      VIAL_MATERIAL = 'vialmaterial'.freeze

      def self.field(holder)
        return '' unless holder.respond_to?(:pf2_base_info)

        info = holder.pf2_base_info || {}

        info['charclass'].to_s.casecmp?('Alchemist') ? info['specialize'].to_s : ''
      end

      def self.field?(holder, name)
        field(holder).casecmp?(name)
      end

      def self.ability?(holder, name, feature)
        field?(holder, name) && Pf2e.holds_feature?(holder, feature)
      end

      # Rules a field's abilities give, as sources the engine reads like any feature's:
      #
      # - Toxicologist, Field Discovery: poison resistance equal to half their level.
      def self.sources(holder)
        return [] unless holder.respond_to?(:pf2_base_info)

        found = []

        if ability?(holder, 'Toxicologist', FIELD_DISCOVERY)
          found << Effects.source('Field Discovery (Toxicologist)',
                                  [ { 'key' => 'Resistance', 'type' => 'poison', 'value' => holder.pf2_level.to_i / 2 } ],
                                  'id' => 'field-discovery-toxicologist', 'kind' => Effects::DOES,
                                  'item' => { 'level' => holder.pf2_level.to_i })
        end

        # Mutagenist, Advanced Vials: physical resistance of half their level while a field vial quiets a
        # mutagen's drawbacks.
        if ability?(holder, 'Mutagenist', ADVANCED_VIALS) && Mutagens.suppressing?(holder)
          found << Effects.source('Advanced Vials (Mutagenist)',
                                  [ { 'key' => 'Resistance', 'type' => 'physical', 'value' => holder.pf2_level.to_i / 2 } ],
                                  'id' => 'advanced-vials-mutagenist', 'kind' => Effects::DOES,
                                  'item' => { 'level' => holder.pf2_level.to_i })
        end

        found
      end

      # ------------------------------------------------------------------------------
      # Chirurgeon

      MEDICINE = 'Medicine'.freeze
      CRAFTING = 'Crafting'.freeze
      RANKS = %w{untrained trained expert master legendary}.freeze

      # The field benefit: their Crafting rank for anything that needs a Medicine rank, and their Crafting
      # modifier for Medicine checks.
      def self.medicine_by_crafting?(holder, skill)
        skill.to_s.casecmp?(MEDICINE) && holder.respond_to?(:pf2_base_info) && field?(holder, 'Chirurgeon')
      end

      # The skill whose attribute a check reads.
      def self.skill_used(holder, skill)
        medicine_by_crafting?(holder, skill) ? CRAFTING : skill
      end

      def self.better(first, second)
        (RANKS.index(first.to_s.downcase) || 0) >= (RANKS.index(second.to_s.downcase) || 0) ? first : second
      end

      # The rank a check rolls: a Chirurgeon's Crafting for their Medicine.
      def self.rolling_prof(holder, skill)
        return Pf2eSkills.rolling_prof(holder, skill) unless medicine_by_crafting?(holder, skill)

        Pf2eSkills.rolling_prof(holder, CRAFTING)
      end

      # The rank a prerequisite reads: a Chirurgeon's Medicine at least their Crafting.
      def self.held_prof(holder, skill)
        held = Pf2eSkills.get_skill_prof(holder, skill)

        medicine_by_crafting?(holder, skill) ? better(held, Pf2eSkills.get_skill_prof(holder, CRAFTING)) : held
      end

      # Field vials: a vial drunk, or thrown at a willing creature, heals the living by its initial damage,
      # with the healing and coagulant traits.
      def self.healing_vial?(user, info)
        !user.nil? && user.respond_to?(:pf2_base_info) && field?(user, 'Chirurgeon') && vial?(info)
      end

      # Coagulant: healed by a coagulant item, a creature can't be healed by another for 10 minutes. Kept
      # with their turn, as the round it ends. Advanced Vials lifts it for someone at half their Hit Points or
      # fewer, who neither waits nor starts waiting.
      COAGULANT = 'coagulant'.freeze
      COAGULANT_ROUNDS = 100

      def self.coagulated?(encounter, holder)
        ends = TurnState.of(holder)[COAGULANT]

        !ends.nil? && (encounter ? encounter.round.to_i : 0) < ends.to_i
      end

      def self.coagulate!(encounter, holder)
        TurnState.write(holder, COAGULANT => (encounter ? encounter.round.to_i : 0) + COAGULANT_ROUNDS)
      end

      def self.hurt_badly?(holder)
        now, max = Harm.hit_points(holder).to_s.split('/').map(&:to_i)

        max.to_i.positive? && now.to_i * 2 <= max.to_i
      end

      def self.vial_heal(encounter, target, name, info, user, out)
        unless Consumables.heals?(target.holder, 'vitality')
          return out['lines'] << Telling.event('pf2e.consumable_no_effect', 'item' => name, 'target' => target.label)
        end

        spared = ability?(user, 'Chirurgeon', ADVANCED_VIALS) && hurt_badly?(target.holder)

        if !spared && coagulated?(encounter, target.holder)
          return out['lines'] << Telling.event('pf2e.coagulant_blocked', 'target' => target.label, 'item' => name)
        end

        bomb = info['bomb'] || {}
        amount = Pf2e.roll_formula("#{bomb['dice'].to_i}#{bomb['die']}")

        Harm.heal(target.holder, amount)
        coagulate!(encounter, target.holder) unless spared

        out['lines'] << Telling.event('pf2e.consumable_heals', 'target' => target.label, 'count' => amount, 'item' => name)
      end

      MADE = [ 'advanced alchemy', 'quick alchemy' ].freeze

      # Field Discovery: an infused healing elixir they made gives whoever drinks it temporary Hit Points
      # equal to their Intelligence modifier.
      def self.fortifying(user, info, made_by)
        return 0 unless user && MADE.include?(made_by.to_s) && ability?(user, 'Chirurgeon', FIELD_DISCOVERY)
        return 0 unless (traits(info) & %w{elixir healing}).size == 2

        [ Pf2eAbilities.abilmod(Pf2eAbilities.get_score(user, 'Intelligence')), 0 ].max
      end

      def self.give_temp_hp(target, amount, out)
        hp = target.holder.respond_to?(:hp) ? target.holder.hp : nil

        return unless hp && amount.positive? && amount > hp.temp_hp.to_i

        hp.update(:temp_hp => amount, :temp_hp_source => FIELD_DISCOVERY)
        out['lines'] << Telling.event('pf2e.chirurgeon_temp_hp', 'target' => target.label, 'count' => amount)
      end

      # Greater Field Discovery: an elixir of life they made with Quick Alchemy heals the most it can.
      def self.heals_most?(user, name, made_by)
        made_by.to_s == 'quick alchemy' && name.to_s.start_with?('Elixir of Life') &&
          ability?(user, 'Chirurgeon', GREATER_FIELD_DISCOVERY)
      end

      # ------------------------------------------------------------------------------
      # Mutagenist

      # A Mutagenist's field vial, drunk: one mutagen's drawbacks quiet for a minute.
      def self.mutagen_vial?(user, info)
        !user.nil? && field?(user, 'Mutagenist') && vial?(info)
      end

      # A vial a research field lets them drink rather than throw.
      def self.drinkable_vial?(user, info)
        healing_vial?(user, info) || mutagen_vial?(user, info)
      end

      def self.quiet_drawbacks(encounter, target, user, out)
        return out['lines'] << Telling.event('pf2e.mutagen_vial_self', 'target' => target.label) unless same?(target.holder, user)

        found = Mutagens.suppress!(user, encounter)

        return out['lines'] << Telling.event('pf2e.mutagen_none', 'target' => target.label) unless found

        out['lines'] << Telling.event('pf2e.mutagen_quiet', 'target' => target.label, 'mutagen' => ActiveEffects.bare_name(found))
      end

      def self.same?(first, second)
        !first.nil? && !second.nil? && first.class == second.class && first.id == second.id
      end

      # Field benefit: using a mutagen gives them temporary Hit Points equal to their Intelligence modifier
      # plus half their level, and not again for a minute.
      MUTAGEN_TEMP = 'mutagenist_temp_hp'.freeze

      def self.mutagen_temp_hp(encounter, target, user, info, out)
        return unless user && field?(user, 'Mutagenist') && same?(target.holder, user)
        return unless traits(info).include?('mutagen')

        now = encounter ? encounter.round.to_i : 0
        ready = TurnState.of(user)[MUTAGEN_TEMP]

        return if ready && now < ready.to_i

        amount = [ Pf2eAbilities.abilmod(Pf2eAbilities.get_score(user, 'Intelligence')), 0 ].max + user.pf2_level.to_i / 2
        TurnState.write(user, MUTAGEN_TEMP => now + Mutagens::SUPPRESS_ROUNDS)
        give_temp_hp(target, amount, out)
      end

      def self.vial?(info)
        info.is_a?(Hash) && info['slug'].to_s == 'versatile-vial'
      end

      def self.traits(info)
        Array((info || {})['traits']).map { |one| one.to_s.downcase }
      end

      # A bomb as this alchemist throws it.
      #
      # - Bomber, Field Discovery: an alchemical bomb with the splash trait deals splash damage equal to
      #   their Intelligence modifier (at least 1) instead of the normal amount, where that is higher.
      # - Bomber, Advanced Vials: their versatile vials are of the material they chose for the day.
      def self.bomb(holder, info, descriptor)
        return descriptor unless field?(holder, 'Bomber')

        made = descriptor.dup
        kinds = traits(info)

        if Pf2e.holds_feature?(holder, FIELD_DISCOVERY) && kinds.include?('alchemical') && kinds.include?('splash')
          intelligence = [ Pf2eAbilities.abilmod(Pf2eAbilities.get_score(holder, 'Intelligence')), 1 ].max
          made['splash'] = [ made['splash'].to_i, intelligence ].max
        end

        material = DailyChoices.pick(holder, VIAL_MATERIAL)
        made['materials'] = Array(made['materials']) + [ material ] if material && vial?(info)

        made
      end
    end
  end
end
