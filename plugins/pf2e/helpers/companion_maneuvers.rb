module AresMUSH
  module Pf2e
    module Companion

      # A nimble or savage animal companion's advanced maneuver (Player Core pp. 207-211): one of its own
      # actions on its stat block, with the figures it needs written into its first line, run through
      # `MonsterAbilities` as a creature's ability is. Its Strikes move its multiple attack penalty on without
      # costing more actions. There is no map, so where it moves is told and its Strikes are made.
      #
      # A maneuver with no row here (Gallop) is announced with its words for its cost.
      module Maneuvers

        RAGE = 'Effect: Badger Rage'.freeze
        # A raging badger's additional damage, by attack.
        RAGE_DAMAGE = { 'Jaws' => 4, 'Claw' => 2 }.freeze
        # The word that says a boar moved the 20 feet its charge's bonus needs.
        MOVED = 'moved'.freeze

        # Its maneuver as an action on its stat block, or nil before it is nimble or savage.
        def self.action(stats, state)
          found = stats['maneuver']
          return nil unless found.is_a?(Hash)

          figures = figures(found['name'].to_s, stats, state)
          frequency = found['frequency'] ? "Frequency #{found['frequency']}%r" : ''

          { 'name' => found['name'], 'type' => 'action', 'cost' => found['actions'].to_i, 'traits' => Array(found['traits']),
            'text' => "#{figures}#{frequency}#{found['description']}" }
        end

        def self.specialized?(stats)
          Array(stats['specializations']).any?
        end

        # The first line `MonsterAbilities.header` reads its figures from, where it has some: Constrict's damage and
        # its master's class DC, Fire Breath's damage and DC.
        def self.figures(name, stats, state)
          case name
          when 'Constrict'
            dc = state&.combat ? Stat.total(state, 'class_dc').to_i : 10
            "#{specialized?(stats) ? 20 : 12} bludgeoning, DC #{dc} basic Fortitude%r"
          when 'Fire Breath'
            level = stats['level'].to_i
            rank = specialized?(stats) ? 4 : 2
            "#{[ level / 2, 1 ].max}d6 fire, DC #{10 + level + rank + stats['attributes']['Constitution'].to_i} basic Reflex%r"
          else ''
          end
        end

        # Throw Rock's rock, a Strike of its own: Dexterity for a ranged attack, 2d6 bludgeoning (3d6 once
        # specialized), range increment 30 feet.
        def self.rock(stats)
          return nil unless (stats['maneuver'] || {})['name'] == 'Throw Rock'

          bonus = Stats.bonus(Stats.rank_of(stats['ranks']['attack']), stats['level']) + stats['attributes']['Dexterity'].to_i
          { 'name' => 'Rock', 'bonus' => bonus, 'traits' => [], 'range' => 30,
            'damage' => [ [ "#{specialized?(stats) ? 3 : 2}d6", 'bludgeoning', nil ] ] }
        end

        # A raging badger's Strikes deal more (`Block.of`).
        def self.raging?(npc)
          Array(npc.pf2_effects).any? { |effect| effect.name == RAGE }
        end

        def self.row(name, holder)
          return nil unless holder && Actors.of(holder).minion_kind == 'companion'

          ROWS[Domains.slug(name)]
        end

        # ------------------------------------------------------------------------------------------------
        # What the rows share
        # ------------------------------------------------------------------------------------------------

        # Its most recent action, where that was a hit with this attack: `{ 'strike', 'target', 'hit' }`.
        def self.last_hit(use, attack)
          last = TurnState.turn(use.actor.holder)['last'] || {}
          last['hit'] && last['strike'].to_s.casecmp?(attack) ? last : nil
        end

        def self.needs_hit(attack)
          lambda do |use|
            next nil if last_hit(use, attack)

            Err.new(:maneuver_needs_hit, 'pf2e.companion_maneuver_needs_hit', 'name' => use.actor.label, 'maneuver' => use.name,
                                                                              'attack' => attack.downcase)
          end
        end

        def self.needs_target(use)
          use.targets.empty? ? use.needs_target : nil
        end

        def self.condition(use, target, one)
          Acting.condition_consequence(use.at(target), target, one, use.out)
        end

        def self.told(use, key, args = {})
          use.out['lines'] << Telling.event(key, { :name => use.actor.label }.merge(args))
        end

        # A Strike with one of its attacks after a move that's told: Cat Pounce, Darting Attack, Flyby Attack.
        # The attack is the one named among the words, or `attack`, or its first.
        def self.move_and_strike(move, attack = nil)
          {
            'refusal' => ->(use) { needs_target(use) },
            'run' => lambda do |use|
              chosen = Array(use.words).find { |word| Acting.attack_for(use.actor.holder, word) } || attack
              told(use, 'pf2e.companion_maneuver_moves', :move => move)
              use.strike(use.targets.first, chosen, false)
            end
          }
        end

        ROWS = {
          # Takedown: the target of its jaws hit falls prone.
          'takedown' => {
            'refusal' => needs_hit('Jaws'),
            'run' => ->(use) { condition(use, use.combatant(last_hit(use, 'Jaws')['target']), 'condition' => 'Prone') }
          },
          # Bear Hug: another claw Strike at the same creature, which a hit Grabs.
          'bear-hug' => {
            'refusal' => needs_hit('Claw'),
            'run' => lambda do |use|
              target = use.combatant(last_hit(use, 'Claw')['target'])
              condition(use, target, 'condition' => 'Grabbed') if use.strike(target, 'claw', false)
            end
          },
          # Shred: the target of its jaws hit takes 2d8 slashing, 3d8 once specialized.
          'shred' => {
            'refusal' => needs_hit('Jaws'),
            'run' => lambda do |use|
              target = use.combatant(last_hit(use, 'Jaws')['target'])
              formula = Maneuvers.specialized_block?(use) ? '3d8' : '2d8'
              thrown = Pf2e.thrown_formula(formula)
              Acting.deal(use.at(target), target, [ { 'amount' => thrown['total'], 'type' => 'slashing', 'formula' => formula,
                                                      'dice' => thrown['shown'] } ], use.out)
            end
          },
          # Constrict: a smaller creature it has Grabbed, as a creature's Constrict, at its master's class DC.
          'constrict' => {
            'several' => true,
            'refusal' => lambda do |use|
              held = MonsterAbilities::CONSTRICT['refusal'].call(use)
              next held if held

              bigger = use.held.find { |target| MonsterAbilities.size_of(target.holder) >= MonsterAbilities.size_of(use.actor.holder) }
              bigger ? Err.new(:constrict_too_big, 'pf2e.companion_constrict_too_big', 'name' => use.actor.label, 'target' => bigger.label) : nil
            end,
            'run' => ->(use) { MonsterAbilities::CONSTRICT['run'].call(use) }
          },
          # Fire Breath: a basic Reflex save for each creature in the cone, named.
          'fire-breath' => {
            'several' => true,
            'refusal' => ->(use) { needs_target(use) },
            'run' => ->(use) { use.targets.each { |target| use.save(target, use.header) } }
          },
          # Frightening Display: Demoralize with its Intimidation, needing no language.
          'frightening-display' => {
            'refusal' => ->(use) { needs_target(use) },
            'run' => lambda do |use|
              target = use.targets.first
              degree = use.check(target, 'Intimidation', 'will')
              value = { Degree::CRITICAL_SUCCESS => 2, Degree::SUCCESS => 1 }[degree]
              next unless value

              condition(use, target, 'condition' => 'Frightened', 'value' => value)
              told(use, 'pf2e.companion_maneuver_display', :target => target.label)
            end
          },
          # Death Roll: a jaws Strike at +2 at the creature it has Grabbed, which a hit knocks prone and a miss
          # lets go.
          'death-roll' => {
            'refusal' => ->(use) { use.held.empty? ? use.holds_nobody : nil },
            'run' => lambda do |use|
              target = use.held.first

              if use.strike(target, 'jaws', false, :bonus => { 'source' => use.name, 'value' => 2 })
                condition(use, target, 'condition' => 'Prone')
              else
                Holding.let_go(use.scene.encounter, use.actor.label)
                told(use, 'pf2e.companion_maneuver_released', :target => target.label)
              end
            end
          },
          # Grab and Sting: a pincer Strike, which a hit Grabs until the end of its master's next turn, then a
          # stinger Strike at the creature it Grabbed.
          'grab-and-sting' => {
            'refusal' => ->(use) { needs_target(use) },
            'run' => lambda do |use|
              target = use.targets.first
              next unless use.strike(target, 'pincer', false)

              condition(use, target, 'condition' => 'Grabbed', 'until' => 'next-turn-end')
              use.strike(target, 'stinger', false)
            end
          },
          # Wing Thrash: a wing Strike at each of up to three foes, the penalty moving on once they are all made.
          'wing-thrash' => {
            'several' => true,
            'refusal' => lambda do |use|
              next use.needs_target if use.targets.empty?

              use.targets.size > 3 ? Err.new(:too_many_targets, 'pf2e.act_too_many_targets', 'action' => use.name, 'most' => 3) : nil
            end,
            'run' => lambda do |use|
              made = TurnState.turn(use.actor.holder)['attacks'].to_i

              use.targets.each do |target|
                use.strike(target, 'wing', false)
                TurnState.attacks_at(use.actor.holder, made)
              end

              TurnState.attacks_at(use.actor.holder, made + use.targets.size)
            end
          },
          'cat-pounce' => move_and_strike('Stride'),
          'darting-attack' => move_and_strike('Step'),
          'flyby-attack' => move_and_strike('Fly', 'talon'),
          # Boar Charge: a tusk Strike after two Strides, at +2 where its player says it moved 20 feet.
          'boar-charge' => {
            'refusal' => ->(use) { needs_target(use) },
            'run' => lambda do |use|
              moved = Array(use.words).include?(MOVED)
              told(use, 'pf2e.companion_maneuver_moves', :move => 'Stride twice')
              use.strike(use.targets.first, 'tusk', false, :bonus => moved ? { 'source' => use.name, 'value' => 2 } : nil)
            end
          },
          # Throw Rock: the rock Strike on its stat block.
          'throw-rock' => {
            'refusal' => ->(use) { MonsterAbilities::THROW_ROCK['refusal'].call(use) },
            'run' => ->(use) { use.strike(use.targets.first, 'rock', false) }
          },
          # Badger Rage: the effect on itself for 1 minute, its extra damage on its stat block (`Block.of`).
          'badger-rage' => {
            'refusal' => lambda do |use|
              npc = use.actor.holder
              held = Pf2e.held_conditions(npc)
              next nil unless held.key?('Fatigued') || raging?(npc)

              Err.new(:badger_cannot_rage, 'pf2e.companion_badger_cannot_rage', 'name' => use.actor.label)
            end,
            'run' => lambda do |use|
              ActiveEffects.apply(use.actor.holder, RAGE, :applied_by => use.actor.label, :encounter => use.scene.encounter)
              told(use, 'pf2e.companion_badger_rages')
            end
          }
        }.freeze

        # A specialized companion's maneuver, read off its stat block.
        def self.specialized_block?(use)
          use.actor.holder.stat_block['specialized'] == true
        end
      end
    end
  end
end
