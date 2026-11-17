require "plugin_test_loader"

module AresMUSH

  # Ancestry feats the setting renames. Foundry's rules are matched to our feats by name, so Orc
  # Superstition never found Oruch Superstition and took no rules; these feats did nothing in play.
  describe "renamed ancestry feats", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Renamed#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char, :perception => 'trained',
                                  :saves => { 'Fortitude' => 'trained', 'Reflex' => 'trained', 'Will' => 'trained' })
      @char.update(:combat => @combat, :pf2_level => 9, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_base_info => {}, :pf2_feats => { 'ancestry' => [] })
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
    end

    after(:each) do
      @abilities.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def with_feats(*names)
      @char.update(:pf2_feats => { 'ancestry' => names })
    end

    def will(options = [])
      Pf2e::Check.of(reread, 'save', 'will', options)
    end

    # A degree adjustment's outcome for a roll that came to `degree` (0 critical failure .. 3 critical success).
    def adjusted(check, degree)
      Pf2e::Degree.adjusted(degree, check.adjustments)
    end

    SPELL = [ 'item:type:spell', 'arcane' ].freeze

    describe "Oruch Superstition" do
      it "should give nothing until the player uses it" do
        before = will(SPELL).total
        with_feats('Oruch Superstition')

        expect(will(SPELL).total).to eq before
      end

      it "should add +1 to a save against a spell when used" do
        before = will(SPELL).total
        with_feats('Oruch Superstition')
        Pf2e::RollOptions.set(reread, 'orc-superstition', true)

        expect(will(SPELL).total).to eq before + 1
      end

      it "should not add to a save against something that is not magic" do
        before = will.total
        with_feats('Oruch Superstition')
        Pf2e::RollOptions.set(reread, 'orc-superstition', true)

        expect(will.total).to eq before
      end
    end

    # Pervasive Superstition switches Oruch Superstition's bonus on for good. Until Oruch Superstition had
    # its rules, it switched on a bonus nothing gave.
    describe "Pervasive Superstition" do
      it "should add +1 to every save against a spell without being used" do
        before = will(SPELL).total
        with_feats('Oruch Superstition', 'Pervasive Superstition')

        expect(will(SPELL).total).to eq before + 1
      end
    end

    describe "Irrepressible (Bassin)" do
      before(:each) { with_feats('Irrepressible (Bassin)') }

      it "should make a success against an emotion effect a critical success" do
        expect(adjusted(will([ 'item:trait:emotion' ]), 2)).to eq 3
      end

      it "should leave a save against anything else alone" do
        expect(adjusted(will, 2)).to eq 2
      end

      it "should make a gutsy bassin's critical failure against an emotion effect a failure" do
        @char.update(:pf2_base_info => { 'heritage' => 'Gutsy' })

        expect(adjusted(will([ 'item:trait:emotion' ]), 0)).to eq 1
      end

      it "should leave another bassin's critical failure alone" do
        expect(adjusted(will([ 'item:trait:emotion' ]), 0)).to eq 0
      end
    end

    describe "Unfettered Bassin" do
      it "should make a successful Escape a critical success" do
        with_feats('Unfettered Bassin')
        @skill = Pf2eSkills.create(:name => 'Acrobatics', :character => @char, :prof_level => 'trained')

        expect(adjusted(Pf2e::Check.of(reread, 'skill', 'Acrobatics', [ 'action:escape' ]), 2)).to eq 3
      ensure
        @skill&.delete
      end
    end

    describe "Watchful Bassin" do
      it "should add +2 to Sense Motive against a possessed creature" do
        options = [ 'action:sense-motive', 'target:trait:possessed' ]
        before = Pf2e::Check.of(reread, 'perception', nil, options).total
        with_feats('Watchful Bassin')

        expect(Pf2e::Check.of(reread, 'perception', nil, options).total).to eq before + 2
      end
    end
  end
end
