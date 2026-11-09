require "plugin_test_loader"

module AresMUSH

  # Common items are anyone's to buy. The vendor sells an uncommon or rare one only to a character whose
  # build names it: a feat, class feature or class with an `item_access` list.
  describe "access to uncommon and rare items", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Access#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char,
                                  :weapon_prof => { 'simple' => 'trained', 'martial' => 'untrained',
                                                    'advanced' => 'untrained', 'unarmed' => 'trained' })
      @char.update(:combat => @combat, :pf2_level => 1, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human' },
                   :pf2_faith => {}, :pf2_feats => {}, :pf2_features => {}, :pf2_level_tracker => {},
                   :pf2_roll_options => {}, :pf2_derived => {})
    end

    after(:each) do
      @char.grants.each(&:delete)
      @char.sheet_caches.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def weapon(name)
      Global.read_config('pf2e_weapons', name)
    end

    def can_buy?(char, name)
      Pf2e::ItemAccess.accessible?(char, 'weapons', name, weapon(name))
    end

    def with_feat(name)
      @char.update(:pf2_feats => { 'ancestry' => [ name ] })

      reread
    end

    def picked(feat, label)
      @char.update(:pf2_feats => { 'ancestry' => [ feat ] },
                   :pf2_level_tracker => { '1' => { 'feat_choices' => { feat => [ label ] } } })

      reread
    end

    describe "rarity" do
      it "should read it from an item's traits" do
        expect(Pf2e::ItemAccess.rarity(weapon('Dogslicer'))).to eq 'uncommon'
        expect(Pf2e::ItemAccess.rarity(weapon('Longsword'))).to eq 'common'
      end

      it "should read a rune's own rarity field" do
        expect(Pf2e::ItemAccess.rarity('rarity' => 'rare', 'traits' => [])).to eq 'rare'
      end

      it "should let anyone buy a common item" do
        expect(can_buy?(reread, 'Longsword')).to be true
      end

      it "should refuse an uncommon item to someone without access" do
        expect(can_buy?(reread, 'Khazadi War Axe')).to be false
      end
    end

    describe "access a feat gives" do
      it "should open uncommon weapons with the trait the feat names" do
        expect(can_buy?(with_feat('Khazadi Weapon Familiarity'), 'Khazadi War Axe')).to be true
      end

      it "should not open another ancestry's weapons" do
        expect(can_buy?(with_feat('Khazadi Weapon Familiarity'), 'Dogslicer')).to be false
      end

      it "should open a weapon the feat names by name" do
        expect(can_buy?(with_feat('Gnome Weapon Familiarity'), 'Kukri')).to be true
      end

      it "should open a rare item named by name but not one matched only by trait" do
        access = [ { 'source' => 'Test', 'category' => 'weapons', 'traits' => [ 'khazad' ], 'names' => [ 'Named' ] } ]
        rare = { 'traits' => [ 'Rare', 'Khazad' ] }

        expect(Pf2e::ItemAccess.allows?(access, 'weapons', 'Named', rare)).to be true
        expect(Pf2e::ItemAccess.allows?(access, 'weapons', 'Other', rare)).to be false
      end

      it "should open nothing in another category" do
        access = Pf2e::ItemAccess.of(with_feat('Khazadi Weapon Familiarity'))

        expect(Pf2e::ItemAccess.allows?(access, 'armor', 'Anything', { 'traits' => [ 'Uncommon', 'Khazad' ] })).to be false
      end
    end

    describe "a deity's favored weapon" do
      def follower(charclass)
        @char.update(:pf2_base_info => { 'charclass' => charclass }, :pf2_faith => { 'deity' => 'Illotha' })

        reread
      end

      it "should open an uncommon favored weapon to a cleric" do
        expect(can_buy?(follower('Cleric'), 'Kukri')).to be true
      end

      it "should open it to a champion, through Deific Weapon" do
        expect(can_buy?(follower('Champion'), 'Kukri')).to be true
      end

      it "should not open it to another class that follows the deity" do
        expect(can_buy?(follower('Fighter'), 'Kukri')).to be false
      end

      it "should mark the favored weapon so Deific Weapon's rules can find it" do
        expect(Pf2eCombat.weapon_options('Kukri', weapon('Kukri'), follower('Champion'))).to include 'item:deity-favored'
      end
    end

    describe "Unconventional Weaponry" do
      it "should offer uncommon weapons, and advanced ones only to someone trained in martial weapons" do
        block = Global.read_config('pf2e_feats', 'Unconventional Weaponry')['feat_choice']['from_weapons']
        untrained = Pf2e.choice_weapon_pool(reread, block)

        expect(untrained).to include 'Dogslicer'
        expect(untrained).not_to include 'Longsword'
        expect(untrained).not_to include 'Khazadi War Axe'

        @combat.update(:weapon_prof => (@combat.weapon_prof || {}).merge('martial' => 'trained'))

        expect(Pf2e.choice_weapon_pool(reread, block)).to include 'Khazadi War Axe'
      end

      it "should give access to the weapon picked" do
        expect(can_buy?(picked('Unconventional Weaponry', 'Dogslicer'), 'Dogslicer')).to be true
        expect(can_buy?(picked('Unconventional Weaponry', 'Dogslicer'), 'Horsechopper')).to be false
      end

      it "should treat a martial weapon picked as simple" do
        expect(Pf2eCombat.get_weapon_prof(picked('Unconventional Weaponry', 'Dogslicer'), 'Dogslicer')).to eq 'trained'
      end

      it "should treat an advanced weapon picked as martial" do
        @combat.update(:weapon_prof => (@combat.weapon_prof || {}).merge('martial' => 'expert'))

        expect(Pf2eCombat.get_weapon_prof(picked('Unconventional Weaponry', 'Khazadi War Axe'), 'Khazadi War Axe')).to eq 'expert'
      end

      it "should not count as a weapon chosen for Weapon Proficiency" do
        expect(Pf2e.chosen_weapons(picked('Unconventional Weaponry', 'Dogslicer'))).to eq []
      end
    end

    # Every `item_access` list in config, held against the catalogues it names.
    describe "the data" do
      def declarations
        { 'pf2e_feats' => Global.read_config('pf2e_feats'), 'pf2e_class' => Global.read_config('pf2e_class'),
          'pf2e_class_features' => Global.read_config('pf2e_class_features') }.flat_map do |file, entries|
          (entries || {}).flat_map do |name, info|
            next [] unless info.is_a?(Hash)

            Array(info['item_access']).map { |row| [ "#{file} / #{name}", row ] }
          end
        end
      end

      it "should name only catalogues the vendor sells from" do
        strays = declarations.reject { |_where, row| Pf2egear::Inventory.row(row['category']) }

        expect(strays.map(&:first)).to eq []
      end

      it "should name only traits and items the catalogue holds" do
        strays = declarations.flat_map do |where, row|
          catalogue = Global.read_config(Pf2egear::Inventory.row(row['category'])['config'])
          traits = catalogue.values.flat_map { |info| Array(info['traits']).map { |t| t.to_s.downcase } }.uniq
          names = catalogue.keys.map(&:downcase)

          Array(row['traits']).reject { |t| traits.include?(t.to_s.downcase) }.map { |t| "#{where}: trait #{t}" } +
            Array(row['names']).reject { |n| names.include?(n.to_s.downcase) }.map { |n| "#{where}: #{n}" }
        end

        expect(strays).to eq []
      end

      it "should give access with every ancestry weapon familiarity feat but Ashen One's" do
        feats = Global.read_config('pf2e_feats').select { |name, _info| name.end_with?('Weapon Familiarity') }
        without = feats.reject { |_name, info| info['item_access'] }.keys

        expect(without).to eq [ 'Ashen One Weapon Familiarity' ]
      end
    end
  end
end
