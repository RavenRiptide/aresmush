require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Items a feat hands over: an egalrin's feather fan, made at the commit boundaries, never sold, and
    # usable only while they hold the feat.
    describe BoundItems, :dbtest => true do

      class BoundItemClient
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

      let(:fan) { 'Egalrin Feather Fan' }

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = BoundItemClient.new
        @char = Character.create(:name => "Fan#{rand(1000000)}", :pf2_level => 5, :pf2_money => 0,
                                 :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Egalrin' },
                                 :pf2_feats => { 'ancestry' => [ fan ] })

        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
      end

      after(:each) do
        char.magic_items.each(&:delete)
        @char.delete
      end

      def char
        Character[@char.id]
      end

      def fans
        char.magic_items.to_a.select { |item| item.name == fan }
      end

      def number
        Pf2egear::Inventory.held(char, 'magicitem').index { |item| item.name == fan }
      end

      it "should name a catalogue item no vendor sells, for every feat that binds one" do
        feats = Global.read_config('pf2e_feats')
        bound = feats.select { |_name, info| info.is_a?(Hash) && info['bound_item'] }

        expect(bound.keys).to include fan

        bound.each_value do |info|
          block = info['bound_item']
          item = Global.read_config(Pf2egear::Inventory.config(block['category']), block['item'])

          expect(item).to be_a Hash
          expect(item['made_only']).to be true
        end

        items = bound.values.map { |info| info['bound_item']['item'] }
        adds = feats.values.select { |info| info.is_a?(Hash) && info['bound_item_adds'] }.map { |info| info['bound_item_adds']['item'] }

        expect(adds - items).to eq []
      end

      describe "settling" do
        it "should make the item once, bound to the feat, at their level" do
          expect(BoundItems.settle!(char)).to eq [ fan ]
          expect(BoundItems.settle!(char)).to eq []

          expect(fans.size).to eq 1
          expect(fans.first.bound_to).to eq fan
          expect(fans.first.level).to eq 5
        end

        it "should keep the item's level at theirs as they level" do
          BoundItems.settle!(char)
          @char.update(:pf2_level => 6)
          BoundItems.settle!(char)

          expect(fans.map(&:level)).to eq [ 6 ]
        end

        it "should make nothing for someone without the feat" do
          @char.update(:pf2_feats => { 'ancestry' => [] })

          expect(BoundItems.settle!(char)).to eq []
          expect(fans).to eq []
        end
      end

      describe "without the feat" do
        before(:each) do
          BoundItems.settle!(char)
          @char.update(:pf2_feats => { 'ancestry' => [] })
        end

        it "should be inert, and usable again once they hold the feat" do
          expect(BoundItems.usable?(char, fans.first)).to be false

          @char.update(:pf2_feats => { 'ancestry' => [ fan ] })

          expect(BoundItems.usable?(char, fans.first)).to be true
        end

        it "should refuse to be used" do
          Pf2egear::PF2UseItemCmd.new(@client, Command.new("use magicitem=#{number}"), char).on_command

          expect(@client.failures).to eq [ t('pf2e.bound_item_cannot_use', :item => fan, :feat => fan) ]
        end

        it "should say so in the gear listing" do
          listing = Pf2egear::Pf2eDisplayGearTemplate.new(char, @client).render

          expect(listing).to include "#{fan} #{t('pf2e.bound_item_inert_mark')}"
        end
      end

      it "should not be sold" do
        BoundItems.settle!(char)
        Pf2egear::PF2SellCmd.new(@client, Command.new("sell magicitem=#{number}"), char).on_command

        expect(@client.failures).to eq [ t('pf2egear.cannot_sell_made', :item => fan) ]
        expect(fans.size).to eq 1
        expect(char.pf2_money.to_i).to eq 0
      end

      it "should hold more spells and activations as later feats add them, up to three activations" do
        BoundItems.settle!(char)

        expect(BoundItems.holds(char, fans.first)).to eq('spells' => [ { 'name' => 'Gust of Wind', 'rank' => 1 } ],
                                                         'activations' => 1)

        @char.update(:pf2_feats => { 'ancestry' => [ fan, "Wind God's Fan", "Thunder God's Fan" ] })
        held = BoundItems.holds(char, fans.first)

        expect(held['spells'].map { |spell| spell['name'] }).to eq [ 'Gust of Wind', 'Wall of Wind', 'Lightning Bolt' ]
        expect(held['activations']).to eq 3
      end
    end
  end
end
