module AresMUSH
  module Pf2e

    # What a property rune lets its wearer do. A rune etched on worn armor or a wielded weapon gives the
    # wearer an action from the catalogue (`pf2e_actions.yml`), used like any other with `+e/act`.
    #
    # Each row names the action, where the rune has to be (`on`), how the action runs (`run`), and what
    # each grade of the rune changes about it. The grades are listed weakest first, and the strongest the
    # wearer has is the one that counts: greater invisibility's three uses a day over invisibility's one.
    #
    #   effect      puts an effect on the wearer: the grade's `effect`, or the one they choose from `choices`
    #   announce    tells the room, and `told` says what changes
    #   strike      Strikes with the weapon carrying the rune, as the catalogue's `strikes` says
    #   counteract  rolls a counteract check with the grade's `modifier` and `rank`
    #   answer      a reaction to the wearer's own last Strike, when `trigger` says it qualifies
    module RuneActions

      ROWS = {
        'Change Size' => {
          'on' => 'armor', 'run' => 'effect', 'runes' => { 'size-changing' => {} },
          'choices' => { 'enlarge' => 'Spell Effect: Enlarge', 'shrink' => 'Spell Effect: Shrink' }
        },
        'Go Invisible' => {
          'on' => 'armor', 'run' => 'effect',
          'runes' => { 'invisibility' => { 'effect' => 'Effect: Invisibility Rune' },
                       'greater-invisibility' => { 'effect' => 'Effect: Invisibility Rune',
                                                   'frequency' => { 'max' => 3, 'per' => 'day' } } }
        },
        'Take to the Skies' => {
          'on' => 'armor', 'run' => 'effect',
          'runes' => { 'winged' => { 'effect' => 'Effect: Winged Rune' },
                       'greater-winged' => { 'effect' => 'Effect: Winged Rune (Greater)', 'frequency' => nil } }
        },
        'Costume Change' => {
          'on' => 'armor', 'run' => 'announce', 'runes' => { 'raiment' => {} }, 'told' => 'pf2e.rune_costume_change'
        },
        'Extend' => {
          'on' => 'weapons', 'run' => 'strike',
          'runes' => { 'extending' => { 'reach' => 60 }, 'greater-extending' => { 'reach' => 120 } }
        },
        'Shine Bright' => {
          'on' => 'weapons', 'run' => 'counteract',
          'runes' => { 'brilliant' => { 'modifier' => 19, 'rank' => 5 }, 'greater-brilliant' => { 'modifier' => 31, 'rank' => 9 } }
        },
        'Holy Healing' => {
          'on' => 'weapons', 'run' => 'answer', 'runes' => { 'holy' => {} }, 'trigger' => 'critical_against_unholy'
        },
        'Unholy Bloodshed' => {
          'on' => 'weapons', 'run' => 'answer', 'runes' => { 'unholy' => {} }, 'trigger' => 'critical_against_holy'
        },
        'Snicker-Snack' => {
          'on' => 'weapons', 'run' => 'answer', 'runes' => { 'vorpal' => {} }, 'trigger' => 'natural_twenty_slashing'
        }
      }.freeze

      # What qualifies the wearer's last Strike for each reaction: what it rolled, with the weapon carrying
      # the rune, and against whom.
      TRIGGERS = {
        'critical_against_unholy' => ->(last, target) { last['degree'] == Degree::CRITICAL_SUCCESS && RuneActions.trait?(target, 'unholy') },
        'critical_against_holy' => ->(last, target) { last['degree'] == Degree::CRITICAL_SUCCESS && RuneActions.trait?(target, 'holy') },
        'natural_twenty_slashing' => ->(last, _target) {
          last['degree'] == Degree::CRITICAL_SUCCESS && last['die'].to_i == 20 && last['damage_type'] == 'slashing'
        }
      }.freeze

      # How each kind of activation runs, once the action has been found to be theirs.
      RUNS = {
        'effect' => ->(scene, name, entry, said, out) { RuneActions.put_on(scene, name, entry, said, out) },
        'announce' => ->(scene, name, _entry, _said, out) { RuneActions.announced(scene, name, out) },
        'counteract' => ->(scene, name, _entry, said, out) { RuneActions.counteracted(scene, name, said, out) },
        'answer' => ->(scene, name, _entry, _said, out) { RuneActions.answered(scene, name, out) }
      }.freeze

      # A vorpal rune's level, which is what its incapacitation is measured against.
      VORPAL_LEVEL = 17
      Source = Struct.new(:pf2_level)

      def self.row(name)
        ROWS[name]
      end

      def self.action?(name)
        ROWS.key?(name)
      end

      # Whether `Acting` hands the action here to run. A Strike runs as the catalogue's other Strike
      # actions do, with only the weapon carrying the rune allowed.
      def self.runs?(name)
        action?(name) && RUNS.key?(ROWS[name]['run'])
      end

      # ------------------------------------------------------------------------------
      # Whose it is

      # The armor they wear, or the weapons they wield, carrying any grade of the rune. A creature carries
      # nothing, so it has none.
      def self.carriers(holder, name)
        found = row(name)

        collection = found && Pf2egear::Inventory.row(found['on'])['collection']

        return [] unless collection && holder.respond_to?(collection) && Actors.of(holder).carries_items?

        Pf2egear::Inventory.held(holder, found['on']).select(&:equipped).select do |item|
          (Pf2egear.property_runes(item) & found['runes'].keys).any?
        end
      end

      def self.grants?(holder, name)
        carriers(holder, name).any?
      end

      # The activations an item's runes give, worn or not: what `use` points someone at.
      def self.given_by(category, item)
        slugs = Pf2egear.property_runes(item)

        ROWS.select { |_name, found| Pf2egear::Inventory.canonical(category) == found['on'] && (slugs & found['runes'].keys).any? }.keys
      end

      # The strongest grade of the rune they carry, and what it changes: `[ slug, changes ]`, or nil.
      def self.grade(holder, name)
        held = carriers(holder, name).flat_map { |item| Pf2egear.property_runes(item) }
        slug = row(name)['runes'].keys.reverse.find { |one| held.include?(one) }

        slug ? [ slug, row(name)['runes'][slug] ] : nil
      end

      # The catalogue entry as the grade they carry changes it: a greater rune's uses a day.
      def self.entry(holder, name, entry)
        found = action?(name) ? grade(holder, name) : nil

        return entry unless found

        changes = found.last

        changes.key?('frequency') ? entry.merge('frequency' => changes['frequency']).compact : entry
      end

      # Why someone without the rune can't use it.
      def self.refusal(name)
        found = row(name)
        runes = found['runes'].keys.map { |slug| slug.tr('-', ' ') }.join(' or ')

        Err.new(:no_rune, 'pf2e.rune_action_not_yours', 'action' => name, 'runes' => runes,
                'item' => found['on'] == 'armor' ? 'armor you wear' : 'a weapon you wield')
      end

      # ------------------------------------------------------------------------------
      # Using it

      # Runs the action, adding what happened to `out`. Answers an Err where it can't be done, before
      # anything has changed.
      def self.act(scene, name, entry, said, out)
        RUNS.fetch(row(name)['run']).call(scene, name, entry, said, out)
      end

      def self.put_on(scene, name, entry, said, out)
        holder = scene.actor.holder
        found = row(name)
        effect = grade(holder, name).last['effect']

        if found['choices']
          chosen = said['words'].find { |word| found['choices'].key?(word) }

          return Err.new(:choose, 'pf2e.rune_choose', 'action' => name, 'choices' => found['choices'].keys.join(' or '),
                         'command' => "#{Domains.slug(name).tr('-', ' ')}/#{found['choices'].keys.first}") unless chosen

          effect = found['choices'][chosen]
        end

        applied = ActiveEffects.apply(holder, effect, :applied_by => scene.actor.label, :encounter => scene.encounter,
                                                      :origin => Acting.action_origin(scene, name, entry))

        return applied if applied.err?

        out['lines'] << Telling.event('pf2e.act_self_effect', :actor => scene.actor.label, :action => name,
                                                             :cost => Actions.cost(name), :effect => applied.state.name,
                                                             :lasts => ActiveEffects.remaining(applied.state))
        nil
      end

      def self.announced(scene, name, out)
        out['lines'] << Telling.event('pf2e.act_announced', :actor => scene.actor.label, :action => name,
                                                           :cost => Actions.cost(name), :target => '')
        out['lines'] << Telling.event(row(name)['told'], :actor => scene.actor.label)
        nil
      end

      # A counteract check against the DC said after the action's name. It says the highest rank it ends,
      # or with the effect's rank said too, whether it ends it.
      def self.counteracted(scene, name, said, out)
        return Err.new(:needs_dc, 'pf2e.rune_needs_dc', 'action' => name, 'command' => name.downcase) unless said['dc']

        changes = grade(scene.actor.holder, name).last
        rolled = Counteract.roll(changes['modifier'], said['dc'])

        out['lines'] << Telling.event('pf2e.act_announced', :actor => scene.actor.label, :action => name,
                                                           :cost => Actions.cost(name), :target => '')
        out['lines'] << Telling.event('pf2e.rune_counteract_roll', :die => rolled['die'], :modifier => changes['modifier'],
                                                                  :total => rolled['total'], :rank => changes['rank'])
        out['lines'] << counteract_outcome(changes['rank'], rolled, said['rank'])
        nil
      end

      def self.counteract_outcome(rank, rolled, target_rank)
        degree = Telling.degree(rolled['degree'], false)
        top = Counteract.highest(rank, rolled['degree'])

        return Telling.event('pf2e.rune_counteract_nothing', :dc => rolled['dc'], :degree => degree) unless top

        if target_rank
          ended = Counteract.ends?(rank, rolled['degree'], target_rank)

          return Telling.event(ended ? 'pf2e.rune_counteract_ends' : 'pf2e.rune_counteract_holds',
                               :dc => rolled['dc'], :degree => degree, :rank => target_rank)
        end

        Telling.event('pf2e.rune_counteract_up_to', :dc => rolled['dc'], :degree => degree, :top => top)
      end

      # ------------------------------------------------------------------------------
      # Strikes

      # Only the weapons carrying the rune may make an activation's Strike.
      def self.strike_with(holder, name, usable)
        return usable unless action?(name)

        ids = carriers(holder, name).map { |item| item.id.to_s }

        usable.select { |_names, attack| ids.include?(attack['id'].to_s) }
      end

      # What the room is told before the Strike: an extending rune's reach.
      def self.before_strike(scene, name, out)
        return unless action?(name) && row(name)['run'] == 'strike'

        reach = grade(scene.actor.holder, name).last['reach']

        out['lines'] << Telling.event('pf2e.rune_extend_reach', :actor => scene.actor.label, :reach => reach) if reach
      end

      # ------------------------------------------------------------------------------
      # Reactions to the wearer's own Strike

      def self.trait?(combatant, trait)
        Effects.facts(combatant.holder).include?("self:trait:#{trait}")
      end

      # The wearer's last Strike, and whom it was against, where it qualifies for this reaction. Answers an
      # Err saying why not.
      def self.triggered(scene, name)
        last = TurnState.turn(scene.actor.holder)['last']
        slugs = row(name)['runes'].keys

        unless last && (Array(last['runes']) & slugs).any? && scene.encounter
          return Err.new(:no_trigger, 'pf2e.rune_no_trigger', 'action' => name)
        end

        return Err.new(:answered, 'pf2e.rune_answered', 'action' => name) if Array(last['answered']).include?(name)

        target = Combatants.find(scene.encounter, "##{last['number']}")

        return Err.new(:no_trigger, 'pf2e.rune_no_trigger', 'action' => name) unless target.ok?
        return Err.new(:no_trigger, 'pf2e.rune_no_trigger', 'action' => name) unless TRIGGERS.fetch(row(name)['trigger']).call(last, target.state)

        Ok.new(:state => [ last, target.state ])
      end

      ANSWERS = {
        'Holy Healing' => ->(scene, _last, target, out) { RuneActions.holy_healing(scene, target, out) },
        'Unholy Bloodshed' => ->(scene, last, target, out) { RuneActions.unholy_bloodshed(scene, last, target, out) },
        'Snicker-Snack' => ->(scene, _last, target, out) { RuneActions.snicker_snack(scene, target, out) }
      }.freeze

      def self.answered(scene, name, out)
        found = triggered(scene, name)

        return found if found.err?

        last, target = found.state

        out['lines'] << Telling.event('pf2e.act_announced', :actor => scene.actor.label, :action => name, :cost => Actions.cost(name),
                                                           :target => Telling.event('pf2e.act_at', :target => target.label))
        ANSWERS.fetch(name).call(scene, last, target, out)

        turn = TurnState.turn(scene.actor.holder)
        TurnState.write(scene.actor.holder, 'turn' => turn.merge('last' => last.merge('answered' => Array(last['answered']) + [ name ])))
        nil
      end

      # Hit points equal to double the unholy creature's level.
      def self.holy_healing(scene, target, out)
        amount = 2 * target.holder.pf2_level.to_i
        healed = Harm.heal(scene.actor.holder, amount, [ 'item:trait:healing', 'item:trait:vitality' ])

        out['lines'] << Telling.event('pf2e.rune_holy_healing', :actor => scene.actor.label, :amount => healed)
      end

      # Persistent bleed damage, 1d8 for each of the weapon's damage dice.
      def self.unholy_bloodshed(scene, last, target, out)
        dice = [ last['dice'].to_i, 1 ].max
        Acting.deal(scene, target, [ { 'amount' => 0, 'formula' => "#{dice}d8", 'type' => 'bleed', 'category' => 'persistent' } ], out)
      end

      # A DC 37 Fortitude save, or the target is decapitated. Incapacitation spares one above the rune's level.
      def self.snicker_snack(scene, target, out)
        traits = %w{concentrate death incapacitation}
        spared = Incapacitation.spares?(traits, target.holder, :source => Source.new(VORPAL_LEVEL))
        check = Check.of(target.holder, 'save', 'fortitude', traits.map { |one| "item:trait:#{one}" })
        result = Resolve.roll(check, :dc => 37, :shift => Incapacitation.shift(spared, :theirs))

        out['lines'] << Telling.event('pf2e.act_save_line', :target => target.label, :save => 'Fortitude',
                                                           :roll => Telling.roll(result), :dc => 37,
                                                           :degree => Telling.degree(result['degree'], false))
        out['lines'] << Telling.event('pf2e.act_incapacitation', :target => target.label) if spared

        return if Degree.success?(result['degree'])

        Actors.of(target.holder).slay!
        out['lines'] << Telling.event('pf2e.rune_decapitated', :target => target.label)
      end

      # After a Strike: the reactions it lets the striker use, offered.
      def self.offers(scene, out)
        holder = scene.actor.holder

        return unless scene.encounter && Actors.of(holder).carries_items?
        # Every one of them answers a critical hit.
        return unless TurnState.turn(holder).dig('last', 'degree') == Degree::CRITICAL_SUCCESS

        ROWS.each do |name, found|
          next unless found['run'] == 'answer' && grants?(holder, name) && triggered(scene, name).ok?

          out['lines'] << Telling.event('pf2e.act_follow_up', :effect => name, :command => "e/act #{name.downcase}")
        end
      end
    end
  end
end
