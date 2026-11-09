require "plugin_test_loader"

module AresMUSH

  # An uncommon or rare spell is learned only once staff unlock it for the character, after the player
  # spends RPP on it. The unlock is a `spell_unlock` grant, and every way of picking a spell by name reads it.
  describe "unlocked spells", :dbtest => true do

    let(:spell) { 'Umbral Journey' }

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Unlock#{rand(1000000)}")
      @char.update(:pf2_level => 5, :pf2_base_info => { 'charclass' => 'Wizard' },
                   :pf2_feats => {}, :pf2_features => {}, :pf2_level_tracker => {})
    end

    after(:each) do
      @char.grants.each(&:delete)
      @char.sheet_caches.each(&:delete)
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def unlock
      Pf2e::SpellUnlocks.unlock!(@char, spell, :by => 'Staff')

      reread
    end

    it "should leave an uncommon spell locked until staff unlock it" do
      expect(Pf2e::SpellUnlocks.unlocked?(reread, spell)).to be false
      expect(Pf2e::SpellUnlocks.unlocked?(unlock, spell)).to be true
    end

    it "should lock it again when staff take the unlock back" do
      Pf2e::SpellUnlocks.relock!(unlock, spell, :by => 'Staff')

      expect(Pf2e::SpellUnlocks.unlocked?(reread, spell)).to be false
    end

    it "should offer an unlocked spell among the spells a character may pick by name" do
      expect(Pf2emagic.find_common_spells(reread).keys).not_to include spell
      expect(Pf2emagic.find_common_spells(unlock).keys).to include spell
    end

    it "should offer it to a class's own picks too" do
      expect(Pf2emagic.pickable_spells(unlock, 'Wizard', 5).keys).to include spell
    end

    it "should not open the spell to anyone else" do
      unlock
      other = Character.create(:name => "Other#{rand(1000000)}")

      expect(Pf2emagic.find_common_spells(other).keys).not_to include spell
    ensure
      other&.delete
    end

    describe "learning it into a spellbook" do
      def attempt(unlocked)
        Pf2emagic::LearnSpell.check(
          'target' => { 'name' => 'Wizard', 'tradition' => 'arcane' }, 'spell' => spell,
          'details' => Global.read_config('pf2e_spells', spell), 'known' => {}, 'unlocked' => unlocked,
          'blocked' => false, 'money' => 100000, 'price' => 0
        )
      end

      it "should refuse a spell that isn't unlocked" do
        expect(attempt(false).code).to eq :not_common
      end

      it "should allow one that is" do
        expect(attempt(true).ok?).to be true
      end
    end
  end
end
