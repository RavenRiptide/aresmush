require "plugin_test_loader"

module AresMUSH
  module Pf2egear

    # A reinforcing rune raises a shield's Hardness and Hit Points, each up to its grade's maximum, and never
    # lowers a shield already past it (GM Core; Foundry's `adjustFromUpgrades`).
    describe "a shield's reinforcing rune", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = EtchReinforcingClient.new
        @char = Character.create(:name => "Shielder#{rand(1000000)}", :pf2_level => 10)
        # Steel Shield: Hardness 5, 20 Hit Points.
        @shield = Pf2egear.create_item(@char, 'shields', 'Steel Shield', 1, Global.read_config('pf2e_shields', 'Steel Shield'))
      end

      after(:each) do
        [ @shield, @char ].each { |one| one&.delete }
      end

      class EtchReinforcingClient
        attr_reader :failures, :successes

        def initialize
          @failures = []
          @successes = []
        end

        def logged_in?
          true
        end

        def emit_failure(msg)
          @failures << msg.to_s
        end

        def emit_success(msg)
          @successes << msg.to_s
        end

        def emit(_msg); end
        def emit_ooc(_msg); end
      end

      def reinforced(grade, shield = @shield)
        shield.update(:runes => { 'fundamental' => { 'reinforcing' => grade } })
        PF2Shield[shield.id]
      end

      describe "the catalogue" do
        it "should hold all six grades, with what each adds" do
          grades = Global.read_config('pf2e_fundamental_runes', 'shield', 'reinforcing')

          expect(grades.keys).to eq [ 1, 2, 3, 4, 5, 6 ]
          expect(grades[1]).to include('name' => 'Minor Reinforcing', 'level' => 4, 'price' => 7500,
                                       'hardness' => { 'increase' => 3, 'max' => 8 },
                                       'hp' => { 'increase' => 44, 'max' => 64 })
        end
      end

      it "should leave a shield with no rune as it is" do
        expect(ShieldRunes.hardness(@shield)).to eq 5
        expect(ShieldRunes.max_hp(@shield)).to eq 20
        expect(ShieldRunes.name(@shield)).to be_nil
      end

      it "should add the grade's Hardness and Hit Points" do
        shield = reinforced(1)

        expect(ShieldRunes.hardness(shield)).to eq 8
        expect(ShieldRunes.max_hp(shield)).to eq 64
        expect(ShieldRunes.name(shield)).to eq 'Minor Reinforcing'
      end

      it "should stop at the grade's maximum" do
        @shield.update(:hardness => 6, :hp => 30)
        shield = reinforced(1)

        expect(ShieldRunes.hardness(shield)).to eq 8
        expect(ShieldRunes.max_hp(shield)).to eq 64
      end

      it "should never lower a shield already past the maximum" do
        @shield.update(:hardness => 10, :hp => 70)
        shield = reinforced(1)

        expect(ShieldRunes.hardness(shield)).to eq 10
        expect(ShieldRunes.max_hp(shield)).to eq 70
      end

      it "should keep the shield's own Hardness and Hit Points, so taking the rune off puts them back" do
        reinforced(6)

        expect(PF2Shield[@shield.id].hardness).to eq 5
        expect(ShieldRunes.max_hp(reinforced(0))).to eq 20
      end

      # A creature's shield comes from its stat block and takes no runes.
      it "should read a shield with no runes as it is" do
        shield = double('stat block shield', :hardness => 7, :hp => 40)

        expect(ShieldRunes.hardness(shield)).to eq 7
        expect(ShieldRunes.max_hp(shield)).to eq 40
      end

      # The Broken Threshold is half the Hit Points, so it rises with them.
      it "should break the shield at half its reinforced Hit Points" do
        @shield.update(:damage => 15)

        expect(Pf2e::ShieldBlock.broken?(PF2Shield[@shield.id])).to be true
        expect(Pf2e::ShieldBlock.broken?(reinforced(1))).to be false

        @shield.update(:damage => 32)

        expect(Pf2e::ShieldBlock.broken?(PF2Shield[@shield.id])).to be true
        expect(Pf2e::ShieldBlock.destroyed?(PF2Shield[@shield.id])).to be false
      end

      it "should show the reinforced Hit Points" do
        expect(Pf2egear.display_shield_hp(reinforced(1))).to eq '64%xn / 64'
      end

      describe "etching one" do
        def etch(text)
          PF2EtchReinforcingCmd.new(@client, Command.new(text), Character[@char.id]).on_command
        end

        def grade
          ShieldRunes.reinforcing(PF2Shield[@shield.id])
        end

        it "should refuse someone who is not staff" do
          etch("etch/reinforcing #{@char.name}=shields/0/2")

          expect(@client.failures).to eq [ t('pf2egear.rune_no_admin') ]
          expect(grade).to eq 0
        end

        describe "for staff" do
          before(:each) do
            allow_any_instance_of(Character).to receive(:is_admin?).and_return(true)
          end

          it "should set the grade" do
            etch("etch/reinforcing #{@char.name}=shields/0/2")

            expect(@client.failures).to eq []
            expect(grade).to eq 2
          end

          it "should take it off at 0" do
            reinforced(3)
            etch("etch/reinforcing #{@char.name}=shields/0/0")

            expect(grade).to eq 0
          end

          it "should refuse a grade past supreme" do
            etch("etch/reinforcing #{@char.name}=shields/0/7")

            expect(@client.failures).to eq [ t('pf2egear.rune_reinforcing_out_of_range') ]
            expect(grade).to eq 0
          end

          it "should refuse anything but a shield" do
            etch("etch/reinforcing #{@char.name}=weapons/0/1")

            expect(@client.failures).to eq [ t('pf2egear.rune_reinforcing_shields_only') ]
          end

          it "should say how to write it when it can't read it" do
            etch("etch/reinforcing #{@char.name}=shields/minor")

            expect(@client.failures).to eq [ t('pf2egear.rune_reinforcing_cmd_fail') ]
          end
        end
      end
    end
  end
end
