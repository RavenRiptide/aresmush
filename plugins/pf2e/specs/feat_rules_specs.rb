require "plugin_test_loader"

module AresMUSH

  # Feats that change a number, from Foundry's own feat packs.
  #
  # Toughness adds hit points equal to your level, Fleet adds five feet of speed, Incredible Initiative
  # adds two to initiative. None of those is code here: each is a row of config the feat carries, and
  # the engine never learns their names.
  describe "feat rules", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Feat#{rand(1000000)}")
      @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
      @combat = Pf2eCombat.create(:character => @char, :perception => 'expert')
      @char.update(:hp => @hp, :combat => @combat, :pf2_level => 10, :pf2_conditions => {},
                   :pf2_traits => [], :pf2_base_info => {},
                   :pf2_movement => { 'base_speed' => 25 },
                   :pf2_feats => { 'general' => [] })
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
    end

    after(:each) do
      @abilities.each(&:delete)
      @hp&.delete
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def with_feat(name)
      @char.update(:pf2_feats => { 'general' => [ name ] })

      reread
    end

    it "should have rules on the feats that carry them" do
      expect(Global.read_config('pf2e_feats', 'Toughness', 'rules')).to_not be_nil
    end

    # Toughness is `hp` = `@actor.level`, verbatim from their data.
    it "should add hit points equal to level for Toughness" do
      before = Pf2eHP.get_max_hp(reread)

      expect(Pf2eHP.get_max_hp(with_feat('Toughness'))).to eq before + 10
    end

    it "should add five feet of speed for Fleet" do
      before = Pf2e::Stat.total(reread, 'speed')

      expect(Pf2e::Stat.total(with_feat('Fleet'), 'speed')).to eq before + 5
    end

    it "should name the feat in the breakdown rather than only in the total" do
      sources = Pf2e::Stat.of(with_feat('Toughness'), 'hp')['modifiers'].map { |row| row['source'] }

      expect(sources).to include 'Toughness'
    end

    # Some feats write a value rather than adding a modifier. Toughness is both: hit points equal to
    # level, and a lower DC to recover from dying - the second half of the feat, which nothing read
    # before the writable paths existed.
    describe "a feat that writes a value" do
      it "should lower the DC to recover from dying" do
        with_feat('Toughness')

        expect(Pf2e::Paths.apply_all!(reread)).to be > 0
        expect(Pf2e::Paths.held(reread, 'dying_recovery_dc')).to eq(-1)
      end

      it "should write nothing for a character without the feat" do
        Pf2e::Paths.apply_all!(reread)

        expect(Pf2e::Paths.held(reread, 'dying_recovery_dc')).to be_nil
      end

      # Hefty Hauler writes two paths, and both are additions.
      it "should add carrying capacity" do
        with_feat('Hefty Hauler')
        Pf2e::Paths.apply_all!(reread)

        expect(Pf2e::Paths.held(reread, 'maxaddend')).to eq 2
        expect(Pf2e::Paths.held(reread, 'encumberedafteraddend')).to eq 2
      end

      # Applied again on every fold, because the fold would otherwise take it off - which is why these
      # are derived rather than written to the ledger. The store is emptied first, or an addition would
      # count twice.
      it "should come to the same thing applied twice" do
        with_feat('Hefty Hauler')
        Pf2e::Paths.apply_all!(reread)
        Pf2e::Paths.apply_all!(reread)

        expect(Pf2e::Paths.held(reread, 'maxaddend')).to eq 2
      end

      it "should refuse a path the registry does not know" do
        expect(Pf2e::Paths.apply!(reread, 'system.attributes.hp.max', 'add', 10)).to be false
      end
    end

    # Initiative is a Perception check that also answers to `initiative`, so a feat written against
    # initiative reaches it without anything here knowing the feat exists.
    describe "initiative" do
      it "should be the perception bonus when nothing modifies it" do
        expect(Pf2e.initiative_bonus(reread, 'Perception')).to eq Pf2eCombat.get_perception(reread)
      end

      it "should take a bonus written against initiative" do
        before = Pf2e.initiative_bonus(reread, 'Perception')

        expect(Pf2e.initiative_bonus(with_feat('Incredible Initiative'), 'Perception')).to eq before + 2
      end

      # The same feat reaches initiative rolled off a skill, because the domain is the same.
      it "should take it when initiative is rolled off a skill" do
        before = Pf2e.initiative_bonus(reread, 'Stealth')

        expect(Pf2e.initiative_bonus(with_feat('Incredible Initiative'), 'Stealth')).to eq before + 2
      end

      # A Perception check that is not initiative does not get it.
      it "should not leak into an ordinary perception check" do
        before = Pf2eCombat.get_perception(reread)

        expect(Pf2eCombat.get_perception(with_feat('Incredible Initiative'))).to eq before
      end

      it "should read an attribute when the scene runner names one" do
        expect(Pf2e.initiative_bonus(reread, 'Dexterity')).to eq 2
      end
    end
  end
end
