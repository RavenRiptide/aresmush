require "plugin_test_loader"

module AresMUSH
  module Pf2egear

    # Buying a rune for an item a character holds (`RuneVendor`, `buy/rune`, `browse rune`).
    describe "buying a rune", :dbtest => true do

      class BuyRuneClient
        attr_reader :successes, :failures, :said

        def initialize
          @successes = []
          @failures = []
          @said = []
        end

        def logged_in?
          true
        end

        def emit_success(msg)
          @successes << msg.to_s
        end

        def emit_failure(msg)
          @failures << msg.to_s
        end

        def emit(msg)
          @said << msg.to_s
        end

        def emit_ooc(msg)
          @said << msg.to_s
        end
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = BuyRuneClient.new
        @char = Character.create(:name => "Runebuyer#{rand(1000000)}", :pf2_level => 20)
        Pf2egear.pay_player(@char, 10_000_000, 'spec')
        @made = [ @char ]
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
      end

      after(:each) do
        @made.each { |one| one&.delete }
      end

      def item(category, name)
        made = Pf2egear.create_item(@char, category, name, 1, Global.read_config("pf2e_#{category}", name))
        @made << made
        made
      end

      def char
        Character[@char.id]
      end

      def quote(made, category, rune)
        RuneVendor.quote(char, made, category, rune)
      end

      def buy(made, category, rune)
        found = quote(made, category, rune)

        expect(found.ok?).to be(true), "expected to buy #{rune}, got #{found.respond_to?(:code) && found.code}"
        RuneVendor.etch!(char, made, found.state)
        found.state
      end

      def code(made, category, rune)
        found = quote(made, category, rune)

        found.ok? ? :ok : found.code
      end

      def reread(made)
        made.class[made.id]
      end

      describe "a fundamental rune" do
        before(:each) { @sword = item('weapons', 'Longsword') }

        it "should etch it, take its price, and add the price to the item's" do
          money = char.pf2_money
          price = reread(@sword).price

          buy(@sword, 'weapons', '+1 potency')

          expect(reread(@sword).runes.dig('fundamental', 'potency')).to eq 1
          expect(char.pf2_money).to eq money - 3500
          expect(reread(@sword).price).to eq price + 3500
        end

        it "should know a rune by its name in any order, without its kind" do
          expect(quote(@sword, 'weapons', 'Weapon Potency (+1)').state['grade']).to eq 1
          expect(quote(@sword, 'weapons', 'potency +1').state['grade']).to eq 1
        end

        it "should charge the difference to raise one the item has" do
          buy(@sword, 'weapons', '+1 Weapon Potency')

          found = quote(reread(@sword), 'weapons', '+2 Weapon Potency').state

          expect(found['cost']).to eq 93500 - 3500
          expect(found['replaces']).to eq '+1 Weapon Potency'
        end

        it "should refuse a grade the item has or passes" do
          buy(@sword, 'weapons', '+2 potency')

          expect(code(reread(@sword), 'weapons', '+1 potency')).to eq :has_grade
          expect(code(reread(@sword), 'weapons', '+2 potency')).to eq :has_grade
        end

        it "should need a potency rune at least as high before a striking rune" do
          expect(code(@sword, 'weapons', 'Striking')).to eq :needs_potency

          buy(@sword, 'weapons', '+1 potency')
          buy(reread(@sword), 'weapons', 'Striking')

          expect(reread(@sword).runes.dig('fundamental', 'power')).to eq 1
          expect(code(reread(@sword), 'weapons', 'Greater Striking')).to eq :needs_potency
        end

        it "should sell resilient runes for armor" do
          mail = item('armor', 'Chain Mail')
          buy(mail, 'armor', '+1 potency')

          expect(buy(reread(mail), 'armor', 'Resilient')['cost']).to eq 34000
        end

        it "should refuse a rune above the character's level" do
          @char.update(:pf2_level => 3)

          expect(code(@sword, 'weapons', '+1 potency')).to eq :ok
          expect(code(@sword, 'weapons', 'Striking')).to eq :too_high
        end
      end

      describe "a reinforcing rune" do
        it "should raise the shield's Hardness and Hit Points" do
          shield = item('shields', 'Steel Shield')

          expect(buy(shield, 'shields', 'Minor Reinforcing')['cost']).to eq 7500
          expect(ShieldRunes.hardness(reread(shield))).to eq 8
          expect(ShieldRunes.max_hp(reread(shield))).to eq 64
        end

        it "should refuse a property rune on a shield" do
          expect(code(item('shields', 'Steel Shield'), 'shields', 'Flaming')).to eq :wrong_kind
        end
      end

      describe "a property rune" do
        before(:each) do
          @sword = item('weapons', 'Longsword')
          @sword.update(:runes => { 'fundamental' => { 'potency' => 1 }, 'property' => { 'list' => [] } })
        end

        it "should etch it for its price" do
          expect(buy(@sword, 'weapons', 'Flaming')['cost']).to eq 50000
          expect(reread(@sword).runes.dig('property', 'list')).to eq [ 'Flaming' ]
        end

        it "should charge the difference for a stronger rune of its family, in place of the weaker" do
          buy(@sword, 'weapons', 'Flaming')
          bought = buy(reread(@sword), 'weapons', 'Greater Flaming')

          expect(bought['cost']).to eq 650000 - 50000
          expect(reread(@sword).runes.dig('property', 'list')).to eq [ 'Greater Flaming' ]
        end

        it "should refuse one that doesn't fit" do
          expect(code(@sword, 'weapons', 'Returning')).to eq :wrong_usage
        end

        it "should refuse an uncommon rune nothing opens" do
          expect(code(@sword, 'weapons', 'Keen')).to eq :rare
        end

        it "should refuse a property rune on a specific magic weapon, but raise its fundamental runes" do
          blade = item('weapons', 'Searing Blade')

          expect(code(blade, 'weapons', 'Frost')).to eq :specific
          expect(quote(blade, 'weapons', '+3 potency').state['cost']).to eq 893500 - 93500
        end
      end

      describe "an item that can't take one" do
        it "should refuse one in use in an encounter" do
          sword = item('weapons', 'Longsword')
          allow(Pf2e::Equipment).to receive(:held_by).and_return(double('state', :id => 7))

          expect(code(sword, 'weapons', '+1 potency')).to eq :in_encounter
        end

        it "should refuse one that won't last" do
          sword = item('weapons', 'Longsword')
          sword.update(:expires => 'rest')

          expect(code(sword, 'weapons', '+1 potency')).to eq :temporary
        end
      end

      it "should return half of a rune's price when the item is sold" do
        sword = item('weapons', 'Longsword')
        before = reread(sword).price

        buy(sword, 'weapons', '+1 potency')

        expect(reread(sword).price / 2).to eq (before + 3500) / 2
      end

      describe "the command" do
        def run(text)
          PF2BuyRuneCmd.new(@client, Command.new(text), char).on_command
        end

        before(:each) { @sword = item('weapons', 'Longsword') }

        it "should buy and etch it" do
          run('buy/rune weapons/0=+1 potency')

          expect(@client.failures).to eq []
          expect(@client.successes.join).to include '+1 Weapon Potency'
          expect(reread(@sword).runes.dig('fundamental', 'potency')).to eq 1
        end

        it "should refuse what the character can't pay for" do
          Pf2egear.pay_player(@char, -char.pf2_money, 'spec')
          run('buy/rune weapons/0=+1 potency')

          expect(@client.failures).to_not eq []
          expect(reread(@sword).runes.dig('fundamental', 'potency').to_i).to eq 0
        end

        it "should say why a rune doesn't fit" do
          run('buy/rune weapons/0=Striking')

          expect(@client.failures.join).to include 'potency rune of +1'
        end

        it "should refuse someone not yet approved" do
          allow_any_instance_of(Character).to receive(:is_approved?).and_return(false)
          run('buy/rune weapons/0=+1 potency')

          expect(@client.failures).to eq [ t('dispatcher.not_allowed') ]
        end
      end

      describe "browsing" do
        def lines
          PF2BrowseGearCmd.new(@client, Command.new('browse rune'), char).rune_lines
        end

        it "should list every fundamental grade and what a limited rune is for" do
          expect(lines.join("\n")).to include('+3 Weapon Potency', 'Major Striking', 'Supreme Reinforcing',
                                              'Returning', 'only on a thrown weapon')
        end

        it "should leave out what the character can't buy" do
          @char.update(:pf2_level => 5)

          expect(lines.join("\n")).to include 'Ghost Touch'
          expect(lines.join("\n")).to_not include 'Keen'
          expect(lines.join("\n")).to_not include 'Flaming'
        end
      end
    end
  end
end
