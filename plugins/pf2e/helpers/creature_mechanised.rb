module AresMUSH
  module Pf2e

    # What the game will do with each part of a creature: what it rolls, what it offers after a hit, what
    # it counts, and what it only announces for the GM to run. It asks the same readers the engine runs a
    # creature with, so what the editor says is what the fight does.
    #
    # Each answer is `{ 'part', 'runs', 'says' }`, `runs` being one of rolled, offered, stages, counted,
    # healed or announced.
    module CreatureMechanised

      def self.of(block)
        strikes(block) + abilities(block) + healing(block) + spells(block)
      end

      def self.said(part, runs, says)
        { 'part' => part, 'runs' => runs, 'says' => says }
      end

      def self.strikes(block)
        Array(block['strikes']).flat_map do |strike|
          [ said("Strike #{strike['name']}", 'rolled', t('pf2e.creature_runs_strike')) ] +
            Array(strike['effects']).map do |effect|
              offered = Acting::FOLLOW_UPS[Domains.slug(effect)]

              offered ? said("#{strike['name']}: #{effect}", 'offered', t('pf2e.creature_runs_follow_up', :action => offered['action'])) :
                        said("#{strike['name']}: #{effect}", 'announced', t('pf2e.creature_runs_announced'))
            end
        end
      end

      def self.abilities(block)
        Array(block['actions']).flat_map do |ability|
          name = ability['name']
          text = ability['text'].to_s

          [ ability_runs(name, text, ability['traits']) ] + waits(name, ability)
        end
      end

      def self.ability_runs(name, text, traits)
        return said(name, 'stages', t('pf2e.creature_runs_stages')) if Afflictions.read(name, text, traits)

        basic = CreatureAbilities.damage_save(text)
        if basic
          return said(name, 'rolled', t('pf2e.creature_runs_basic', :save => basic['save'].capitalize, :dc => basic['dc'],
                                                                    :formula => basic['formula'], :type => basic['type']))
        end

        saving = CreatureAbilities.saving(text)
        if saving && Hash(saving['outcomes']).any?
          return said(name, 'rolled', t('pf2e.creature_runs_outcomes', :save => saving['save'].capitalize, :dc => saving['dc']))
        end

        said(name, 'announced', t('pf2e.creature_runs_announced'))
      end

      # What the game counts of an ability: the rounds it takes to come back, and how often it may be used.
      def self.waits(name, ability)
        counted = []
        counted << said("#{name}: its wait", 'counted', t('pf2e.creature_runs_wait')) if Recharge.rounds_of(name, ability)
        counted << said("#{name}: its frequency", 'counted', t('pf2e.creature_runs_frequency')) if CreatureAbilities.frequency(ability['text'])
        counted
      end

      def self.healing(block)
        block['hp_details'].to_s.scan(Npcs::HEALING).map do |kind, value, _stops|
          said("#{kind.downcase} #{value}", 'healed', t('pf2e.creature_runs_healing', :value => value))
        end
      end

      def self.spells(block)
        Array(block['spellcasting']).flat_map { |casting| Hash(casting['spells']).values.flatten }.uniq.map do |spell|
          known = Acting.spell_mechanics(spell).last

          known ? said("Spell #{spell}", 'rolled', t('pf2e.creature_runs_spell')) : said("Spell #{spell}", 'announced', t('pf2e.creature_runs_announced'))
        end
      end
    end

    # The words a creature's stat block may use: the traits of the bestiary's creatures and of the
    # setting's ancestries and heritages, and the kinds of damage the engine knows. A word outside them is
    # warned of, not refused: an author may mean a trait staff have not listed yet.
    module CreatureVocabulary

      def self.traits
        @traits ||= (bestiary_traits + setting_traits + Array(Global.read_config('pf2e', 'creature_extra_traits')))
                    .map { |trait| Domains.slug(trait) }.uniq.sort
      end

      # Drops what was read, for a spec or an import that changed it.
      def self.reset!
        @traits = nil
      end

      def self.bestiary_traits
        Bestiary.index.values.flat_map { |one| Array(one['traits']) }
      end

      # The setting's: its ancestries' traits, and every trait its heritages name.
      def self.setting_traits
        ancestries = Hash(Global.read_config('pf2e_ancestry')).values.flat_map { |one| Array(Hash(one)['traits']) }

        ancestries + listed_traits(Global.read_config('pf2e_heritage'))
      end

      def self.listed_traits(held)
        case held
        when Hash then held.flat_map { |key, value| key == 'traits' ? Array(value) : listed_traits(value) }
        when Array then held.flat_map { |value| listed_traits(value) }
        else []
        end
      end

      def self.trait?(word)
        traits.include?(Domains.slug(word))
      end

      def self.damage?(type)
        IWR::DAMAGE_TYPES.include?(Domains.slug(type))
      end

      def self.warnings(block)
        unknown = Array(block['traits']).reject { |trait| trait?(trait) }
                                        .map { |trait| CreatureCheck.found(:creature_trait_unknown, 'trait' => trait) }
        damage = Array(block['strikes']).flat_map do |strike|
          Array(strike['damage']).reject { |_formula, type, _category| damage?(type) }
                                 .map { |_formula, type, _category| CreatureCheck.found(:creature_damage_unknown, 'type' => type, 'strike' => strike['name']) }
        end

        unknown + damage
      end
    end
  end
end
