require "plugin_test_loader"

module AresMUSH

  # A bag with the invested trait, such as a voyager's pack, is invested like a magic item: its own rules
  # apply only while it is, and the day's preparations invest it again.
  describe "invested bags", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Packer#{rand(1000000)}", :pf2_level => 17, :pf2_conditions => {}, :pf2_traits => [],
                               :pf2_derived => {}, :pf2_feats => {}, :pf2_apex => {})
      @combat = Pf2eCombat.create(:character => @char)
      @char.update(:combat => @combat)
      @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12) }
      @skill = Pf2eSkills.create_skill_for_char('Survival', @char)
      @said = []
      @client = double('client')
      allow(@client).to receive(:emit_success) { |message| @said << message }
      allow(@client).to receive(:emit_failure) { |message| @said << message }
      allow(@client).to receive(:emit_ooc) { |message| @said << message }
    end

    after(:each) do
      PF2Bag.find(:character_id => @char.id).each(&:delete)
      (@abilities + [ @skill, @combat, @char ]).each(&:delete)
    end

    def reread
      Character[@char.id]
    end

    def give(name)
      Pf2egear.create_item(@char, 'bags', name, 1, Global.read_config('pf2e_bags', name))
    end

    def run(klass, text)
      cmd = klass.new(@client, Command.new(text), reread)
      cmd.parse_args
      cmd.handle
    end

    def survival
      Pf2eSkills.get_skill_bonus(reread, 'Survival')
    end

    it "should give a voyager's pack's Survival bonus only while it's invested" do
      give("Voyager's Pack")
      plain = survival

      expect(survival).to eq plain

      run(Pf2egear::PF2InvestCmd, 'invest bags/0')

      expect(reread.bags.to_a.first.invested).to be true
      expect(survival).to eq plain + 3

      run(Pf2egear::PF2UninvestCmd, 'uninvest bags/0')

      expect(survival).to eq plain
    end

    it "should invest it again at the day's preparations, and count it among invested items" do
      give("Voyager's Pack")
      run(Pf2egear::PF2InvestCmd, 'invest bags/0')
      Pf2e.do_daily_investiture(reread)

      expect(Pf2egear.get_invested_items(reread).map(&:name)).to eq [ "Voyager's Pack" ]
    end

    it "should not invest a bag without the invested trait" do
      give('Backpack')
      run(Pf2egear::PF2InvestCmd, 'invest bags/0')

      expect(reread.bags.to_a.first.invested).to be_falsey
      expect(@said.first).to eq t('pf2egear.not_investible_item', :item => 'Backpack')
    end

    it "should sell barding of the zephyr as gear, its armor kept for companions" do
      info = Global.read_config('pf2e_gear', 'Barding of the Zephyr')

      expect(info.values_at('level', 'price')).to eq [ 10, 90000 ]
      expect(info['traits']).to include 'companion'
      expect(info['companion_armor']['ac_bonus']).to eq 1
    end

    # Player Core: light barding is AC +1, Dex cap +5; heavy barding is AC +3, Dex cap +3.
    it "should keep armor stats on every barding" do
      bardings = Global.read_config('pf2e_gear').select { |_name, info| Array((info || {})['traits']).include?('barding') }

      expect(bardings.keys).to include('Light Barding (Small or Medium)', 'Light Barding (Large)',
                                       'Heavy Barding (Small or Medium)', 'Heavy Barding (Large)')
      bardings.each do |name, info|
        armor = info['companion_armor']
        expected = armor && armor['category'] == 'heavy-barding' ? [ 3, 3 ] : [ 1, 5 ]

        expect(armor && armor.values_at('ac_bonus', 'dex_cap')).to eq(expected), name
      end
    end
  end
end
