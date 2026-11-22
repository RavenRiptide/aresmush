module AresMUSH
  module Pf2e
    module Familiar

      # The abilities a familiar has today, picked with prepare/familiar during daily preparations (Player
      # Core p. 212): familiar and master abilities, as many as its count allows. It is a DailyChoices pick
      # (`pick: familiar`, `lasts: until_changed`), so it locks until the next rest and holds from day to
      # day while it stays legal.
      #
      # The pick is held as { 'pick' => "Darkvision, Skilled (Arcana)", 'abilities' => [ { 'name', 'choice' } ] }.
      module Daily

        SWITCH = 'familiar'.freeze

        # What a Poppet's reinforcement is picked as: it spends one of the day's abilities.
        REINFORCED = 'Reinforced'.freeze

        PICKABLE = %w{familiar master}.freeze
        SPEEDS = %w{land swim climb fly}.freeze

        def self.catalogue
          Global.read_config('pf2e_familiar_abilities') || {}
        end

        # Today's picks, as they were stored.
        def self.today(char)
          found = DailyChoices.in_force(char)[SWITCH]
          found ? Array(found.first['abilities']) : []
        end

        def self.reinforced?(char)
          today(char).any? { |one| one['name'] == REINFORCED }
        end

        # What is true of the familiar today, for `Familiar::Stats.of`'s `options`.
        def self.options(char)
          reinforced?(char) ? [ 'self:reinforced' ] : []
        end

        # What `Familiar::Stats.of` reads for the familiar today: the abilities its approved details fix, and
        # the day's picks.
        def self.abilities_today(char)
          Familiar.fixed_abilities(char) + today(char).reject { |one| one['name'] == REINFORCED }
        end

        # A master ability they have today: picked, and their familiar approved. It is theirs, so it holds
        # whether or not the familiar is in the encounter. `holder` is a character or their encounter state.
        def self.master_ability?(holder, name)
          # Today's picks first: a creature holds none, and has no familiar record to ask about.
          today(holder).any? { |one| one['name'] == name } && Familiar.approved?(holder)
        end

        # The pools a feat opens one extra slot for: Leshy Familiar Secrets' leshy abilities.
        def self.pools(char)
          Pf2e.held_feat_details(char).filter_map { |_name, details| details['familiar_pool'] }.map(&:to_s).uniq
        end

        # How many abilities the day's picks may use: the count, less what a specific familiar uses. A pool's
        # slot is inside the count, and only that pool's abilities may fill it.
        def self.budget(char)
          approved = Familiar.approved_record(char) || {}
          uses = Stats.specific_config(approved['specific'])['uses'].to_i

          [ Stats.ability_count(char) - uses, 0 ].max
        end

        # Every ability prepare/familiar lists, in one flat list: "Skilled (skill)" where a choice is asked.
        def self.offer(char)
          offered(listing(char))
        end

        # The same flat list, from a listing already built. prepare/familiar builds one listing and asks this
        # of it, since building it is most of what the command costs.
        def self.offered(shown)
          (shown['familiar'] + shown['needs'].map(&:first) + shown['master'] + shown['leshy']).sort
        end

        # What prepare/familiar shows. An ability is left out when the familiar can't have it whatever else
        # is picked with it: a prerequisite of the master's that isn't met, an ability its details already
        # give it, or a second ability that replaces its animal trait. One that needs another ability picked
        # with it is listed in 'needs' with the abilities it needs: [ [ label, [ names ] ] ].
        def self.listing(char)
          approved = Familiar.approved_record(char) || {}
          fixed = Familiar.fixed_abilities(char)
          held = fixed.map { |one| one['name'] }
          open = pools(char)
          traits = nil
          trait_held = fixed.any? { |one| (catalogue[one['name']] || {})['changes_trait'] } ||
                       Stats.specific_config(approved['specific'])['traits'].present?

          entries = catalogue.filter_map do |name, info|
            next nil unless PICKABLE.include?(info['kind'])
            next nil if info['pool'] && !open.include?(info['pool'].to_s)
            next nil if held.include?(name) && !info['repeatable']
            next nil if info['changes_trait'] && trait_held

            prereq = info['prereq'] || {}
            next nil if prereq.any? { |kind, wanted| !COMBINED.include?(kind) && prereq_unmet?(char, kind, wanted, approved) }

            needs = Array(prereq['abilities']).map(&:to_s) - held

            if prereq['trait']
              traits ||= Array((Stats.of(char, fixed, :form => approved['form'].presence || 'land',
                                         :specific => approved['specific']) || {})['traits'])
              unless traits.include?(prereq['trait'].to_s)
                givers = trait_givers(prereq['trait'])
                next nil if givers.empty?

                needs += givers
              end
            end

            { 'name' => name, 'label' => label(char, name, info), 'info' => info, 'needs' => needs.uniq }
          end

          # Needing an ability the familiar can't have rules this one out too.
          names = entries.map { |one| one['name'] }
          entries = entries.select { |one| (one['needs'] - names).empty? }

          plain = entries.select { |one| one['needs'].empty? }
          sorted = ->(list) { list.map { |one| one['label'] }.sort }

          {
            'name' => approved['name'].presence,
            'familiar' => sorted.call(plain.select { |one| one['info']['kind'] == 'familiar' && !one['info']['pool'] }),
            'needs' => entries.reject { |one| one['needs'].empty? }.map { |one| [ one['label'], one['needs'] ] }.sort_by(&:first),
            'master' => sorted.call(plain.select { |one| one['info']['kind'] == 'master' }),
            'leshy' => sorted.call(plain.select { |one| one['info']['pool'] }),
            'selected' => today(char).map { |one| Familiar.abilities_text([ one ]) }.sort,
            'budget' => budget(char),
            'pooled' => open.size
          }
        end

        # Prerequisites another ability picked the same day can meet; the listing shows these as needs.
        COMBINED = %w{abilities trait}.freeze

        # "Skilled (skill)", "Resistance (two damage types)": the ability with what its choice asks for.
        def self.label(char, name, info)
          return name unless asks?(char, name, info)

          "#{name} (#{info['choice']['label'] || info['choice']['from'].to_s.chomp('s')})"
        end

        # The abilities that give the familiar a trait: Plant gives the plant trait.
        def self.trait_givers(trait)
          catalogue.select do |_name, info|
            PICKABLE.include?(info['kind']) && !info['pool'] &&
              Array(info['rules']).any? { |rule| rule['key'] == 'ActorTraits' && Array(rule['add']).map(&:to_s).include?(trait.to_s) }
          end.keys
        end

        # Whether an ability asks for a choice: Cantrip Connection only of a repertoire caster, since a
        # prepared caster fills its cantrip slot with `prepare`.
        def self.asks?(char, name, info)
          return false unless info['choice']
          return MasterSpells.repertoire?(char) if name == MasterSpells::CANTRIP_CONNECTION

          true
        end

        # DailyChoices' `resolve`: the whole list checked, and stored as the pick.
        def self.answers(char, _block, typed)
          return Err.new(:familiar_daily_waiting, 'pf2e.familiar_daily_waiting') if Familiar.awaiting_approval?(char)
          return Err.new(:familiar_daily_pet, 'pf2e.familiar_daily_pet') if Choices.plain_pet?(char)

          list = Choices.parse_list(typed)
          return Err.new(:familiar_daily_unreadable, 'pf2e.familiar_daily_unreadable') unless list

          check(char, list).and_then do |picked|
            Ok.new(:state => { 'pick' => Familiar.abilities_text(picked), 'abilities' => picked })
          end
        end

        # DailyChoices' `kept`: a rest keeps the picks while they are still legal. Spellcasting's spell
        # isn't asked again, so a spell not prepared again costs none of the others; it is checked when
        # the familiar casts it.
        def self.kept?(char, _block, pick)
          Familiar.approved?(char) && check(char, Array(pick['abilities']), keeping: true).ok?
        end

        # ------------------------------------------------------------------------------------------------
        # Checking a list
        # ------------------------------------------------------------------------------------------------

        def self.check(char, list, keeping: false)
          approved = Familiar.approved_record(char) || {}
          specific = approved['specific']
          fixed = Familiar.fixed_abilities(char)

          named = list.map { |one| named(one, specific) }
          failed = named.find(&:err?)
          return failed if failed

          picked = named.map(&:state)

          chosen = check_choices(char, picked, fixed, approved, keeping: keeping)
          return chosen if chosen.err?

          picked = chosen.state

          [ :repeats, :count, :traits, :prereqs ].each do |step|
            found = send("check_#{step}", char, picked, fixed, approved)
            return found if found.err?

            picked = found.state
          end

          Ok.new(:state => picked)
        end

        # An entry as the catalogue spells it, still carrying what was typed for its choice.
        def self.named(one, specific)
          if one['name'].casecmp?(REINFORCED)
            reinforce = Stats.specific_config(specific)['reinforce']
            return Err.new(:familiar_daily_reinforce, 'pf2e.familiar_daily_reinforce') unless reinforce
            return Err.new(:familiar_daily_no_choice, 'pf2e.familiar_daily_no_choice', 'ability' => REINFORCED) if one['choice']

            return Ok.new(:state => { 'name' => REINFORCED })
          end

          name = Choices.find_in(catalogue.keys, one['name'])
          return Err.new(:familiar_daily_unknown, 'pf2e.familiar_daily_unknown') unless name
          return Err.new(:familiar_daily_patron, 'pf2e.familiar_daily_patron', 'ability' => name) unless PICKABLE.include?(catalogue[name]['kind'])

          Ok.new(:state => one.merge('name' => name))
        end

        # Each choice checked against what it may be. A repertoire caster's Cantrip Connection is
        # `MasterSpells.connections`' to settle, since it remembers. A rest keeps Spellcasting's spell as it
        # stands.
        def self.check_choices(char, picked, fixed, approved, keeping: false)
          connecting = false

          stored = picked.map do |one|
            info = catalogue[one['name']] || {}
            asked = info['choice']

            next one if keeping && one['name'] == MasterSpells::SPELLCASTING

            if asked && one['name'] == MasterSpells::CANTRIP_CONNECTION && MasterSpells.repertoire?(char)
              connecting = true
              next one
            end

            unless asks?(char, one['name'], info)
              return Err.new(:familiar_daily_no_choice, 'pf2e.familiar_daily_no_choice', 'ability' => one['name']) if one['choice']

              next one.except('choice')
            end

            options = choice_options(char, one, asked, picked, fixed, approved)
            if options.empty? && one['name'] == MasterSpells::SPELLCASTING
              # Without the slots it needs, its prerequisite says why.
              next one if Choices.top_slot_rank(char) < info.dig('prereq', 'slot_rank').to_i

              return Err.new(:familiar_spellcasting_none, 'pf2e.familiar_spellcasting_none')
            end

            answer = choice_answer(one['choice'], options, asked['count'].to_i)

            unless answer
              count = asked['count'].to_i
              what = count > 1 ? t('pf2e.familiar_daily_choice_many', :count => count) : t('pf2e.familiar_daily_choice_one')

              return Err.new(:familiar_daily_choice, 'pf2e.familiar_daily_choice', 'ability' => one['name'], 'what' => what,
                             'list' => options.join(', '))
            end

            one.merge('choice' => answer)
          end

          connecting ? MasterSpells.connections(char, stored) : Ok.new(:state => stored)
        end

        def self.choice_options(char, one, asked, picked, fixed, approved)
          case asked['from']
          when 'list' then Array(asked['options']).map(&:to_s)
          when 'skills' then (Global.read_config('pf2e_skills') || {}).keys - Array(asked['except'])
          when 'languages' then Choices.known_languages(char)
          when 'spells' then MasterSpells.spellcasting_options(char)
          when 'speeds'
            others = picked.reject { |other| other.equal?(one) || other['name'] == REINFORCED }.map { |other| other.except('choice') }
            stats = Stats.of(char, fixed + others, :form => approved['form'].presence || 'land', :specific => approved['specific'])
            (stats ? stats['speeds'].keys : []) & SPEEDS
          else []
          end
        end

        # One answer, or `count` different ones ("fire, cold" or "fire and cold") as a list.
        def self.choice_answer(typed, options, count)
          return Choices.find_in(options, typed) if count <= 1

          said = typed.to_s.split(/\s*,\s*|\s+and\s+/i).map(&:strip).reject(&:empty?)
          found = said.map { |one| Choices.find_in(options, one) }

          found.size == count && found.all? && found.uniq.size == count ? found : nil
        end

        # An ability once, unless it is repeatable and each pick chooses differently; and never one the
        # familiar already has from its details.
        def self.check_repeats(_char, picked, fixed, _approved)
          (picked + fixed).group_by { |one| one['name'] }.each do |name, ones|
            next if ones.size < 2 || picked.none? { |one| one['name'] == name }

            info = catalogue[name] || {}
            # A prepared caster's Cantrip Connections ask no choice: each is one more cantrip slot.
            unchosen = name == MasterSpells::CANTRIP_CONNECTION && ones.none? { |one| one['choice'] }
            different = unchosen || ones.map { |one| one['choice'] }.uniq.size == ones.size

            next if info['repeatable'] && different

            key = fixed.any? { |one| one['name'] == name } ? 'pf2e.familiar_daily_has' : 'pf2e.familiar_daily_twice'
            return Err.new(:familiar_daily_twice, key, 'ability' => name)
          end

          Ok.new(:state => picked)
        end

        def self.check_count(char, picked, _fixed, _approved)
          open = pools(char)
          budget = budget(char)
          pooled = picked.select { |one| (catalogue[one['name']] || {})['pool'] }

          if pooled.any? { |one| !open.include?(catalogue[one['name']]['pool'].to_s) } || pooled.size > open.size
            return Err.new(:familiar_daily_pool, 'pf2e.familiar_daily_pool', 'count' => open.size)
          end

          return Ok.new(:state => picked) if picked.size <= budget && picked.size - pooled.size <= budget - open.size

          Err.new(:familiar_daily_count, 'pf2e.familiar_daily_count', 'count' => budget, 'picked' => picked.size,
                  'pool' => open.size)
        end

        # One ability that replaces its animal trait, counting what it already has: a specific familiar's
        # traits, or a fixed ability's (a leshy's plant, an alchemical familiar's construct).
        def self.check_traits(_char, picked, fixed, approved)
          changes = ->(one) { (catalogue[one['name']] || {})['changes_trait'] }
          today = picked.select(&changes)

          return Ok.new(:state => picked) if today.empty?

          held = fixed.any?(&changes) || Stats.specific_config(approved['specific'])['traits'].present?
          return Ok.new(:state => picked) if today.size == 1 && !held

          Err.new(:familiar_daily_trait, 'pf2e.familiar_daily_trait', 'ability' => today.last['name'])
        end

        def self.check_prereqs(char, picked, fixed, approved)
          all = (picked + fixed).map { |one| one['name'] }
          traits = nil

          picked.each do |one|
            (catalogue[one['name']] || {}).fetch('prereq', {}).each do |kind, wanted|
              unmet = case kind
                      when 'abilities' then (Array(wanted) - all).any?
                      when 'trait'
                        traits ||= Stats.of(char, fixed + picked.reject { |p| p['name'] == REINFORCED },
                                            :form => approved['form'].presence || 'land', :specific => approved['specific'])['traits']
                        !traits.include?(wanted.to_s)
                      else prereq_unmet?(char, kind, wanted, approved, one['name'])
                      end

              next unless unmet

              return Err.new(:familiar_daily_prereq, 'pf2e.familiar_daily_prereq', 'ability' => one['name'],
                             'needs' => t("pf2e.familiar_needs_#{kind}", :value => Array(wanted).join(', ')))
            end
          end

          Ok.new(:state => picked)
        end

        # A prerequisite of the master's or the familiar's details, which no other pick changes.
        def self.prereq_unmet?(char, kind, wanted, approved, name = nil)
          case kind
          when 'level' then char.pf2_level.to_i < wanted.to_i
          when 'slot_rank' then Choices.top_slot_rank(char) < wanted.to_i
          when 'has_focus_pool' then Pf2emagic.focus_pool_max(char.magic).zero?
          when 'feature' then !Pf2e.holds_feature?(char, wanted.to_s)
          when 'specific' then approved['specific'].to_s != wanted.to_s
          when 'cantrips' then !casts_cantrips?(char)
          when 'innate_ancestry_spell' then !innate_ancestry_spell?(char)
          else
            Global.logger.error "Unknown familiar ability prerequisite '#{kind}' on #{name}; it was refused." if name
            true
          end
        end

        # They prepare cantrips or keep them in a repertoire.
        def self.casts_cantrips?(char)
          magic = char.magic
          return false unless magic

          Pf2emagic::Entries.for_magic(magic).any? do |entry|
            (entry['slots'] || {})['cantrip'].to_i.positive? || Array((entry['known'] || {})['cantrip']).any?
          end
        end

        # An innate spell from an ancestry feat they hold.
        def self.innate_ancestry_spell?(char)
          return false unless Pf2emagic::Entries.innate?(char.magic)

          Array((char.pf2_feats || {})['ancestry']).any? { |name| grants_innate?(Global.read_config('pf2e_feats', name.to_s)) }
        end

        def self.grants_innate?(node)
          case node
          when Hash then node.key?('innate_spell') || node.values.any? { |one| grants_innate?(one) }
          when Array then node.any? { |one| grants_innate?(one) }
          else false
          end
        end
      end
    end
  end
end
