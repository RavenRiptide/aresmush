module AresMUSH
  module Pf2e
    module Familiar

      # Witch feats that give the familiar an activity of its own (Player Core):
      #
      #   Shed Spirit        Spirit Familiar, 8th: spirit damage to an enemy, basic Will; an ally it names
      #                      regains half the damage that landed
      #   Stitching Strike   Stitched Familiar, 8th: slashing damage, basic Reflex; a target that fails is
      #                      immobilized for 1 round, or until it Escapes against the same DC
      #   Patron's Claim     18th: spirit damage, basic Fortitude; a target that fails and takes damage is
      #                      drained 2 (4 on a critical failure), and the master regains a Focus Point
      #
      # Each feat carries a `familiar_action:`, written as a bestiary action, which `Familiar::Block` puts on
      # the familiar's stat block with its name, its master's spell DC and the dice at its master's level
      # filled in. The familiar uses it on its master's turn as any of its own abilities (`e/as <familiar>=act
      # shed spirit=<enemy>,<ally>`), and a row in `MonsterAbilities` runs it.
      module Activities

        SHED_SPIRIT = 'Shed Spirit'.freeze
        STITCHING_STRIKE = 'Stitching Strike'.freeze
        PATRONS_CLAIM = "Patron's Claim".freeze

        # The stat block's entries: what the master's feats give, filled in for this familiar.
        def self.actions(npc, state)
          given(state).map do |one|
            one.reject { |key, _| %w{damage summary}.include?(key) }.merge('text' => filled(one['text'], one, npc.name, state))
          end
        end

        # A line for each on the familiar's sheet: its name and what it does, with its master's figures.
        def self.sheet_lines(master, name)
          given(master).map { |one| "#{one['name']}: #{filled(one['summary'], one, name, master)}" }
        end

        # Filled by name, since the text's `%r` line breaks are no format directives.
        def self.filled(text, one, name, master)
          fills = { '%{name}' => name.to_s, '%{dc}' => spell_dc(master).to_s, '%{damage}' => damage(one['damage'], master.pf2_level.to_i) }

          text.to_s.gsub(/%\{(?:name|dc|damage)\}/, fills)
        end

        # The `familiar_action:` of each feat the master holds.
        def self.given(holder)
          return [] unless holder.respond_to?(:pf2_feats)

          Pf2e.held_feat_details(holder).filter_map { |_name, details| details.is_a?(Hash) ? details['familiar_action'] : nil }
        end

        # Whether the master's feats give their familiar this activity, by name.
        def self.given?(holder, name)
          given(holder).any? { |one| one['name'].to_s.casecmp?(name.to_s) }
        end

        # The dice at a level: a fixed formula, or `{ base, from, every, add }` - `add` more dice of the base's
        # size at `from` and every `every` levels after it.
        def self.damage(spec, level)
          return spec.to_s unless spec.is_a?(Hash)

          count, size = spec['base'].to_s.split('d').map(&:to_i)
          from = spec['from'].to_i
          steps = level >= from ? (level - from) / [ spec['every'].to_i, 1 ].max + 1 : 0

          "#{count + steps * spec['add'].to_i}d#{size}"
        end

        # The master's best spell DC as they stand in the encounter. The activities ask for "your spell DC",
        # not the class DC.
        def self.spell_dc(state)
          entries = state.magic ? Pf2emagic::Entries.casting(state.magic) : []

          entries.filter_map do |entry|
            stats = Pf2emagic.get_caster_stats(state, entry['name'])
            stats.is_a?(Hash) ? Acting.spell_figure(state, 'spell_dc', stats) : nil
          end.max.to_i
        end

        # ------------------------------------------------------------------------------
        # Using them (`MonsterAbilities` rows)

        # One enemy, and for Shed Spirit an ally after it.
        def self.refusal(use)
          return use.needs_target if use.targets.empty?

          most = use.name == SHED_SPIRIT ? 2 : 1
          return nil if use.targets.size <= most

          Err.new(:familiar_activity_targets, 'pf2e.familiar_activity_targets', 'action' => use.name, 'most' => most)
        end

        def self.run(use)
          target = use.targets.first
          degree = use.save(target, use.header)
          return unless degree

          landed = landed(use, target)

          case use.name
          when SHED_SPIRIT then shed_spirit(use, use.targets[1], landed)
          when STITCHING_STRIKE then stitch(use, target, degree)
          when PATRONS_CLAIM then claim(use, target, degree, landed)
          end
        end

        # What the save's damage took off the target (`Acting.deal`).
        def self.landed(use, target)
          (use.out['taken'] || {})[target.label].to_i
        end

        # The ally it names regains half of what landed.
        def self.shed_spirit(use, ally, landed)
          return unless landed.positive?
          return use.out['lines'] << Telling.event('pf2e.familiar_shed_spirit_no_ally', :name => use.actor.label) unless ally

          amount = Harm.heal(ally.holder, landed / 2)
          use.out['lines'] << Acting.healed(ally.label, amount, nil)
          use.out['gm'] << Telling.event('pf2e.act_hp_left', 'target' => ally.label, 'hp' => Harm.hit_points(ally.holder))
        end

        # Immobilized for a round, escaped from at the activity's DC.
        def self.stitch(use, target, degree)
          return unless degree <= Degree::FAILURE

          Acting.condition_consequence(use.at(target), target, { 'condition' => 'Immobilized', 'until' => 'rounds:1' }, use.out)
          Acting.note_on(target.holder, 'Immobilized', 'escape_dc' => use.header['dc'])
        end

        # Drained, and a Focus Point for the master, where the target failed and took damage.
        def self.claim(use, target, degree, landed)
          return unless degree <= Degree::FAILURE && landed.positive?

          drained = degree == Degree::CRITICAL_FAILURE ? 4 : 2
          Acting.condition_consequence(use.at(target), target, { 'condition' => 'Drained', 'value' => drained }, use.out)

          state = use.actor.holder.master
          return unless state&.magic && Pf2emagic.focus_pool_max(state.magic).positive?

          master = MasterActions.master_label(use)
          now = MasterActions.regain_focus(state)
          use.out['lines'] << Telling.event('pf2e.familiar_focus_restored', :master => master, :current => now,
                                                                            :max => Pf2emagic.focus_pool_max(state.magic))
        end

        # ------------------------------------------------------------------------------
        # The master

        # A master naming the activity as their own: it is their familiar's, used through `e/as`.
        def self.master_refusal(holder, name)
          return nil unless given?(holder, name)

          Err.new(:familiar_activity_own, 'pf2e.familiar_activity_own', 'action' => name)
        end

        # What `e/how` tells a master about each: its name, the command, and what its targets are.
        def self.how(holder)
          given(holder).flat_map do |one|
            name = one['name'].to_s

            case name
            when SHED_SPIRIT
              [ { 'name' => name, 'command' => "+e/as <familiar>=act #{name.downcase}=<enemy>,<ally>",
                  'about' => t('pf2e.familiar_activity_how_shed', :action => name) } ]
            when Presence::NAME
              [ { 'name' => name, 'command' => "+e/as <familiar>=act #{name.downcase}", 'about' => t('pf2e.familiar_presence_how') },
                { 'name' => name, 'command' => "+e/as <familiar>=enter #{name.downcase}=<enemy>,<enemy>",
                  'about' => t('pf2e.familiar_presence_how_enter') } ]
            else
              [ { 'name' => name, 'command' => "+e/as <familiar>=act #{name.downcase}=<target>",
                  'about' => t('pf2e.familiar_activity_how', :action => name) } ]
            end
          end
        end
      end
    end
  end
end
