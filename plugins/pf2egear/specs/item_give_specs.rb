require "plugin_test_loader"

module AresMUSH

  # Staff creating an item and giving it to a character: what a commission crafting request made, or a GM's
  # loot. The recipient pays the catalogue price and can't receive an item above their own level unless
  # staff say so.
  describe "item/give", :dbtest => true do

    class ItemGiveClient
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

      @client = ItemGiveClient.new
      @staff = Character.create(:name => "Staff#{rand(1000000)}")
      @char = Character.create(:name => "Given#{rand(1000000)}", :pf2_level => 6, :pf2_money => 100_000)

      allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
      allow_any_instance_of(Character).to receive(:has_permission?).and_return(true)
      allow(Login).to receive(:notify)
      allow(Login).to receive(:find_game_client).and_return(nil)
    end

    after(:each) do
      PF2Encounter[@encounter.id]&.delete if @encounter
      PF2MagicItem.find(:character_id => @char.id).each(&:delete)
      [ @char, @staff ].each { |one| one&.delete }
    end

    def reread
      Character[@char.id]
    end

    def give(text)
      Pf2egear::PF2ItemGiveCmd.new(@client, Command.new(text), Character[@staff.id]).on_command
    end

    def items
      reread.magic_items.to_a
    end

    it "should give the item and take its catalogue price" do
      give("item/give #{@char.name}=magicitem/Charm of Resistance")

      expect(@client.failures).to eq []
      expect(items.map(&:name)).to eq [ 'Charm of Resistance' ]
      expect(reread.pf2_money).to eq 100_000 - 24_500
    end

    it "should refuse an item above the character's level, and give it with force, still charging" do
      give("item/give #{@char.name}=magicitem/Collar of Inconspicuousness")

      expect(@client.failures).to eq [ t('pf2egear.give_too_high', :item => 'Collar of Inconspicuousness', :level => 8,
                                         :char => @char.name, :char_level => 6) ]
      expect(items).to eq []

      give("item/give/force #{@char.name}=magicitem/Collar of Inconspicuousness")

      expect(items.map(&:name)).to eq [ 'Collar of Inconspicuousness' ]
      expect(reread.pf2_money).to eq 100_000 - 47_500
    end

    it "should give an item free, whatever its level" do
      give("item/give/free #{@char.name}=magicitem/Earthglide Cloak")

      expect(@client.failures).to eq []
      expect(items.map(&:name)).to eq [ 'Earthglide Cloak' ]
      expect(reread.pf2_money).to eq 100_000
    end

    it "should refuse an item the character can't afford" do
      @char.update(:pf2_money => 100)
      give("item/give #{@char.name}=magicitem/Charm of Resistance")

      expect(@client.failures).to eq [ t('pf2egear.give_cant_afford', :char => @char.name, :item => 'Charm of Resistance',
                                         :cost => Pf2egear.display_money(24_500)) ]
      expect(items).to eq []
    end

    it "should need a deity for an item made for one, and keep it on the item" do
      @char.update(:pf2_level => 11, :pf2_money => 200_000)

      give("item/give #{@char.name}=magicitem/Helm of Zeal")
      give("item/give #{@char.name}=magicitem/Helm of Zeal/althea")

      expect(@client.failures.size).to eq 1
      expect([ items.map(&:name), items.map(&:deity) ]).to eq [ [ 'Helm of Zeal' ], [ 'Althea' ] ]
      expect(reread.pf2_money).to eq 200_000 - 125_000
    end

    it "should refuse a deity for an item that isn't made for one" do
      give("item/give #{@char.name}=magicitem/Charm of Resistance/Althea")

      expect(@client.failures).to eq [ t('pf2egear.give_no_deity', :item => 'Charm of Resistance', :extra => 'Althea') ]
    end

    it "should find an item by the start of its name, and refuse one it can't tell apart" do
      give("item/give #{@char.name}=magicitem/Walking Caul")
      give("item/give #{@char.name}=magicitem/Charm of Res")
      give("item/give #{@char.name}=magicitem/Nothing Like This")

      expect(items.map(&:name)).to eq [ 'Walking Cauldron' ]
      expect(@client.failures).to eq [
        t('pf2egear.give_ambiguous', :item => 'Charm of Res',
                                     :matches => 'Charm of Resistance, Charm of Resistance (Greater), Charm of Resistance (Major)'),
        t('pf2egear.give_no_item', :item => 'Nothing Like This', :category => 'magicitem') ]
    end

    it "should refuse an item only a feat makes, and a character in a running encounter" do
      give("item/give/free #{@char.name}=magicitem/Egalrin Feather Fan")

      @encounter = PF2Encounter.create(:organizer => @staff.name, :round => 1, :is_active => true)
      reread.encounters.add @encounter
      give("item/give #{@char.name}=magicitem/Charm of Resistance")

      expect(@client.failures).to eq [ t('pf2egear.give_made_only', :item => 'Egalrin Feather Fan'),
                                       t('pf2egear.give_in_encounter', :char => @char.name, :id => @encounter.id) ]
      expect(items).to eq []
    end

    it "should be for staff only" do
      allow_any_instance_of(Character).to receive(:has_permission?).and_return(false)
      give("item/give #{@char.name}=magicitem/Charm of Resistance")

      expect(@client.failures).to eq [ t('dispatcher.not_allowed') ]
      expect(items).to eq []
    end
  end
end
