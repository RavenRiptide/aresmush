module AresMUSH
  module Pf2e

    # An aura: an emanation around a character that puts effects on whoever is inside it - a champion's
    # aura on their allies, Silence on everyone.
    #
    # Foundry's `Aura` (`rule-element/aura.ts`) knows where everyone stands and applies its effects as
    # creatures enter and leave. This engine has no positions, so it cannot know who is inside; what it
    # can know is everything else. `Auras.of` says what auras a character projects and what each would do,
    # and `enter` and `leave` apply and end those effects on someone a DM says is inside or has left -
    # following the aura's own terms for whom it affects. When the aura itself ends, everything it put on
    # anyone ends with it.
    module Auras

      # Whom an aura's effect reaches, by how the one inside stands to the one projecting it.
      AFFECTS = { 'allies' => %w{ally}, 'enemies' => %w{enemy}, 'all' => %w{ally enemy} }.freeze

      # Every aura the character or creature projects: its slug, its radius, and the effects it puts on
      # others. An effect it is under can project one - Silence - and so can what it has of its own, which
      # lasts as long as it does: a creature's abilities, a character's feats and class features.
      #
      # Each carries the encounter and rank its effects are applied with: an effect's own, or for what is
      # its own, its encounter and level.
      #
      # Rows sharing a slug are one aura carrying all their effects, as in Foundry: Champion's Aura is the
      # aura, and Aura of Courage adds what it does to allies inside.
      def self.of(char)
        (from_effects(char) + from_abilities(char)).group_by { |aura| aura['slug'] }.map do |_slug, rows|
          rows.first.merge('radius' => rows.map { |one| one['radius'] }.max,
                           'traits' => rows.flat_map { |one| one['traits'] }.uniq,
                           'effects' => rows.flat_map { |one| one['effects'] })
        end
      end

      def self.from_effects(char)
        ActiveEffects.on(char).flat_map do |effect|
          item = ActiveEffects.instance_item(effect)

          read(char, effect.name, ActiveEffects.info(effect.name)['rules'], item)
            .map { |aura| aura.merge('effect' => effect, 'encounter' => effect.encounter, 'level' => effect.level) }
        end
      end

      def self.from_abilities(char)
        actor = Actors.of(char)

        actor.ability_sources.flat_map do |source|
          read(char, source['name'], source['rules'], source['item'])
            .map { |aura| aura.merge('effect' => nil, 'encounter' => actor.encounter, 'level' => char.pf2_level) }
        end
      end

      # A predicate may ask for an option the emitter has switched on: Champion's Aura's own toggle.
      def self.read(char, name, rules, item)
        options = Effects.options(char)
        context = Effects.context(char)

        Array(rules).select { |row| row['key'] == 'Aura' }.map do |row|
          row = Rules.resolved(row, Effects.source(name, [], 'item' => item), context)

          next nil unless row && Predicate.test(row['predicate'], options)

          { 'slug' => row['slug'] || Domains.slug(name),
            'radius' => Formula.value(row['radius'] || 0, context.merge('item' => item)).to_i,
            'traits' => Array(row['traits']),
            'effects' => Array(row['effects']).map { |one| reach(one) }.compact }
        end.compact
      end

      def self.reach(one)
        catalogue, name = Grants.target(one['uuid'])

        return nil unless catalogue == 'effects' && ActiveEffects.catalogue.key?(name)

        { 'name' => name, 'affects' => (one['affects'] || 'all').to_s, 'self' => one['includesSelf'] != false,
          'predicate' => one['predicate'], 'leaves_on_exit' => one['removeOnExit'] != false, 'save' => one['save'] }
      end

      # The origin an effect records when an aura put it there, so the aura can find it again.
      def self.origin(emitter, aura)
        "#{Pf2e.holder_key(emitter)}:#{aura['slug']}"
      end

      # Someone is inside one of the emitter's auras. `relation` is `ally` or `enemy`; the emitter
      # themselves is inside their own aura, and only an effect that includes its emitter reaches them.
      #
      # An effect with a `save` lands only if the one inside fails that save against the emitter's spell
      # DC (Eternal Bane's bane). The roll comes back as a message.
      def self.enter(emitter, target, slug, relation = 'ally')
        aura = of(emitter).find { |one| one['slug'] == slug }

        return Err.new(:no_aura, 'pf2e.aura_not_found', 'aura' => slug, 'name' => emitter.name) unless aura

        mine = Pf2e.holder_key(emitter) == Pf2e.holder_key(target)
        facts = Effects.character_facts(target)
        told = []

        reaching = aura['effects'].select { |one|
          (mine ? one['self'] : AFFECTS.fetch(one['affects'], []).include?(relation.to_s)) &&
            Predicate.test(one['predicate'], facts)
        }.reject { |one| inside?(target, one['name'], origin(emitter, aura)) }

        applied = reaching.select { |one| fails_save?(emitter, target, aura, one, told) }.map do |one|
          effect = ActiveEffects.apply(target, one['name'], :applied_by => emitter.name,
                                                             :encounter => aura['encounter']).state
          effect.update(:aura_of => origin(emitter, aura), :level => aura['level'])
          effect
        end

        told.inject(Ok.new(:state => applied)) { |done, one| done.with_message(one['key'], one['args']) }
      end

      # Whether an effect reaches the one inside: always, unless it has a save and they pass it. An
      # emitter with no spell DC to save against leaves it to the GM, so it lands.
      def self.fails_save?(emitter, target, aura, one, told)
        return true unless one['save']

        dc = spell_dc(emitter)

        return true unless dc

        # A save's rank is stored under its capitalised name.
        save = one['save'].to_s.capitalize
        result = Resolve.roll(Check.of(target, 'save', save), :dc => dc)
        told << { 'key' => 'pf2e.aura_save',
                  'args' => { 'target' => target.name, 'aura' => aura['slug'], 'save' => save,
                              'total' => result['total'], 'dc' => dc, 'degree' => Resolve::WORDS[result['degree']] } }

        !Degree.success?(result['degree'])
      end

      # The emitter's best spell DC, or nil when they cast nothing.
      def self.spell_dc(emitter)
        magic = emitter.respond_to?(:magic) ? emitter.magic : nil
        entries = magic ? Pf2emagic::Entries.casting(magic) : []

        entries.filter_map { |entry|
          stats = Pf2emagic.get_caster_stats(emitter, entry['name'])
          stats.is_a?(Hash) ? Acting.spell_figure(emitter, 'spell_dc', stats) : nil
        }.max
      end

      # The emitter's turn has ended. An effect their aura put on someone may say what that brings
      # (`emitter_turn_end`): Aura of Courage eases each ally's Frightened by 1.
      def self.emitter_turn_ended(emitter)
        of(emitter).flat_map do |aura|
          Pf2eEffect.find(:aura_of => origin(emitter, aura)).to_a.flat_map do |effect|
            ending = ActiveEffects.info(effect.name)['emitter_turn_end']

            next [] unless ending.is_a?(Hash) && effect.holder

            eased(effect.holder, ending, emitter)
          end
        end
      end

      def self.eased(holder, ending, emitter)
        name = Pf2e.canonical_condition(ending['lower'])
        held = Pf2e.condition_level(holder, name)

        return [] unless held.positive?

        left = [ held - ending['by'].to_i, 0 ].max
        Pf2e.set_condition(holder, name, left)

        [ Telling.event('pf2e.aura_eased', 'name' => holder.name, 'condition' => name, 'value' => left,
                                           'emitter' => emitter.name) ]
      end

      # Someone has left the aura: what it put on them ends, unless the aura says it stays.
      def self.leave(emitter, target, slug)
        aura = of(emitter).find { |one| one['slug'] == slug }
        leaving = aura ? aura['effects'].select { |one| one['leaves_on_exit'] }.map { |one| one['name'] } : []

        ended = ActiveEffects.on(target).select { |effect|
          effect.aura_of == (aura ? origin(emitter, aura) : "#{Pf2e.holder_key(emitter)}:#{slug}") &&
            (aura.nil? || leaving.include?(effect.name))
        }

        ended.each { |effect| ActiveEffects.remove(target, effect) }
        dropped = drop_conditions(target, aura ? origin(emitter, aura) : "#{Pf2e.holder_key(emitter)}:#{slug}")

        Ok.new(:state => ended.map(&:name) + dropped)
      end

      # The conditions an aura's save left that last only while they remain in it - Patron's Presence's
      # Stupefied - marked with the aura's origin. Answers their names.
      def self.drop_conditions(holder, origin)
        names = (holder.pf2_conditions || {}).select { |_name, held| held.is_a?(Hash) && held['aura_of'] == origin }.keys

        names.each { |name| Pf2e.remove_condition(holder, name) }
        names
      end

      def self.inside?(target, name, origin)
        ActiveEffects.on(target).any? { |effect| effect.name == name && effect.aura_of == origin }
      end

      # The effect projecting an aura has ended: everything the aura put on anyone ends with it.
      def self.dispelled(emitter, effect)
        origins(emitter, effect.name).flat_map { |origin| Pf2eEffect.find(:aura_of => origin).to_a }.each do |one|
          next unless one.holder

          drop_conditions(one.holder, one.aura_of)
          ActiveEffects.remove(one.holder, one)
        end
      end

      # What the effects put on others by the auras of the named effect record as their origin.
      def self.origins(emitter, name)
        Array(ActiveEffects.info(name)['rules']).select { |row| row['key'] == 'Aura' }.map do |row|
          "#{Pf2e.holder_key(emitter)}:#{row['slug'] || Domains.slug(name)}"
        end
      end
    end
  end
end
