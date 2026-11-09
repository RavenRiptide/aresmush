module AresMUSH
  module Pf2e

    # An egalrin feather fan's Wave Fan activation: cast one of the spells the fan holds, at the rank it holds
    # it, or an innate cantrip without spending a use. The fan holds Gust of Wind, and Wind God's Fan and
    # Thunder God's Fan each add a spell and an activation a day, to at most three (`BoundItems.holds`).
    #
    # The spell's DC is the higher of their class DC and their spell DC, so a fighter casts at their class DC.
    # The fan's spells aren't limited to the caster's spell lists. The fan is primal.
    #
    # The game doesn't record which feat gave an innate cantrip, so any innate cantrip counts as one gained
    # from a heritage or an ancestry feat.
    #
    # It's used as other items are: `e/use magicitem=<n>[/<who>][/<spell>][/<word>...]`. The spell can be
    # left out where the fan holds only one.
    module WaveFan

      TRADITION = 'primal'.freeze

      def self.fan?(item)
        return false unless item.is_a?(PF2MagicItem) && BoundItems.bound?(item)

        info = Global.read_config(Pf2egear::Inventory.config('magicitem'), item.name.to_s)

        info.is_a?(Hash) && info['holds'].is_a?(Hash)
      end

      def self.held(holder, item)
        BoundItems.holds(holder, item) || { 'spells' => [], 'activations' => 0 }
      end

      def self.left(holder, item)
        [ held(holder, item)['activations'].to_i - item.activations_used.to_i, 0 ].max
      end

      # Their innate cantrips, by name.
      def self.cantrips(holder)
        Pf2emagic::Entries.innate_grants(holder.magic).select { |grant|
          grant['level'].to_s.casecmp?('cantrip') || grant['level'].to_s.to_i.zero?
        }.map { |grant| grant['name'].to_s }.reject { |name| name.casecmp?('open') }.uniq
      end

      # What the words ask it to cast: the first word naming a spell it holds or an innate cantrip, or the
      # only spell it holds when none is named. Answers { spell, rank, cantrip, words } with the rest of the
      # words for the spell itself.
      def self.chosen(holder, item, words)
        spells = held(holder, item)['spells']
        cantrips = cantrips(holder)
        at = Array(words).index do |word|
          spells.any? { |one| one['name'].to_s.casecmp?(word) } || cantrips.any? { |one| one.casecmp?(word) }
        end

        if at
          word = words[at]
          rest = words.reject.with_index { |_one, index| index == at }
          spell = spells.find { |one| one['name'].to_s.casecmp?(word) }

          return Ok.new(:state => { 'spell' => spell['name'], 'rank' => spell['rank'].to_i, 'cantrip' => false, 'words' => rest }) if spell

          named = cantrips.find { |one| one.casecmp?(word) }

          return Ok.new(:state => { 'spell' => named, 'rank' => nil, 'cantrip' => true, 'words' => rest })
        end

        if spells.size == 1
          return Ok.new(:state => { 'spell' => spells.first['name'], 'rank' => spells.first['rank'].to_i, 'cantrip' => false,
                                    'words' => Array(words) })
        end

        Err.new(:which, 'pf2e.wave_fan_which', 'item' => item.name,
                'spells' => (spells.map { |one| one['name'] } + cantrips).join(', '))
      end

      # The casting it's cast with: the higher of their class DC and their spell DC. Class DC and spell DC are
      # the same arithmetic over a proficiency and an attribute, so the class's are handed to the casting
      # engine as though they were a caster's.
      def self.casting(holder)
        classed = { 'tradition' => TRADITION, 'prof_level' => Stat.class_proficiency(holder, nil),
                    'spell_abil' => Stat.class_attribute(holder, nil) }

        options = [ classed ] + Pf2emagic::Entries.casting(holder.magic).filter_map do |entry|
          stats = Pf2emagic.get_caster_stats(holder, entry['name'])
          stats.is_a?(Hash) ? stats.merge('tradition' => TRADITION) : nil
        end

        options.max_by { |one| Acting.spell_figure(holder, 'spell_dc', one).to_i }
      end

      # Outside an encounter: the room is told. Nothing is counted, as for a wand.
      def self.use_outside!(holder, item, words)
        chosen(holder, item, words)
      end

      def self.cast!(scene, item, targets, words)
        holder = scene.actor.holder
        picked = chosen(holder, item, words)

        return picked if picked.err?

        choice = picked.state

        return Err.new(:spent, 'pf2e.wave_fan_spent', 'item' => item.name) if !choice['cantrip'] && left(holder, item).zero?

        spell = choice['spell']
        said = choice['words']
        before = [ Acting.way_needed(spell, said), Acting.casting_refused(scene, spell, said),
                   Acting.item_needed(scene, spell, targets, said) ].find { |one| one&.err? }

        return before if before

        cast = casting(holder).merge('spell name' => spell)
        cast['spell level'] = choice['rank'].to_s if choice['rank']
        risked = Acting.casting_risked(scene, spell)

        done = if risked && !risked['kept']
                 Acting.casting_lost(scene, spell, risked, cast)
               else
                 Acting.cast(scene, spell, targets, said, :cast => cast, :noted => risked ? risked['lines'] : [])
               end

        return done if done.err?

        item.update(:activations_used => item.activations_used.to_i + 1) unless choice['cantrip']

        done
      end

      # A rest gives the fan its day back.
      def self.rested!(holder)
        return unless Actors.of(holder).carries_items?

        Pf2egear::Inventory.all(holder, 'magicitem').select { |one| one.activations_used.to_i.positive? }
                           .each { |one| one.update(:activations_used => 0) }
      end
    end
  end
end
