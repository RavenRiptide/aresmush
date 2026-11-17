require "plugin_test_loader"

module AresMUSH

  # Every character's fist, and the rules that change it.
  #
  # Foundry's rules name the fist by the id they give it, `xxxxxxFISTxxxxxx`. Here the fist is not an
  # item and has no id, so until the fist answered to Foundry's, none of those rules reached it: Iron
  # Fists left it nonlethal, and Powerful Fist's d6 was only there because chargen stored one.
  describe "the fist and the rules that change it", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Fist#{rand(1000000)}")
      @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 10, :charclass_hp => 10)
      @combat = Pf2eCombat.create(:character => @char, :perception => 'trained',
                                  :weapon_prof => { 'unarmed' => 'trained' },
                                  :unarmed_attacks => { 'Fist' => fist('1d4'),
                                                        'Jaws' => { 'damage' => '1d6', 'damage_type' => 'P',
                                                                    'group' => 'Brawling',
                                                                    'traits' => %w(nonlethal unarmed) } })
      @char.update(:hp => @hp, :combat => @combat, :pf2_level => 5, :pf2_conditions => {},
                   :pf2_traits => [], :pf2_base_info => {}, :pf2_derived => {},
                   :pf2_feats => { 'ancestry' => [] }, :pf2_features => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
    end

    after(:each) do
      Pf2e::ActiveEffects.on(Character[@char.id]).each(&:delete)
      @abilities.each(&:delete)
      @hp&.delete
      @combat&.delete
      @char&.delete
    end

    def fist(damage)
      { 'damage' => damage, 'damage_type' => 'B', 'group' => 'Brawling',
        'traits' => %w(agile finesse nonlethal unarmed) }
    end

    def reread
      Character[@char.id]
    end

    def attack(name)
      Pf2eCombat.damage_descriptor(reread, name)
    end

    def sheet_line(name)
      Pf2e::PF2CombatSheetTemplate.new(reread, nil).unarmed_attacks.find { |line| line.include?("#{name}:") }
    end

    def with_ancestry_feat(name)
      @char.update(:pf2_feats => { 'ancestry' => [ name ] })
    end

    def with_feature(name)
      @char.update(:pf2_features => { 'charclass_features' => [ name ] })
    end

    describe "a character with no rule aimed at the fist" do
      it "should keep the fist as stored" do
        expect(attack('Fist')['traits']).to include 'nonlethal'
        expect(attack('Fist')['die']).to eq 'd4'
      end

      # A nil id is what lends an unarmed attack handwraps' runes and keeps weapon poison off it.
      it "should leave the fist without an item id" do
        expect(attack('Fist')['id']).to be_nil
      end
    end

    describe "Iron Fists" do
      before(:each) { with_ancestry_feat('Iron Fists') }

      it "should take away the fist's nonlethal trait and give it shove" do
        expect(attack('Fist')['traits']).to_not include 'nonlethal'
        expect(attack('Fist')['traits']).to include 'shove'
      end

      it "should show the fist that way on the combat sheet" do
        line = sheet_line('Fist')

        expect(line).to include 'Shove'
        expect(line).to_not include 'Nonlethal'
      end

      it "should leave the character's other unarmed attacks alone" do
        expect(attack('Jaws')['traits']).to include 'nonlethal'
        expect(attack('Jaws')['traits']).to_not include 'shove'
      end

      # Divine Vessel grants an attack called Fist. In Foundry it is a different item from the fist, so
      # their fist rules never reach it, and here they must not either.
      it "should leave a granted attack that is also called Fist alone" do
        granted = { 'id' => nil, 'name' => 'Fist', 'category' => 'unarmed', 'group' => 'brawling',
                    'base' => 'Fist', 'traits' => %w(agile finesse unarmed nonlethal), 'prof' => 'trained',
                    'ranged' => false, 'unarmed' => true, 'bomb' => false, 'die' => 'd8', 'dice' => 2,
                    'range' => 0, 'materials' => [], 'runes' => [], 'damage_type' => 'B',
                    'striking' => 0, 'rune' => 0 }

        expect(Pf2eCombat.adjusted_strike(reread, granted)['traits']).to include 'nonlethal'
      end
    end

    describe "Powerful Fist" do
      before(:each) { with_feature('Powerful Fist') }

      it "should make a monk's 1d4 fist a d6" do
        expect(Pf2eCombat.get_damage(reread, 'Fist')).to start_with '1d6'
      end

      # Features are read before active effects, so Wooden Fists steps the monk's d6 and not the d4.
      it "should let Wooden Fists step the d6 up to a d8" do
        Pf2e::ActiveEffects.apply(reread, 'Spell Effect: Wooden Fists')

        expect(Pf2eCombat.get_damage(reread, 'Fist')).to start_with '1d8'
        expect(attack('Fist')['traits']).to include 'reach'
        expect(attack('Fist')['traits']).to_not include 'nonlethal'
      end
    end

    describe "Tusks (Oruch)" do
      before(:each) { with_ancestry_feat('Tusks (Oruch)') }

      it "should grant a tusks attack of 1d6 piercing" do
        tusks = Pf2eCombat.granted_strikes(reread).find { |one| one['name'] == 'Tusks' }

        expect(tusks).to_not be_nil
        expect(tusks['die']).to eq 'd6'
        expect(tusks['traits']).to include('finesse', 'unarmed')
        expect(tusks['group']).to eq 'brawling'
      end

      it "should show the tusks on the combat sheet" do
        line = Pf2e::PF2CombatSheetTemplate.new(reread, nil).unarmed_attacks.find { |one| one.include?('Tusks') }

        expect(line).to include '1d6'
        expect(line).to include 'piercing'
      end
    end

    # Chargen used to store a monk's fist as 1d6, which Powerful Fist would now step up to a d8.
    describe "putting back a fist stored as 1d6" do
      it "should store a monk's fist as 1d4 again and still roll a d6" do
        with_feature('Powerful Fist')
        @combat.update(:unarmed_attacks => { 'Fist' => fist('1d6') })

        expect(Pf2e::FistDie.restore!(reread)).to eq true
        expect(reread.combat.unarmed_attacks['Fist']['damage']).to eq '1d4'
        expect(Pf2eCombat.get_damage(reread, 'Fist')).to start_with '1d6'
      end

      it "should leave a character without Powerful Fist alone" do
        @combat.update(:unarmed_attacks => { 'Fist' => fist('1d6') })

        expect(Pf2e::FistDie.restore!(reread)).to eq false
        expect(reread.combat.unarmed_attacks['Fist']['damage']).to eq '1d6'
      end

      it "should do nothing the second time" do
        with_feature('Powerful Fist')
        @combat.update(:unarmed_attacks => { 'Fist' => fist('1d6') })
        Pf2e::FistDie.restore!(reread)

        expect(Pf2e::FistDie.restore!(reread)).to eq false
      end

      it "should leave the character's other unarmed attacks as they were" do
        with_feature('Powerful Fist')
        jaws = { 'damage' => '1d6', 'damage_type' => 'P', 'group' => 'Brawling', 'traits' => %w(unarmed) }
        @combat.update(:unarmed_attacks => { 'Fist' => fist('1d6'), 'Jaws' => jaws })
        Pf2e::FistDie.restore!(reread)

        expect(reread.combat.unarmed_attacks['Jaws']).to eq jaws
      end
    end
  end
end
