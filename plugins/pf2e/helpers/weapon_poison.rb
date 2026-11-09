module AresMUSH
  module Pf2e

    # An injury poison on a weapon (GM Core, p. 248, the injury trait). It waits for the first Strike made
    # with the weapon:
    #
    #   a hit dealing piercing or slashing damage   exposes the target, who saves against it
    #   a miss                                      leaves it on the weapon, to try again
    #   a critical miss, or a hit without piercing   wastes it
    #   or slashing damage
    #
    # Only one is on a weapon at a time. It is kept on the weapon itself (`PF2Weapon#poison`), which in an
    # encounter is the encounter's copy of it, so it goes with the encounter.
    #
    # A poison's affliction is its stat block in the catalogue (`affliction:`), which `Afflictions` reads
    # and runs. Poison Weapon's simple injury poison has none: it deals `poison_damage` with no saving
    # throw. A poison an alchemist made carries their class DC where Powerful Alchemy stamped it, and the
    # target saves against the higher of that and the poison's own.
    module WeaponPoison

      POISON_WEAPON = 'Poison Weapon'.freeze
      SIMPLE = 'Simple Injury Poison'.freeze
      MADE_BY = 'poison weapon'.freeze
      TOXICOLOGIST = 'Toxicologist'.freeze

      def self.info(name)
        Global.read_config('pf2e_consumables', name.to_s) || {}
      end

      def self.injury?(info)
        Array(info['traits']).map { |one| one.to_s.downcase }.include?('injury')
      end

      # A weapon they wield, by what they call it.
      def self.weapon(holder, term)
        wanted = Domains.slug(term)

        Pf2egear::Inventory.held(holder, 'weapons').select(&:equipped).find do |item|
          [ item.name, (item.nickname if item.respond_to?(:nickname)) ].compact.any? { |one| Domains.slug(one) == wanted }
        end
      end

      # An injury poison they carry outside a bag, by its name or enough of it to tell it apart. A
      # Toxicologist's versatile vials are poisons they can apply too.
      def self.poison(holder, term)
        wanted = term.to_s.strip.downcase
        vials = toxicologist?(holder)
        held = Pf2egear::Inventory.held(holder, 'consumables').select do |item|
          found = info(item.name)
          injury?(found) || (vials && ResearchField.vial?(found))
        end

        held.find { |item| item.name.downcase == wanted } ||
          held.select { |item| item.name.downcase.include?(wanted) }.then { |some| some.map(&:name).uniq.size == 1 ? some.first : nil }
      end

      # How many actions applying one takes: one with Poison Weapon or a Toxicologist's field benefit, and
      # otherwise what the poison says.
      def self.cost(holder, item_info)
        return 1 if Pf2e.has_feat?(holder, POISON_WEAPON) || toxicologist?(holder)

        [ item_info['activate'].to_i, 1 ].max
      end

      def self.toxicologist?(holder)
        ResearchField.field?(holder, TOXICOLOGIST)
      end

      # Puts the poison on the weapon and uses it up. Answers `{ 'weapon', 'poison', 'cost' }`.
      def self.apply!(holder, weapon_term, poison_term)
        armed = weapon(holder, weapon_term)

        return Err.new(:no_weapon, 'pf2e.poison_no_weapon', 'weapon' => weapon_term) unless armed
        return Err.new(:already_poisoned, 'pf2e.poison_already', 'weapon' => armed.name, 'poison' => armed.poison['name']) if
          armed.poison.is_a?(Hash) && armed.poison['name']

        dose = poison(holder, poison_term)

        return Err.new(:no_poison, 'pf2e.poison_none', 'poison' => poison_term) unless dose

        found = info(dose.name)
        entry = ResearchField.vial?(found) ? vial_dose(holder, dose, found) : poison_dose(holder, dose, found)

        armed.update(:poison => entry)
        Consumables.spend!(holder, dose.id)

        Ok.new(:state => { 'weapon' => armed.name, 'poison' => dose.name, 'cost' => cost(holder, found) })
      end

      # What a dose of poison leaves on the weapon. `toxic` marks an infused poison a Toxicologist made and
      # applied themselves, which harms the poison-immune and, from 13th level, sprays.
      def self.poison_dose(holder, dose, found)
        { 'name' => dose.name, 'dc' => dose.respond_to?(:dc) ? dose.dc.to_i : 0, 'damage' => found['poison_damage'],
          'by' => holder.name, 'toxic' => toxicologist?(holder) && infused?(dose) }
      end

      # A Toxicologist's field vial: its initial damage, as poison, added to the first Strike that hits, and
      # at Advanced Vials persistent poison damage equal to its splash. Inert at the end of the turn.
      def self.vial_dose(holder, dose, found)
        bomb = found['bomb'] || {}
        persistent = ResearchField.ability?(holder, TOXICOLOGIST, ResearchField::ADVANCED_VIALS) ? bomb['splash'].to_i : 0

        { 'name' => dose.name, 'damage' => "#{bomb['dice'].to_i}#{bomb['die']} poison", 'persistent' => persistent,
          'by' => holder.name, 'toxic' => true, 'lasts' => 'turn_end' }
      end

      INFUSED = [ Alchemy::PREPARED, Alchemy::QUICK, Alchemy::VIALS, Alchemy::QUICK_VIAL ].freeze

      def self.infused?(dose)
        INFUSED.include?(dose.granted_by.to_s)
      end

      # What a Strike does with the poison on its weapon, once its roll is known.
      def self.after_strike(scene, attack, degree, out)
        return if attack['bomb'] || attack['id'].to_s.empty?
        # A creature's Strikes are its stat block's, and it carries no weapons to poison.
        return unless Actors.of(scene.actor.holder).carries_items?

        armed = Pf2egear::Inventory.held(scene.actor.holder, 'weapons').find { |one| one.id.to_s == attack['id'].to_s }

        return unless armed && armed.poison.is_a?(Hash) && armed.poison['name']

        # A miss leaves it there for the next Strike. A Strike that never rolled - a concealed miss - is one.
        return if degree.nil? || degree == Degree::FAILURE

        dose = armed.poison
        armed.update(:poison => {})

        unless Degree.success?(degree) && cuts?(attack)
          return out['lines'] << Telling.event('pf2e.poison_wasted', 'weapon' => armed.name, 'poison' => dose['name'])
        end

        expose(scene, dose, out)
      end

      # Whether the Strike deals piercing or slashing damage, by the letter a weapon carries or the word.
      def self.cuts?(attack)
        type = attack['damage_type'].to_s

        type.match?(/\A[PS](\z|\W)/i) || type.match?(/piercing|slashing/i)
      end

      # The target is exposed: a simple poison's damage, or the affliction, saved against at the higher of
      # the poison's DC and the one its maker stamped.
      def self.expose(scene, dose, out)
        acid = dose['toxic'] && poison_immune?(scene.target)

        out['lines'] << Telling.event('pf2e.poison_exposed', 'target' => scene.target.label, 'poison' => dose['name'])

        if dose['damage'].to_s.strip != ''
          formula, type = dose['damage'].to_s.split(/\s+/, 2)
          type = acid ? 'acid' : (type || 'poison')
          formulas = [ [ formula, type, nil ] ]
          formulas << [ dose['persistent'].to_s, type, 'persistent' ] if dose['persistent'].to_i.positive?

          return Acting.deal(scene, scene.target, DamageRoll.of_formulas(formulas, false), out)
        end

        found = info(dose['name'])
        affliction = Afflictions.read(dose['name'], found['affliction'], found['traits'])

        return unless affliction

        affliction['dc'] = [ affliction['dc'].to_i, dose['dc'].to_i ].max
        affliction = as_acid(affliction) if acid
        held = Afflictions.on(scene.target.holder).any? { |one| one['name'] == affliction['name'] }

        Afflictions.catch(scene, scene.target, affliction, out)

        offer_spray(scene, dose, affliction, out) unless held
      end

      # A Toxicologist's infused poison works on a creature immune to poison, dealing acid instead.
      def self.poison_immune?(target)
        !IWR.immune_to_effect?(IWR.for(target.holder), [ 'poison' ]).nil?
      end

      def self.as_acid(affliction)
        stages = affliction['stages'].map do |stage|
          stage.merge('damage' => Array(stage['damage']).map { |formula, type| [ formula, type.to_s == 'poison' ? 'acid' : type ] })
        end

        affliction.merge('traits' => affliction['traits'] - [ 'poison' ], 'stages' => stages)
      end

      # ------------------------------------------------------------------------------
      # The Toxicologist's Greater Field Discovery: a failed initial save sprays the poison onto a creature
      # next to the one poisoned. The game can't see who is next to whom, so the attacker names them.

      SPRAY = 'spray'.freeze

      def self.offer_spray(scene, dose, affliction, out)
        return unless dose['toxic'] && ResearchField.ability?(scene.actor.holder, TOXICOLOGIST, ResearchField::GREATER_FIELD_DISCOVERY)
        return unless Afflictions.on(scene.target.holder).any? { |one| one['name'] == affliction['name'] }

        TurnState.write(scene.actor.holder, SPRAY => { 'affliction' => affliction, 'from' => scene.target.label })
        out['lines'] << Telling.event('pf2e.spray_ready', 'actor' => scene.actor.label, 'target' => scene.target.label,
                                                          'poison' => affliction['name'])
      end

      # The spray, onto the creature named. The one sprayed doesn't spread it further.
      def self.spray!(scene, out)
        pending = TurnState.of(scene.actor.holder)[SPRAY]

        return Err.new(:no_spray, 'pf2e.spray_none') unless pending.is_a?(Hash)
        return Err.new(:same_target, 'pf2e.spray_same', 'target' => pending['from']) if scene.target.label == pending['from']

        TurnState.write(scene.actor.holder, SPRAY => nil)
        out['lines'] << Telling.event('pf2e.spray_done', 'target' => scene.target.label, 'poison' => pending['affliction']['name'])
        Afflictions.catch(scene, scene.target, pending['affliction'], out)

        Ok.new(:state => out)
      end

      # The end of their turn: a field vial on a weapon goes inert, and a spray not used is gone.
      def self.turn_ended(holder)
        return unless Actors.of(holder).carries_items?

        Pf2egear::Inventory.held(holder, 'weapons').each do |armed|
          armed.update(:poison => {}) if armed.poison.is_a?(Hash) && armed.poison['lasts'] == 'turn_end'
        end

        TurnState.write(holder, SPRAY => nil) if TurnState.of(holder)[SPRAY]
      end

      # A rest, or joining an encounter fresh: Poison Weapon's simple injury poisons for the day, as many as
      # their level. They lapse at the next rest.
      def self.at_rest!(holder)
        return unless Actors.of(holder).carries_items? && Pf2e.has_feat?(holder, POISON_WEAPON)

        count = [ holder.pf2_level.to_i, 1 ].max

        Equipment.grant!(holder, 'consumables', SIMPLE, count, info(SIMPLE), :granted_by => MADE_BY, :expires => 'rest')
      end
    end
  end
end
