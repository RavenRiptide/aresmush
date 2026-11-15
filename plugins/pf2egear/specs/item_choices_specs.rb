require "plugin_test_loader"

module AresMUSH

  # Investing some items requires a choice, and the item's rules read it: a Charm of Resistance resists the
  # damage type chosen, and an Entertainer's Cincture adds to the skill chosen. The choice is kept on the
  # item, so it goes wherever the item goes.
  #
  # A Helm of Zeal needs no choice at `invest`. Its deity is fixed when it's made, so the player specifies it
  # at `buy`, and the helm's bonus is to that deity's Divine Skill.
  describe "item choices", :dbtest => true do

    class ItemChoiceClient
      attr_reader :failures, :said

      def initialize
        @failures = []
        @said = []
      end

      def logged_in?
        true
      end

      def screen_reader
        false
      end

      def emit_failure(message)
        @failures << message.to_s
      end

      %w{emit_success emit emit_ooc}.each { |name| define_method(name) { |message| @said << message.to_s } }
    end

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @client = ItemChoiceClient.new
      @char = Character.create(:name => "Invest#{rand(1000000)}", :pf2_level => 11, :pf2_money => 500_000,
                               :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {},
                               :pf2_level_tracker => {})
      @combat = Pf2eCombat.create(:character => @char)
      @char.update(:combat => @combat)
      @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12) }
      @skills = %w{Medicine Diplomacy Deception}.map { |name| Pf2eSkills.create_skill_for_char(name, @char) }

      allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
    end

    after(:each) do
      PF2MagicItem.find(:character_id => @char.id).each(&:delete)
      (@skills + @abilities + [ @combat, @char ]).each { |one| one&.delete }
    end

    def reread
      Character[@char.id]
    end

    def run(klass, text)
      klass.new(@client, Command.new(text), reread).on_command
    end

    def give(name)
      Pf2egear.create_item(@char, 'magicitem', name, 1, Global.read_config('pf2e_magicitem', name))
    end

    def item
      reread.magic_items.to_a.first
    end

    def resisted
      Pf2e::IWR.of(reread)['resistance'].map { |one| one['type'] }
    end

    describe "a choice made when investing" do
      it "should refuse to invest without a choice, and list the choices" do
        give('Charm of Resistance')
        run(Pf2egear::PF2InvestCmd, 'invest magicitem/0')

        expect(@client.failures).to eq [ t('pf2egear.invest_needs_choice', :item => 'Charm of Resistance',
                                           :choices => 'Acid, Cold, Electricity, Fire, Sonic',
                                           :cmd => 'invest magicitem/0/<choice>') ]
        expect(item.invested).to be_falsey
        expect(resisted).to eq []
      end

      it "should keep the choice on the item, and the rules should read it" do
        give('Charm of Resistance')
        run(Pf2egear::PF2InvestCmd, 'invest magicitem/0/fire')

        expect(@client.failures).to eq []
        expect(item.invested).to be true
        expect(item.answers).to eq [ 'fire' ]
        expect(resisted).to eq [ 'fire' ]
      end

      it "should take a choice typed as its label" do
        give('Charm of Resistance')
        run(Pf2egear::PF2InvestCmd, 'invest magicitem/0/Electricity')

        expect(item.answers).to eq [ 'electricity' ]
      end

      it "should refuse a choice the item doesn't have" do
        give('Charm of Resistance')
        run(Pf2egear::PF2InvestCmd, 'invest magicitem/0/acrobatics')

        expect(@client.failures).to eq [ t('pf2egear.invest_bad_choice', :item => 'Charm of Resistance', :choice => 'acrobatics',
                                           :choices => 'Acid, Cold, Electricity, Fire, Sonic') ]
        expect(item.invested).to be_falsey
      end

      it "should keep the choice when invested again without one, and take a new one after uninvesting" do
        give('Charm of Resistance')
        run(Pf2egear::PF2InvestCmd, 'invest magicitem/0/fire')
        run(Pf2egear::PF2UninvestCmd, 'uninvest magicitem/0')
        run(Pf2egear::PF2InvestCmd, 'invest magicitem/0')

        expect(item.answers).to eq [ 'fire' ]

        run(Pf2egear::PF2UninvestCmd, 'uninvest magicitem/0')
        run(Pf2egear::PF2InvestCmd, 'invest magicitem/0/cold')

        expect(resisted).to eq [ 'cold' ]
      end

      it "should read a skill chosen when invested" do
        give("Entertainer's Cincture")
        diplomacy = Pf2eSkills.get_skill_bonus(reread, 'Diplomacy')
        deception = Pf2eSkills.get_skill_bonus(reread, 'Deception')

        run(Pf2egear::PF2InvestCmd, 'invest magicitem/0/diplomacy')

        expect(@client.failures).to eq []
        expect(Pf2eSkills.get_skill_bonus(reread, 'Diplomacy')).to eq diplomacy + 2
        expect(Pf2eSkills.get_skill_bonus(reread, 'Deception')).to eq deception
      end

      it "should list the choices an item requires, and none for a toggle or a deity's item" do
        expect(Pf2e::ItemChoices.questions('Charm of Resistance', Global.read_config('pf2e_magicitem', 'Charm of Resistance'))
                 .map { |one| [ one['key'], one['answers'].map(&:first) ] })
          .to eq [ [ 'damageType', %w{acid cold electricity fire sonic} ] ]
        expect(Pf2e::ItemChoices.questions('Shadow Signet', Global.read_config('pf2e_magicitem', 'Shadow Signet'))).to eq []
        expect(Pf2e::ItemChoices.questions('Helm of Zeal', Global.read_config('pf2e_magicitem', 'Helm of Zeal'))).to eq []
      end
    end

    it "should show in the item view the choice made, and the deity a helm was made for" do
      give('Charm of Resistance')
      run(Pf2egear::PF2InvestCmd, 'invest magicitem/0/fire')

      expect(Pf2e::ItemChoices.describe(item, Global.read_config('pf2e_magicitem', 'Charm of Resistance')))
        .to eq [ t('pf2egear.item_choice', :choice => 'Fire') ]

      item.delete
      run(Pf2egear::PF2BuyCmd, 'buy magicitem=Helm of Zeal/Althea')

      expect(Pf2e::ItemChoices.describe(item, Global.read_config('pf2e_magicitem', 'Helm of Zeal')))
        .to eq [ t('pf2egear.item_made_for', :deity => 'Althea', :skill => 'Medicine') ]
    end

    describe "a Helm of Zeal" do
      it "should be bought for a deity, and give that deity's Divine Skill its bonus once invested" do
        medicine = Pf2eSkills.get_skill_bonus(reread, 'Medicine')
        diplomacy = Pf2eSkills.get_skill_bonus(reread, 'Diplomacy')

        run(Pf2egear::PF2BuyCmd, 'buy magicitem=Helm of Zeal/althea')

        expect(@client.failures).to eq []
        expect([ item.name, item.deity ]).to eq [ 'Helm of Zeal', 'Althea' ]

        run(Pf2egear::PF2InvestCmd, 'invest magicitem/0')

        expect(@client.failures).to eq []
        expect(item.invested).to be true
        expect(Pf2eSkills.get_skill_bonus(reread, 'Medicine')).to eq medicine + 2
        expect(Pf2eSkills.get_skill_bonus(reread, 'Diplomacy')).to eq diplomacy
      end

      it "should refuse a purchase with no deity specified, or one the game doesn't have" do
        run(Pf2egear::PF2BuyCmd, 'buy magicitem=Helm of Zeal')
        run(Pf2egear::PF2BuyCmd, 'buy magicitem=Helm of Zeal/Nobody')

        deities = Global.read_config('pf2e_deities').keys.sort.join(', ')

        expect(@client.failures).to eq [ t('pf2egear.buy_needs_deity', :item => 'Helm of Zeal', :deities => deities),
                                         t('pf2egear.buy_bad_deity', :deity => 'Nobody', :deities => deities) ]
        expect(item).to be_nil
      end

      it "should still take a number as how many, for anything else" do
        run(Pf2egear::PF2BuyCmd, 'buy magicitem=Charm of Resistance/1')

        expect(@client.failures).to eq []
        expect(item.name).to eq 'Charm of Resistance'
      end
    end
  end
end
