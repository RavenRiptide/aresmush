require "plugin_test_loader"

module AresMUSH

  # The ancestry weapon familiarity feats: martial weapons of the ancestry, and the plain weapons each
  # names, count as simple; advanced ones count as martial; and from 5th level each grants the critical
  # specialisation effect with them. The feats say all of it in their own rules.
  describe "ancestry weapon familiarity", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Familiar#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char,
                                  :weapon_prof => { 'simple' => 'expert', 'martial' => 'trained',
                                                    'advanced' => 'untrained', 'unarmed' => 'trained' })
      @char.update(:combat => @combat, :pf2_level => 1, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Khazad' },
                   :pf2_feats => {}, :pf2_features => {},
                   :pf2_roll_options => {}, :pf2_derived => {})
    end

    after(:each) do
      @combat&.delete
      @char&.delete
    end

    def with_feat(name, level: 1)
      @char.update(:pf2_feats => { 'ancestry' => [ name ] }, :pf2_level => level)

      Character[@char.id]
    end

    def weapon(name)
      Global.read_config('pf2e_weapons', name)
    end

    def familiarity_feats
      Global.read_config('pf2e_feats').select { |name, _info| name.end_with?('Weapon Familiarity') }
    end

    # Every `item:base:` and `item:trait:` a rule names, found anywhere in its definition or predicate.
    def named_options(node)
      case node
      when Hash then node.values.flat_map { |one| named_options(one) }
      when Array then node.flat_map { |one| named_options(one) }
      when String then node.match?(/\Aitem:(base|trait):/) ? [ node ] : []
      else []
      end
    end

    describe "the data" do
      it "should give every familiarity feat a proficiency rule and a critical specialisation rule" do
        missing = familiarity_feats.reject do |_name, info|
          kinds = Array(info['rules']).map { |row| row['key'] }

          kinds.include?('MartialProficiency') && kinds.include?('CriticalSpecialization')
        end

        expect(missing.keys).to eq []
      end

      it "should name only weapons and traits the catalogue holds" do
        options = Global.read_config('pf2e_weapons').flat_map { |name, info| Pf2eCombat.weapon_options(name, info) }.uniq

        strays = familiarity_feats.flat_map do |name, info|
          named_options(info['rules']).reject { |one| options.include?(one) }.map { |one| "#{name}: #{one}" }
        end

        expect(strays.uniq).to eq []
      end
    end

    describe "proficiency" do
      it "should treat a martial weapon of the ancestry as simple" do
        char = with_feat('Oruch Weapon Familiarity')

        expect(Pf2eCombat.get_weapon_prof(char, 'Oruch Knuckle Dagger')).to eq 'expert'
      end

      it "should treat an advanced weapon of the ancestry as martial" do
        char = with_feat('Khazadi Weapon Familiarity')

        expect(Pf2eCombat.get_weapon_prof(char, 'Khazadi War Axe')).to eq 'trained'
      end

      it "should treat a plain weapon the feat names as simple" do
        char = with_feat('Khazadi Weapon Familiarity')

        expect(Pf2eCombat.get_weapon_prof(char, 'Warhammer')).to eq 'expert'
      end

      it "should cover the heritage feat, whose weapons carry no ancestry trait" do
        char = with_feat('Ashen One Weapon Familiarity')

        expect(Pf2eCombat.get_weapon_prof(char, 'Scythe')).to eq 'expert'
      end

      it "should leave a weapon the feat does not name alone" do
        char = with_feat('Khazadi Weapon Familiarity')

        expect(Pf2eCombat.get_weapon_prof(char, 'Longsword')).to eq 'trained'
      end

      it "should leave a character without the feat alone" do
        expect(Pf2eCombat.get_weapon_prof(Character[@char.id], 'Warhammer')).to eq 'trained'
      end
    end

    describe "critical specialisation" do
      it "should not apply before 5th level" do
        char = with_feat('Khazadi Weapon Familiarity', level: 4)

        expect(Pf2e.crit_spec_weapon?(char, 'Warhammer', weapon('Warhammer'))).to be false
      end

      it "should apply from 5th level" do
        char = with_feat('Khazadi Weapon Familiarity', level: 5)

        expect(Pf2e.crit_spec_weapon?(char, 'Warhammer', weapon('Warhammer'))).to be true
      end

      it "should not apply to a weapon the feat does not name" do
        char = with_feat('Khazadi Weapon Familiarity', level: 5)

        expect(Pf2e.crit_spec_weapon?(char, 'Longsword', weapon('Longsword'))).to be false
      end
    end

    # The "Via ..." line on the combat sheet.
    describe "what the sheet says grants it" do
      before(:each) { allow(Pf2e).to receive(:equipped_weapon_names).and_return([ 'Warhammer' ]) }

      it "should name the feat once it grants the effect" do
        char = with_feat('Khazadi Weapon Familiarity', level: 5)

        expect(Pf2e.crit_spec_sources(char)).to include 'Khazadi Weapon Familiarity'
      end

      it "should not name the feat before 5th level" do
        char = with_feat('Khazadi Weapon Familiarity', level: 1)

        expect(Pf2e.crit_spec_sources(char)).not_to include 'Khazadi Weapon Familiarity'
      end
    end
  end
end
