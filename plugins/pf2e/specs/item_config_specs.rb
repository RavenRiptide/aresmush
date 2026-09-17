require "plugin_test_loader"

module AresMUSH

  # Every item that changes a number, held against the vocabulary that reads it.
  #
  # The rows are imported from the pf2e system's equipment packs, which is the point: they are the
  # reference implementation of these items. What they replaced was hand-written, and ten of the
  # fifty-one entries granted a conditional bonus unconditionally.
  describe "item effects in config", :dbtest => true do

    CATALOGUES = %w{pf2e_magicitem pf2e_armor pf2e_weapons pf2e_shields pf2e_gear pf2e_consumables}.freeze

    # The ten our own config had wrong: each grants its bonus only in some circumstance, and each was
    # written as though it always applied.
    WAS_UNCONDITIONAL = [
      'Boots of Bounding (Greater)', 'Clandestine Cloak', 'Clandestine Cloak (Greater)',
      'Dancing Scarf', 'Dancing Scarf (Greater)', 'Skeleton Key (Greater)'
    ].freeze

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config
    end

    def rows
      CATALOGUES.flat_map do |catalogue|
        (Global.read_config(catalogue) || {}).flat_map do |name, info|
          next [] unless info.is_a?(Hash) && info['modifies']

          info['modifies'].map { |row| [ "#{catalogue} / #{name}", row ] }
        end
      end
    end

    def reachable
      saves = %w{Fortitude Reflex Will}.flat_map { |s|
        Pf2e::Domains.for('save', Pf2e.canonical_save(s), Pf2e::LINKED_ABILITY[s.downcase])
      }
      skills = (Global.read_config('pf2e_skills') || {}).flat_map { |name, info|
        Pf2e::Domains.for(Pf2eSkills.lore?(name) ? 'lore' : 'skill', name, info['key_abil'])
      }
      plain = %w{hp speed ac perception class_dc spell_dc spell_attack attack}.flat_map { |kind|
        Pf2e::ABILITIES.flat_map { |ability| Pf2e::Domains.for(kind, 'Example', ability) }
      }

      (saves + skills + plain).uniq
    end

    it "should have imported rows to check" do
      expect(rows.size).to be > 100
    end

    it "should name only domains some statistic has" do
      strays = rows.flat_map { |where, row|
        Array(row['domain']).reject { |domain| reachable.include?(Pf2e::Domains.slug(domain)) }
                            .map { |domain| "#{where}: #{domain}" }
      }

      expect(strays).to eq []
    end

    it "should name only modifier types the stacking rule knows" do
      strays = rows.reject { |_where, row| Pf2e::Modifiers::TYPES.include?(row['type'].to_s) }
                   .map { |where, row| "#{where}: #{row['type'].inspect}" }

      expect(strays).to eq []
    end

    it "should carry a value the formula reader can read" do
      strays = rows.reject { |_where, row| Pf2e::Formula.parses?(row['value']) }
                   .map { |where, row| "#{where}: #{row['value'].inspect}" }

      expect(strays).to eq []
    end

    it "should carry circumstances the predicate reader finds valid" do
      strays = rows.select { |_where, row| row['when'] }
                   .reject { |_where, row| Pf2e::Predicate.valid?(row['when']) }
                   .map { |where, row| "#{where}: #{row['when'].inspect}" }

      expect(strays).to eq []
    end

    it "should have conditional rows at all, since most item bonuses are conditional" do
      conditional = rows.count { |_where, row| row['when'] }

      expect(conditional).to be > 20
    end

    # The specific failure this import was for.
    it "should make every bonus we had written as unconditional carry its circumstance" do
      missing = WAS_UNCONDITIONAL.reject do |name|
        Array(Global.read_config('pf2e_magicitem', name, 'modifies') ||
              Global.read_config('pf2e_gear', name, 'modifies')).any? { |row| row['when'] }
      end

      expect(missing).to eq []
    end

    # One vocabulary, not two: a `bonus:` hash left behind next to a `modifies:` block would be
    # counted twice, because they are read by different code.
    it "should have no item left carrying the old bonus hash" do
      left = CATALOGUES.flat_map { |catalogue|
        (Global.read_config(catalogue) || {}).select { |_n, i| i.is_a?(Hash) && i['bonus'] }.keys
      }

      expect(left).to eq []
    end
  end
end
