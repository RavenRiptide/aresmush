require "plugin_test_loader"

module AresMUSH

  # Every rule element in config, held against the vocabulary that reads it.
  #
  # The rows are imported from the pf2e system's own packs, which is the point: their system is the
  # reference implementation of these mechanics. What they replaced was hand-written and wrong in the
  # same direction every time - of 51 item bonuses, 10 granted a conditional bonus unconditionally, and
  # of 14 hand-written conditions, Unconscious penalised the wrong save.
  #
  # So this asserts against the tables rather than against a list someone has to remember to update: a
  # selector no statistic answers to, a kind nothing applies, a field nothing reads, or a formula the
  # reader cannot parse fails here rather than in front of a player.
  describe "imported rules", :dbtest => true do

    CATALOGUES = %w{pf2e_conditions pf2e_magicitem pf2e_armor pf2e_weapons pf2e_shields pf2e_gear
                    pf2e_consumables pf2e_feats}.freeze

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config
    end

    def rows
      CATALOGUES.flat_map do |catalogue|
        (Global.read_config(catalogue) || {}).flat_map do |name, info|
          next [] unless info.is_a?(Hash) && info['rules']

          info['rules'].map { |row| [ "#{catalogue} / #{name}", row ] }
        end
      end
    end

    # Every domain any statistic can produce, which is the whole vocabulary a selector may name.
    def reachable
      saves = %w{Fortitude Reflex Will}.flat_map { |s|
        Pf2e::Domains.for('save', Pf2e.canonical_save(s), Pf2e::LINKED_ABILITY[s.downcase])
      }
      skills = (Global.read_config('pf2e_skills') || {}).flat_map { |name, info|
        Pf2e::Domains.for(Pf2eSkills.lore?(name) ? 'lore' : 'skill', name, info['key_abil'])
      }
      plain = %w{hp ac perception class_dc spell_dc spell_attack initiative}.flat_map { |kind|
        Pf2e::ABILITIES.flat_map { |ability| Pf2e::Domains.for(kind, nil, ability) }
      }
      speeds = Pf2e::Domains::MOVEMENT.flat_map { |type| Pf2e::Domains.for('speed', type) }

      # An attack and its damage carry the weapon's own facts, so their domains are generated from the
      # catalogue's own weapon names, groups and base types rather than from a representative one.
      weapons = (Global.read_config('pf2e_weapons') || {})
      attacks = weapons.first(400).flat_map { |name, info|
        [ true, false ].flat_map { |ranged|
          descriptor = { 'name' => name, 'group' => info['group'], 'base' => info['base'] || name,
                         'prof' => 'expert', 'ranged' => ranged,
                         'unarmed' => Pf2e.has_trait?(info['traits'], 'unarmed') }

          Pf2e::Domains.for('attack', descriptor, 'Strength') +
            Pf2e::Domains.for('damage', descriptor, 'Strength')
        }
      }
      shapes = Pf2e::ABILITIES.flat_map { |ability|
        %w{unarmed weapon}.product([ true, false ]).flat_map { |kind, ranged|
          descriptor = { 'ranged' => ranged, 'unarmed' => kind == 'unarmed' }

          Pf2e::Domains.for('attack', descriptor, ability) +
            Pf2e::Domains.for('damage', descriptor, ability)
        }
      }

      (saves + skills + plain + speeds + attacks + shapes).uniq
    end

    # Two kinds of selector cannot be checked against a list. One names the item carrying the rule and
    # resolves to an id we cannot know here. The other is built off the name of an attack a character
    # has, which a feat can invent - Tiger Stance grants a tiger claw, so `tiger-claw-damage` is a real
    # domain that no catalogue contains. Both are checked by shape; everything else against the list,
    # which is what still catches `healing` and `will-dc`.
    def resolvable?(selector, held)
      return true if selector.to_s.match?(Pf2e::Effects::SELF_REFERENCE)

      slug = Pf2e::Domains.slug(selector)

      held.include?(slug) || Pf2e::Domains.derived?(slug)
    end

    it "should have imported rules to check" do
      expect(rows.size).to be > 300
    end

    it "should carry only kinds we apply" do
      strays = rows.reject { |_where, row| Pf2e::Rules.known?(row['key']) }
                   .map { |where, row| "#{where}: #{row['key'].inspect}" }

      expect(strays.uniq).to eq []
    end

    it "should carry only fields we read" do
      strays = rows.flat_map { |where, row|
        fields = Pf2e::Rules::BY_KEY[row['key'].to_s]['fields']

        (row.keys.map(&:to_s) - fields).map { |field| "#{where}: #{field}" }
      }

      expect(strays.uniq).to eq []
    end

    it "should name only selectors some statistic answers to" do
      held = reachable

      strays = rows.flat_map { |where, row|
        Array(row['selector']).reject { |selector| resolvable?(selector, held) }
                              .map { |selector| "#{where}: #{selector}" }
      }

      expect(strays.uniq).to eq []
    end

    # Neither a declaration nor a write reaches a statistic, so neither names a selector: one names an
    # option and the other a path.
    SELECTORLESS = %w{RollOption ActiveEffectLike Immunity Weakness Resistance}.freeze
    IWR_KINDS = %w{Immunity Weakness Resistance}.freeze

    it "should have a selector on everything that reaches a statistic, and on nothing else" do
      reaching, apart = rows.partition { |_where, row| !SELECTORLESS.include?(row['key']) }

      expect(reaching.reject { |_where, row| row['selector'] }.map(&:first).uniq).to eq []
      expect(apart.select { |_where, row| row['selector'] }.map(&:first).uniq).to eq []
    end

    it "should have an option on every declaration" do
      declarations = rows.select { |_where, row| row['key'] == 'RollOption' }

      expect(declarations.reject { |_where, row| row['option'] }.map(&:first).uniq).to eq []
    end

    # A path the registry cannot write would be an effect that silently does nothing.
    it "should write only paths the registry knows" do
      writes = rows.select { |_where, row| row['key'] == 'ActiveEffectLike' }

      strays = writes.reject { |_where, row| Pf2e::Paths.writable?(row['path']) }
                     .map { |where, row| "#{where}: #{row['path']}" }

      expect(strays.uniq).to eq []
    end

    it "should write with only the modes the registry applies" do
      writes = rows.select { |_where, row| row['key'] == 'ActiveEffectLike' }

      strays = writes.reject { |_where, row| Pf2e::Paths::MODES.key?(row['mode'].to_s) }
                     .map { |where, row| "#{where}: #{row['mode'].inspect}" }

      expect(strays.uniq).to eq []
    end

    # A kind of damage we cannot resolve would resist nothing, so the type has to be a plain word.
    it "should resist only kinds of damage it can name" do
      iwr = rows.select { |_where, row| IWR_KINDS.include?(row['key']) }

      strays = iwr.reject { |_where, row| Array(row['type']).all? { |one| !one.to_s.include?('{') } }
                  .map { |where, row| "#{where}: #{row['type'].inspect}" }

      expect(strays.uniq).to eq []
    end

    it "should give a weakness and a resistance a value, since that is how much it is" do
      valued = rows.select { |_where, row| %w{Weakness Resistance}.include?(row['key']) }

      expect(valued.reject { |_where, row| row['value'] }.map(&:first).uniq).to eq []
    end

    it "should have immunities and resistances, which conditions and items both declare" do
      expect(rows.count { |_where, row| IWR_KINDS.include?(row['key']) }).to be > 5
    end

    it "should have writes, since that is the second half of some feats" do
      expect(rows.count { |_where, row| row['key'] == 'ActiveEffectLike' }).to be > 40
    end

    # A write's value is stored as it stands, so it has to be something we can store and read back.
    it "should write only values we can hold" do
      writes = rows.select { |_where, row| row['key'] == 'ActiveEffectLike' }

      strays = writes.reject { |_where, row|
        [ String, Integer, Float, TrueClass, FalseClass ].any? { |kind| row['value'].is_a?(kind) }
      }.map { |where, row| "#{where}: #{row['value'].class}" }

      expect(strays.uniq).to eq []
    end

    it "should have declarations, since most of what an item offers is one" do
      expect(rows.count { |_where, row| row['key'] == 'RollOption' }).to be > 50
    end

    # Only a modifier's `type` is a stacking type. On an immunity or a resistance it is a kind of damage,
    # which is a different vocabulary in the same field name.
    it "should name only modifier types the stacking rule knows" do
      modifiers = rows.select { |_where, row| row['key'] == 'FlatModifier' && row['type'] }

      strays = modifiers.reject { |_where, row| Pf2e::Modifiers::TYPES.include?(row['type'].to_s) }
                        .map { |where, row| "#{where}: #{row['type'].inspect}" }

      expect(strays.uniq).to eq []
    end

    # A value that is a number or an expression has to be readable. A write's value may be neither - a
    # list of forms, a word - and those are written as they stand rather than evaluated.
    it "should carry values the formula reader can read" do
      strays = rows.flat_map { |where, row|
        Pf2e::Rules::FORMULA_FIELDS
          .select { |field| row[field].is_a?(Numeric) || row[field].is_a?(String) }
          .reject { |field| Pf2e::Formula.parses?(row[field]) || row['key'] == 'ActiveEffectLike' }
          .map { |field| "#{where}: #{field} #{row[field].inspect}" }
      }

      expect(strays.uniq).to eq []
    end

    # A write's value, where it is arithmetic, still has to be readable: Breath Control's is
    # `25 * (5 + @actor.abilities.con.mod)`.
    it "should carry writable arithmetic the formula reader can read" do
      writes = rows.select { |_where, row| row['key'] == 'ActiveEffectLike' }

      strays = writes.select { |_where, row| row['value'].is_a?(String) }
                     .select { |_where, row| row['value'].match?(/[@(]/) }
                     .reject { |_where, row| Pf2e::Formula.parses?(row['value']) }
                     .map { |where, row| "#{where}: #{row['value'].inspect}" }

      expect(strays.uniq).to eq []
    end

    it "should carry circumstances the predicate reader finds valid" do
      strays = rows.select { |_where, row| row['predicate'] }
                   .reject { |_where, row| Pf2e::Predicate.valid?(row['predicate']) }
                   .map { |where, row| "#{where}: #{row['predicate'].inspect}" }

      expect(strays.uniq).to eq []
    end

    it "should have conditional rows, since most item bonuses are conditional" do
      expect(rows.count { |_where, row| row['predicate'] }).to be > 20
    end

    it "should have damage dice, since that is what most feats that touch damage add" do
      expect(rows.count { |_where, row| row['key'] == 'DamageDice' }).to be > 20
    end

    # An override raises a die, sets it outright, or changes the kind of damage. Every one has exactly
    # one property, which is what their own validation requires.
    it "should carry only overrides the damage reader applies" do
      known = %w{upgrade downgrade dieSize diceNumber damageType}

      strays = rows.select { |_where, row| row['override'] }
                   .flat_map { |where, row|
                     (row['override'].keys.map(&:to_s) - known).map { |key| "#{where}: #{key}" }
                   }

      expect(strays.uniq).to eq []
    end

    it "should have overrides, since that is how a die size is raised" do
      expect(rows.count { |_where, row| row['override'] }).to be > 5
    end

    # One vocabulary, not two: a block left behind next to a `rules:` block would be read by different
    # code and counted twice.
    it "should have nothing left carrying the vocabularies this replaced" do
      left = CATALOGUES.flat_map { |catalogue|
        (Global.read_config(catalogue) || {})
          .select { |_n, i| i.is_a?(Hash) && (i['bonus'] || i['modifies'] || i['affected_stat']) }.keys
      }

      expect(left).to eq []
    end
  end
end
