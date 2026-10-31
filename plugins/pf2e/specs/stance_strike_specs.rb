require "plugin_test_loader"

module AresMUSH

  # A stance that says "the only Strikes you can make are..." grants an attack that replaces every other
  # while it lasts: a monk in Stumbling Stance makes stumbling swings, and their fists and weapons wait.
  describe "stance strikes", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Stance#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char,
                                  :weapon_prof => { 'unarmed' => 'trained', 'simple' => 'trained', 'martial' => 'trained' },
                                  :unarmed_attacks => { 'Fist' => { 'damage' => '1d6', 'damage_type' => 'B', 'group' => 'Brawling',
                                                                    'traits' => %w(agile finesse nonlethal unarmed) } })
      @char.update(:combat => @combat, :pf2_level => 3, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_derived => {}, :pf2_feats => {}, :pf2_roll_options => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => name == 'Dexterity' ? 18 : 10)
      }
      @items = []
    end

    after(:each) do
      Pf2e::ActiveEffects.on(reread).each(&:delete)
      @items.each(&:delete)
      @abilities.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def item(name)
      info = Global.read_config('pf2e_weapons', name) || raise("no such weapon: #{name}")
      made = Pf2egear.create_item(@char, 'weapons', name, 1, info)
      @items << made

      made
    end

    def handwraps
      item('Handwraps of Mighty Blows (+1 Striking)')
        .update(:invested => true, :runes => { 'fundamental' => { 'potency' => 1, 'power' => 1 } })
    end

    def enter(stance)
      Pf2e::ActiveEffects.apply(reread, stance)
    end

    def attack_names
      Pf2e::Actors.of(reread).attacks.map { |names, _attack| names.first }
    end

    def attack(name)
      Pf2e::Actors.of(reread).attacks.find { |names, _attack| names.first == name }&.last
    end

    before(:each) do
      item('Longsword').update(:equipped => true)
    end

    it "should offer the character's weapons and fists outside a stance" do
      expect(attack_names).to include 'Longsword', 'Fist'
    end

    it "should offer only the stance's attack while in it" do
      enter('Stance: Stumbling Stance')

      expect(attack_names).to eq [ 'Stumbling Swing' ]
    end

    it "should offer the weapons again once the stance ends" do
      enter('Stance: Stumbling Stance')
      Pf2e::ActiveEffects.remove_named(reread, 'Stance: Stumbling Stance')

      expect(attack_names).to include 'Longsword', 'Fist'
      expect(attack_names).to_not include 'Stumbling Swing'
    end

    it "should roll the attack the stance describes" do
      enter('Stance: Crane Stance')
      wing = attack('Crane Wing')

      expect(attack_names).to eq [ 'Crane Wing' ]
      expect(Pf2e::Damage.formula(reread, wing)).to start_with '1d6'
      expect(wing['traits']).to include 'agile', 'finesse', 'nonlethal'
    end

    # Dexterity +4, trained +2 and level 3 make +9; invested handwraps of mighty blows add their +1 and
    # their striking rune to an unarmed attack a stance grants as they do to a fist.
    it "should give a stance's attack the runes of invested handwraps" do
      enter('Stance: Stumbling Stance')
      before = Pf2e::Stat.total(reread, 'attack', attack('Stumbling Swing'))

      handwraps

      expect(before).to eq 9
      expect(Pf2e::Stat.total(reread, 'attack', attack('Stumbling Swing'))).to eq 10
      expect(Pf2e::Damage.formula(reread, attack('Stumbling Swing'))).to start_with '2d8'
    end

    def combat_sheet
      Pf2e::PF2CombatSheetTemplate.new(reread, double(:screen_reader => false))
    end

    it "should list only the stance's attack on the combat sheet, and say why there are no weapons" do
      enter('Stance: Stumbling Stance')

      expect(combat_sheet.unarmed_attacks.join).to include 'Stumbling Swing'
      expect(combat_sheet.unarmed_attacks.join).to_not include 'Fist:'
      expect(combat_sheet.weapons).to eq [ t('pf2e.csheet_strikes_replaced', :source => 'Stumbling Stance',
                                                                             :attacks => 'Stumbling Swing') ]
    end

    # The handwraps line says what they add, so a pair with no runes does not read as working.
    it "should name the runes invested handwraps give" do
      handwraps

      expect(combat_sheet.rune_lenders.join).to include t('pf2e.unarmed_runes_apply', :runes => '+1 potency, striking')
    end

    it "should say when invested handwraps have no runes" do
      item('Handwraps of Mighty Blows (+1)').update(:invested => true, :runes => { 'fundamental' => {}, 'property' => {} })

      expect(combat_sheet.rune_lenders.join).to include t('pf2e.unarmed_runes_none')
    end

    # Every stance action the catalogue offers whose effect grants an attack, with damage of its own, as
    # the only one there is. Monastic Archer Stance limits Strikes to bows the character already has.
    it "should give every stance whose attack replaces the others an attack to make" do
      effects = Global.read_config('pf2e_effects')
      stances = Global.read_config('pf2e_actions').values.map { |action| action['self_effect'] }.compact
                      .select { |name| name.start_with?('Stance:') && effects[name] }
                      .select { |name| effects[name]['description'].to_s =~ /The only Strikes you can make.*\bdeal \d*d\d+/ }

      missing = stances.reject do |name|
        Array(effects[name]['rules']).any? { |row| row['key'] == 'Strike' && row['replaceAll'] == true }
      end

      expect(stances).to include 'Stance: Stumbling Stance'
      expect(missing).to eq []
    end
  end
end
