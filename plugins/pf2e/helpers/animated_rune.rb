module AresMUSH
  module Pf2e

    # An animated rune's Set Free: the wielder releases the weapon, and it fights on its own against the last
    # enemy they attacked (GM Core).
    #
    # At the end of each of its owner's turns it Strikes, with an attack modifier of +24 plus its potency
    # rune, its own damage dice with no Strength, and the damage its runes always add. Then it rolls a DC 6
    # flat check: on a failure it falls, and can't be set free again for 10 minutes. The map is in another app,
    # so its flying is said rather than measured. Taking it back in hand (`e/equip`) ends it too.
    module AnimatedRune

      NAME = 'Set Free'.freeze
      ATTACK = 24
      FLAT_DC = 6
      # Ten minutes, in rounds.
      RESTS = 100

      def self.act(scene, out)
        holder = scene.actor.holder
        weapon = RuneActions.carriers(holder, NAME).first
        round = scene.encounter ? scene.encounter.round.to_i : 0

        if weapon.animated['rested_until'].to_i > round
          return Err.new(:resting, 'pf2e.animated_resting', 'weapon' => weapon.name, 'rounds' => weapon.animated['rested_until'].to_i - round)
        end

        target = scene.target || last_attacked(scene)

        return Err.new(:needs_target, 'pf2e.animated_needs_target', 'weapon' => weapon.name) unless target

        weapon.update(:equipped => false, :animated => { 'target' => target.number })
        out['lines'] << Telling.event('pf2e.act_announced', :actor => scene.actor.label, :action => NAME, :cost => Actions.cost(NAME),
                                                           :target => '')
        out['lines'] << Telling.event('pf2e.animated_set_free', :weapon => weapon.name, :target => target.label)
        nil
      end

      # Whoever their last Strike this turn was against.
      def self.last_attacked(scene)
        last = TurnState.turn(scene.actor.holder)['last']
        found = last && scene.encounter ? Combatants.find(scene.encounter, "##{last['number']}") : nil

        found&.ok? ? found.state : nil
      end

      # ------------------------------------------------------------------------------
      # At the end of its owner's turn

      def self.turn_ended(encounter, participant, holder)
        return [] unless Actors.of(holder).carries_items?

        Pf2egear::Inventory.held(holder, 'weapons').select { |one| one.animated['target'] }.flat_map do |weapon|
          # Back in their hand, it is an ordinary weapon again.
          if weapon.equipped
            weapon.update(:animated => {})
            next []
          end

          fights(encounter, participant, holder, weapon)
        end
      end

      def self.fights(encounter, participant, holder, weapon)
        owner = Combatants.find(encounter, participant)

        return [] unless owner.ok?

        target = target_of(encounter, holder, weapon)

        return [ Telling.event('pf2e.animated_no_target', :weapon => weapon.name) ] unless target

        out = Acting.report
        scene = Acting::Scene.new(encounter, owner.state, target, nil, false)
        strike(scene, weapon, out)

        flat = Resolve.flat(FLAT_DC)
        out['lines'] << Telling.event(flat['success'] ? 'pf2e.animated_flies_on' : 'pf2e.animated_falls',
                                      :weapon => weapon.name, :die => flat['die'], :dc => FLAT_DC)
        weapon.update(:animated => { 'rested_until' => encounter.round.to_i + RESTS }) unless flat['success']

        out['lines']
      end

      # The enemy it was set on while it stands, and otherwise the first enemy still standing, which the room
      # is told.
      def self.target_of(encounter, holder, weapon)
        found = Combatants.find(encounter, "##{weapon.animated['target']}")

        return found.state if found.ok? && !down?(found.state.holder)

        side = Actors.of(holder).side
        foe = Combatants.all(encounter).find { |one| Actors.of(one.holder).side != side && !down?(one.holder) }

        weapon.update(:animated => weapon.animated.merge('target' => foe.number)) if foe
        foe
      end

      # Defeated: dead, or out of hit points.
      def self.down?(holder)
        counts = Actors.of(holder).hit_point_counts

        Pf2e.dead?(holder) || (!counts.nil? && counts.first.to_i <= 0)
      end

      def self.strike(scene, weapon, out)
        modifier = ATTACK + Pf2egear.get_rune_value(weapon, 'fundamental', 'potency').to_i
        defence = Resolve.defence(scene.target.holder, 'ac')
        die = Pf2e.roll_dice(1, 20).first.to_i
        total = die + modifier
        degree = Degree.of(total, defence['dc'], die)
        result = { 'total' => total, 'die' => die, 'dice' => [ die ], 'modifier' => modifier }

        out['lines'] << Telling.event('pf2e.animated_strikes', :weapon => weapon.name, :target => scene.target.label,
                                                              :roll => Telling.roll(result), :ac => defence['dc'],
                                                              :degree => Telling.degree(degree, true))

        return unless Degree.success?(degree)

        critical = degree == Degree::CRITICAL_SUCCESS
        Acting.deal(scene, scene.target, damage(weapon, critical), out, :critical => critical)
      end

      # Its own dice and kind of damage, without the Strength of whoever wielded it, and what its runes add
      # whatever it hits. A critical hit doubles all but persistent damage and what only a critical hit adds.
      def self.damage(weapon, critical)
        dice = 1 + Pf2egear.get_rune_value(weapon, 'fundamental', 'striking').to_i
        own = [ [ "#{dice}#{weapon.wp_damage}", DamageRoll.kind(weapon.wp_damage_type), nil ] ]
        added = rune_dice(weapon).reject { |row| row['critical'] && !critical }
        doubled, kept = added.partition { |row| row['category'].nil? && !row['critical'] }

        DamageRoll.of_formulas(own + doubled.map { |row| formula(row) }, critical) +
          DamageRoll.of_formulas(kept.map { |row| formula(row) }, false)
      end

      def self.formula(row)
        [ "#{row['diceNumber'] || 1}#{row['dieSize']}", row['damageType'], row['category'] ]
      end

      # The damage dice its property runes add to every Strike: the rows that ask nothing of the target.
      def self.rune_dice(weapon)
        Pf2egear.property_list(weapon).flat_map do |name|
          Array((Pf2egear.rune_entry(name) || {})['rules']).select do |row|
            row.is_a?(Hash) && row['key'] == 'DamageDice' && row['predicate'].nil? && row['dieSize'] && row['damageType']
          end
        end
      end
    end
  end
end
