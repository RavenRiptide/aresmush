require "plugin_test_loader"

module AresMUSH

  # Every condition that changes a number, held against the vocabulary that reads it.
  #
  # The previous shape was an `affected_stat` block in two different shapes, naming statistics in
  # English, read by nothing at all. A condition that names a domain nothing has, or a type nothing
  # stacks, or a formula nothing parses, is the same failure with a new spelling - so this asserts
  # against the tables rather than against a list of conditions someone has to remember to update.
  describe "condition effects", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config
    end

    def conditions
      Global.read_config('pf2e_conditions').select { |_name, info| info.is_a?(Hash) && info['modifies'] }
    end

    def rows
      conditions.flat_map { |name, info| info['modifies'].map { |row| [ name, row ] } }
    end

    # Every domain any statistic can produce. A save's own name is reachable through the save kind, a
    # skill's through the skill kind, and so on, so this is the whole vocabulary a condition may name.
    def reachable
      saves = %w{Fortitude Reflex Will}.flat_map { |s| Pf2e::Domains.for('save', s, Pf2e::LINKED_ABILITY[s.downcase]) }
      skills = Global.read_config('pf2e_skills').flat_map { |name, info|
        Pf2e::Domains.for('skill', name, info['key_abil'])
      }
      plain = %w{hp speed ac perception class_dc spell_dc spell_attack attack}.flat_map { |kind|
        Pf2e::ABILITIES.flat_map { |ability| Pf2e::Domains.for(kind, 'Example', ability) }
      }
      lores = Pf2e::Domains.for('lore', 'Example Lore')

      (saves + skills + plain + lores).uniq
    end

    it "should have conditions that change numbers" do
      expect(conditions.size).to be > 10
    end

    it "should name only domains some statistic has" do
      strays = rows.flat_map { |name, row|
        Array(row['domain']).reject { |domain| reachable.include?(Pf2e::Domains.slug(domain)) }
                            .map { |domain| "#{name}: #{domain}" }
      }

      expect(strays).to eq []
    end

    it "should name only modifier types the stacking rule knows" do
      strays = rows.reject { |_name, row| Pf2e::Modifiers::TYPES.include?(row['type'].to_s) }
                   .map { |name, row| "#{name}: #{row['type'].inspect}" }

      expect(strays).to eq []
    end

    it "should carry a value the formula reader can read" do
      strays = rows.reject { |_name, row| Pf2e::Formula.parses?(row['value']) }
                   .map { |name, row| "#{name}: #{row['value'].inspect}" }

      expect(strays).to eq []
    end

    # A row whose formula reads a condition's value only makes sense on a condition that has one.
    it "should only scale by a value on a condition that carries one" do
      strays = rows.select { |_name, row| row['value'].to_s.include?('@source.value') }
                   .reject { |name, _row| Global.read_config('pf2e_conditions', name, 'value') }
                   .map { |name, _row| name }

      expect(strays).to eq []
    end

    it "should have no condition left carrying the old affected_stat block" do
      left = Global.read_config('pf2e_conditions').select { |_n, i| i.is_a?(Hash) && i['affected_stat'] }

      expect(left.keys).to eq []
    end
  end
end
