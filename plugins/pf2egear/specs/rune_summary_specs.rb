require "plugin_test_loader"

module AresMUSH
  module Pf2egear

    # `gear` lists an item's runes under it in PF2e's shorthand, so the name stays free for a nickname.
    describe "an item's rune summary", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config
      end

      def item(runes)
        double('item', :runes => runes)
      end

      def shield(grade)
        double('shield', :runes => { 'fundamental' => { 'reinforcing' => grade } })
      end

      it "should have nothing to say for an item with no runes" do
        expect(Pf2egear.rune_summary(item({}), 'weapons')).to be_nil
        expect(Pf2egear.rune_summary(item(nil), 'armor')).to be_nil
        expect(Pf2egear.rune_summary(item({ 'fundamental' => { 'potency' => 0, 'power' => 0 } }), 'weapons')).to be_nil
      end

      it "should give a potency rune alone" do
        expect(Pf2egear.rune_summary(item({ 'fundamental' => { 'potency' => 1 } }), 'weapons')).to eq '+1'
      end

      it "should give potency and striking on a weapon" do
        runes = { 'fundamental' => { 'potency' => 2, 'power' => 2 } }

        expect(Pf2egear.rune_summary(item(runes), 'weapons')).to eq '+2 Greater Striking'
        expect(Pf2egear.rune_summary(item(runes), 'weapon')).to eq '+2 Greater Striking'
      end

      it "should call the same rune resilient on armor" do
        runes = { 'fundamental' => { 'potency' => 1, 'power' => 1 } }

        expect(Pf2egear.rune_summary(item(runes), 'armor')).to eq '+1 Resilient'
      end

      it "should list property runes after the fundamental ones, sorted" do
        runes = { 'fundamental' => { 'potency' => 2, 'power' => 3 },
                  'property' => { 'list' => [ 'Frost', 'Flaming' ] } }

        expect(Pf2egear.rune_summary(item(runes), 'weapons')).to eq '+2 Major Striking; Flaming, Frost'
      end

      it "should list property runes alone on an item with no fundamental ones" do
        runes = { 'property' => { 'list' => [ 'Slick' ] } }

        expect(Pf2egear.rune_summary(item(runes), 'armor')).to eq 'Slick'
      end

      # A specific magic item's catalogue row, and an item made from one before `build_item` put it
      # right, keeps the list bare.
      it "should read property runes kept as a bare list" do
        runes = { 'fundamental' => { 'potency' => 1 }, 'property' => [ 'Ghost Touch' ] }

        expect(Pf2egear.rune_summary(item(runes), 'weapons')).to eq '+1; Ghost Touch'
      end

      it "should give a shield's reinforcing rune" do
        expect(Pf2egear.rune_summary(shield(1), 'shields')).to eq 'Minor Reinforcing'
        expect(Pf2egear.rune_summary(shield(0), 'shields')).to be_nil
      end

      it "should have nothing to say for a category that takes no runes" do
        expect(Pf2egear.rune_summary(item({ 'fundamental' => { 'potency' => 1 } }), 'magicitem')).to be_nil
      end

      describe "in the gear list" do
        def template
          Pf2eDisplayGearTemplate.new(nil, double('client', :screen_reader => false))
        end

        it "should put the runes on a line under the item" do
          line = template.rune_line(item({ 'fundamental' => { 'potency' => 1, 'power' => 1 } }), 'weapons')

          expect(line).to start_with '%r%b%b%b%b%b%b%b%b'
          expect(line).to end_with 'Runes:%xn +1 Striking'
        end

        it "should add no line for an item with no runes" do
          expect(template.rune_line(item({}), 'weapons')).to eq ''
        end
      end
    end
  end
end
