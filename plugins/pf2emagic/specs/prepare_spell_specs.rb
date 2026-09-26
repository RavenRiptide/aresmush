require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Preparing a spell reaches the tradition check for every prepared caster, so the check has to
    # read the class's tradition.
    describe "preparing a spell", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Prepare#{rand(1000000)}")
        @magic = PF2Magic.create(:character => @char,
                                 :tradition => { 'Cleric' => [ 'divine', 'trained' ] },
                                 :spell_abil => { 'Cleric' => 'Wisdom' },
                                 :spells_per_day => { 'Cleric' => { '1' => 2 } })
        @char.update(:magic => @magic, :pf2_base_info => { 'charclass' => 'Cleric' }, :pf2_level => 1)
      end

      after(:each) do
        @magic.delete if @magic
        @char.delete if @char
      end

      it "should prepare a spell of the class's tradition" do
        result = Pf2emagic.prepare_spell('Fear', Character[@char.id], 'Cleric', '1')

        expect(result).to be_a Hash
        expect(PF2Magic[@magic.id].spells_prepared['Cleric']['1']).to eq [ 'Fear' ]
      end

      it "should refuse a spell off the class's tradition" do
        result = Pf2emagic.prepare_spell('Force Barrage', Character[@char.id], 'Cleric', '1')

        expect(result).to eq t('pf2emagic.cant_prepare_trad', :cc => 'Cleric')
      end
    end
  end
end
