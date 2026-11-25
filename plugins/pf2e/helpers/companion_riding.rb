module AresMUSH
  module Pf2e
    module Companion

      # Riding an animal companion (Player Core p. 206, and Mounted Combat, p. 435). Its master or an ally may
      # ride it if it is at least one size larger than them. Encounters have no map, so riding is a state: the
      # companion's record holds its rider's id in the order, and the rider has `Effect: Mounted` (-2
      # circumstance to Reflex saves).
      #
      # While ridden, rider and mount fight as a unit and share one multiple attack penalty; the rider's only
      # move action is Mount, which dismounts; and a companion without the mount special can use only its land
      # Speed, and can't move and Support in the same turn. A player is refused these; the GM may do anything.
      module Riding

        MOUNT = 'Mount'.freeze
        EFFECT = 'Effect: Mounted'.freeze
        FELL_RIDER = 'Fell Rider'.freeze
        HEAL_MOUNT = 'Heal Mount'.freeze
        LAY_ON_HANDS = 'Lay on Hands'.freeze
        # What Heal Mount makes *lay on hands* restore on one's mount, and each heightened rank adds.
        HEAL_MOUNT_HP = '10'.freeze
        # The Speeds a companion without the mount special can't use while ridden.
        OTHER_SPEEDS = %w{Burrow Climb Fly Swim}.freeze

        def self.companion?(holder)
          !holder.nil? && Actors.of(holder).minion_kind == 'companion'
        end

        def self.encounter_of(holder)
          holder.respond_to?(:encounter) ? holder.encounter : nil
        end

        # The holder's own row in the order.
        def self.row_of(encounter, holder)
          key = Actors.of(holder).creature? ? 'npc' : 'state'

          Combatants.rows(encounter).find { |row| row[key].to_s == holder.id.to_s }
        end

        # A ridden companion's rider's row, where they are still in the encounter.
        def self.rider_row(npc)
          encounter = npc.rider ? encounter_of(npc) : nil
          return nil unless encounter

          Combatants.rows(encounter).find { |row| row['id'].to_i == npc.rider.to_i }
        end

        def self.ridden?(npc)
          companion?(npc) && !rider_row(npc).nil?
        end

        # The companion this holder rides, or nil. Only someone with `Effect: Mounted` is looked for.
        def self.mount_of(holder)
          return nil if holder.nil? || companion?(holder) || !ActiveEffects.active?(holder, EFFECT)

          encounter = encounter_of(holder)
          own = encounter ? row_of(encounter, holder) : nil
          return nil unless own

          Combatants.rows(encounter).each do |row|
            next unless row['master'] && row['npc']

            npc = Pf2eNpc[row['npc']]
            return npc if npc && companion?(npc) && npc.rider.to_i == own['id'].to_i
          end

          nil
        end

        # Whether this holder rides this companion.
        def self.rides?(holder, npc)
          mount = mount_of(holder)
          !mount.nil? && mount.id.to_s == npc.id.to_s
        end

        def self.down?(npc)
          Pf2e.dead?(npc) || Pf2e.held_conditions(npc).key?('Unconscious') || Pf2e.condition_level(npc, 'Dying').positive?
        end

        # ------------------------------------------------------------------------------
        # Mount

        # The Mount action: onto a companion, or off one when already mounted. Nil where the target isn't a
        # companion, so the action is only announced, as any other.
        def self.act(scene, name, targets)
          rider = scene.actor
          target = targets.first
          mounted = mount_of(rider.holder)

          if mounted
            if target && target.holder.id.to_s != mounted.id.to_s
              return Err.new(:already_mounted, 'pf2e.companion_riding_already_mounted', 'rider' => rider.label, 'mount' => mounted.name)
            end

            return dismount(scene, name, mounted)
          end

          return nil unless target && companion?(target.holder)

          refused = mount_refusal(rider, target)
          return refused if refused

          npc = target.holder
          npc.update(:rider => rider.number)
          ActiveEffects.apply(rider.holder, EFFECT, :applied_by => target.label, :encounter => scene.encounter)

          out = Acting.report
          out['lines'] << Telling.event('pf2e.companion_riding_mounted', :rider => rider.label, :mount => target.label)
          Acting.spend(scene, name, Actions.info(name), out)

          Ok.new(:state => out)
        end

        def self.mount_refusal(rider, target)
          npc = target.holder

          if companion?(rider.holder)
            return Err.new(:companion_rider, 'pf2e.companion_riding_companion_rider', 'rider' => rider.label)
          end

          if down?(npc)
            return Err.new(:mount_down, 'pf2e.companion_riding_down', 'mount' => target.label)
          end

          if (other = rider_row(npc))
            return Err.new(:already_ridden, 'pf2e.companion_riding_ridden', 'mount' => target.label, 'rider' => other['name'])
          end

          return nil if MonsterAbilities.size_of(npc) > MonsterAbilities.size_of(rider.holder)

          Err.new(:mount_too_small, 'pf2e.companion_riding_too_small', 'mount' => target.label, 'rider' => rider.label)
        end

        # Mount again, while mounted: off into an adjacent space.
        def self.dismount(scene, name, npc)
          out = Acting.report
          unseat!(npc, scene.actor.holder)
          out['lines'] << Telling.event('pf2e.companion_riding_dismounted', :rider => scene.actor.label, :mount => npc.name)
          Acting.spend(scene, name, Actions.info(name), out)

          Ok.new(:state => out)
        end

        # The companion carries nobody now. The record is written fresh, since a copy read before a hit would
        # put the hit back, and the copy in hand is cleared too so a later save of it agrees.
        def self.unseat!(npc, rider_holder)
          npc.rider = nil
          Pf2eNpc[npc.id]&.update(:rider => nil)
          ActiveEffects.named_on(rider_holder, EFFECT).each { |effect| ActiveEffects.remove(rider_holder, effect) } if rider_holder
        end

        # The rider falls off: told with `key`. Nothing where the companion carries nobody.
        def self.thrown(npc, key)
          row = rider_row(npc)
          return [] unless row

          unseat!(npc, Combatants.holder_of(row))
          [ Telling.event(key, :rider => row['name'], :mount => npc.name) ]
        end

        # A companion knocked out or killed throws its rider.
        def self.dropped(holder)
          return [] unless companion?(holder) && holder.rider

          fresh = Pf2eNpc[holder.id]
          return [] unless fresh && down?(fresh)

          holder.rider = nil
          thrown(fresh, 'pf2e.companion_riding_thrown')
        end

        # Combatants leaving the order, by id: a companion among them throws its rider, and a rider among them
        # is gone from their mount. Asked before they leave.
        def self.left!(encounter, ids)
          leaving = ids.map(&:to_i)
          lines = []

          Combatants.rows(encounter).each do |row|
            next unless row['master'] && row['npc']

            npc = Pf2eNpc[row['npc']]
            next unless npc && companion?(npc) && npc.rider

            if leaving.include?(npc.rider.to_i)
              npc.update(:rider => nil)
            elsif leaving.include?(row['id'].to_i)
              lines += thrown(npc, 'pf2e.companion_riding_left')
            end
          end

          lines
        end

        # ------------------------------------------------------------------------------
        # What a player is refused while riding

        # The rider's move actions other than Mount. `term` is the action as typed.
        def self.rider_refusal(combatant, term)
          mount = mount_of(combatant.holder)
          return nil unless mount

          name = action_name(term)
          return nil if name.nil? || name == MOUNT || !move?(name)

          Err.new(:rider_moves, 'pf2e.companion_riding_rider_moves', 'rider' => combatant.label, 'mount' => mount.name, 'action' => name)
        end

        # A ridden companion without the mount special: only its land Speed, and no move after it Supports.
        # Support after a move is already refused, as Support after any other action is (`Support.refusal`).
        def self.minion_refusal(npc, label, name)
          return nil if npc.stat_block['mount'] || !ridden?(npc)

          if OTHER_SPEEDS.include?(name)
            return Err.new(:ridden_land_only, 'pf2e.companion_riding_land_only', 'name' => label, 'action' => name)
          end

          return nil unless Support.supported?(npc) && move?(name)

          Err.new(:ridden_supported, 'pf2e.companion_riding_move_after_support', 'name' => label)
        end

        def self.action_name(term)
          typed = term.to_s.split('=').first.to_s.split('/').first.to_s.strip
          found = typed.empty? ? nil : Actions.find(typed)

          found&.ok? ? found.state : nil
        end

        def self.move?(name)
          Support::MOVES.include?(name) || Array(Actions.info(name)['traits']).map(&:to_s).include?('move')
        end

        # ------------------------------------------------------------------------------
        # Fighting as a unit

        # The attacks the holder's partner has made in the same turn, which count toward the holder's multiple
        # attack penalty: the rider's for the companion, the companion's for its rider. A companion acts on its
        # master's turn, so an ally riding it shares the penalty only with what it does on their turn.
        def self.shared_attacks(holder)
          partner = partner_of(holder)
          encounter = partner ? encounter_of(holder) : nil
          return 0 unless encounter

          own = row_of(encounter, holder)
          theirs = row_of(encounter, partner)
          return 0 unless own && theirs
          return 0 unless Combatants.turn_name(encounter, own['name']) == Combatants.turn_name(encounter, theirs['name'])

          TurnState.turn(partner)['attacks'].to_i
        end

        def self.partner_of(holder)
          return nil unless holder.respond_to?(:pf2_effects)

          if companion?(holder)
            row = holder.rider ? rider_row(holder) : nil
            return row ? Combatants.holder_of(row) : nil
          end

          mount_of(holder)
        end

        # ------------------------------------------------------------------------------
        # What riding adds

        # Fell Rider: a companion that Supports while its master rides it gives them the effects of a
        # successful Aid on their first Demoralize this turn, marked on their turn.
        def self.fell_rider!(use, npc, state)
          row = rider_row(npc)
          char = state.respond_to?(:character) ? state.character : nil
          return unless row && char && row['id'].to_i == use.actor.master.to_i && Pf2e.has_feat?(char, FELL_RIDER)

          TurnState.write(state, 'turn' => TurnState.turn(state).merge('fell_rider' => true))
          use.out['lines'] << Telling.event('pf2e.companion_riding_fell_rider', :name => use.actor.label, :rider => row['name'])
        end

        # The Aid Fell Rider gave, on the first Demoralize, which spends it.
        def self.fell_rider_aid(holder)
          return [] unless TurnState.turn(holder)['fell_rider']

          TurnState.write(holder, 'turn' => TurnState.turn(holder).merge('fell_rider' => false))
          [ { 'source' => FELL_RIDER, 'slug' => 'fell-rider', 'type' => 'circumstance', 'value' => 1 } ]
        end

        # A horse's support: on a supported melee Strike by its rider, who moved 10 feet or more on the action
        # before it (the word `moved`), a circumstance bonus to damage of twice the weapon's damage dice.
        def self.horse_charge(scene, attack, said)
          return attack unless attack['companion_support'] && !attack['ranged']

          npc = Support.supporting(scene.actor.holder)
          return attack unless npc && npc.stat_block['type'].to_s == 'Horse'
          return attack unless rides?(scene.actor.holder, npc) && said['words'].include?(Maneuvers::MOVED)

          bonus = { 'source' => 'Support: Horse', 'value' => 2 * WeaponTraits.dice(attack), 'damage_type' => nil, 'category' => nil,
                    'critical' => nil }
          attack.merge('bonus_damage' => Array(attack['bonus_damage']) + [ bonus ], 'horse_charge' => bonus['value'])
        end

        # Heal Mount: *lay on hands* on one's own companion restores 10 Hit Points plus 10 per heightened rank.
        def self.heal_mount(scene, spell, mechanics, target)
          return mechanics unless spell.to_s.casecmp?(LAY_ON_HANDS) && target && companion?(target.holder)
          return mechanics unless target.master.to_i == scene.actor.number.to_i

          caster = scene.actor.holder
          char = caster.respond_to?(:character) ? caster.character : nil
          healing = Array(mechanics['damage']).any? { |one| Array(one['kinds']).include?('healing') }
          return mechanics unless char && healing && Pf2e.has_feat?(char, HEAL_MOUNT)

          heightening = (mechanics['heightening'] || {}).merge('damage' => [ HEAL_MOUNT_HP ])
          mechanics.merge('damage' => mechanics['damage'].map { |one| one.merge('formula' => HEAL_MOUNT_HP) },
                          'heightening' => heightening)
        end

        # `riding Ash` beneath a rider, `ridden by Rowan` beneath a companion, in `e/view`.
        def self.view_line(holder)
          return nil if holder.nil?

          if companion?(holder)
            row = holder.rider ? rider_row(holder) : nil
            return row ? t('pf2e.view_ridden_by', :rider => row['name']) : nil
          end

          mount = mount_of(holder)
          mount ? t('pf2e.view_riding', :mount => mount.name) : nil
        end
      end
    end
  end
end
