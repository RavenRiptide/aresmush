require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # An animal companion's gear through the real commands, on a druid of the animal order with an approved
    # wolf: barding on its sheet, a stack split and joined again, investing two items and refusing a third,
    # the character's own Bulk and investiture leaving worn items out, sell, bag/store and invest refusing a
    # worn item, staff putting on what isn't a companion item, and what comes off when the companion changes.
    describe "animal companion gear", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        allow(Jobs).to receive(:notify)
        allow(Login).to receive(:notify)

        @char = Character.create(:name => "Kennel#{rand(1000000)}")
        @staff = Character.create(:name => "Boss#{rand(1000000)}")
        Roles.add_role(@staff, 'admin')
        @staff = Character[@staff.id]
        @client = AutoBuilder::CaptureClient.new

        @builder = AutoBuilder.new(@char)
        @builder.prefer.merge!('Animal Companion' => 'Wolf', 'Incredible Companion (Druid)' => 'Savage')
        @builder.build_level_one('Druid', specialty: 'Animal')
        @char = Character[@char.id]

        run(PF2CompanionNameCmd, 'companion/name Ash')
        Roles.add_role(@char, 'approved')
        @char = Character[@char.id]
        Ledger.commit_chargen!(@char)
        Companion.approve_with_app!(@char)
        @char = Character[@char.id]
        @builder.instance_variable_set(:@char, @char)
      end

      after(:each) do
        @char.delete if @char
        @staff.delete if @staff
      end

      def run(klass, text, who = @char)
        @client.clear
        klass.new(@client, Command.new(text), Character[who.id]).on_command
        @char = Character[@char.id]
      end

      def give(category, name, quantity = 1)
        config = Pf2egear::Inventory.config(category)
        Pf2egear.create_item(Character[@char.id], category, name, quantity, Global.read_config(config, name))
        @char = Character[@char.id]
      end

      # Where an item is in `gear`'s list, as the commands number it.
      def number(category, name, worn: false)
        Pf2egear::Inventory.held(Character[@char.id], category).index { |item| item.name == name && Companion::Gear.worn?(item) == worn }
      end

      def rows(category, name)
        Pf2egear::Inventory.held(Character[@char.id], category).select { |item| item.name == name }
      end

      def stats
        char = Character[@char.id]
        Companion.stats(char, Companion.main(char))
      end

      def gear_section
        Companion::SheetView.build(Character[@char.id])['sections'].find { |one| one['title'] == t('pf2e.companion_sheet_section_gear') }
      end

      it "should say on its sheet that it wears nothing" do
        expect(gear_section['rows']).to eq [ t('pf2e.companion_sheet_wears_nothing', :subject => 'Ash', :mid => 'Ash') ]
      end

      it "should put one barding of a stack on, with its AC and Speed, and join it back when it comes off" do
        give('gear', 'Light Barding (Small or Medium)', 2)
        before = stats
        carried = Pf2egear::Bulk.total(Character[@char.id])

        run(PF2CompanionWearCmd, "companion/wear gear=#{number('gear', 'Light Barding (Small or Medium)')}")

        expect(@client.successes.last).to eq t('pf2e.companion_gear_worn', :name => 'Ash', :item => 'Light Barding (Small or Medium)')
        expect(rows('gear', 'Light Barding (Small or Medium)').map { |item| [ item.quantity, item.companion ] })
          .to contain_exactly([ 1, nil ], [ 1, 'animal-companion' ])

        after = stats
        # A young wolf: Dex +3 under a cap of +5, trained in barding as in unarmored, plus light barding's +1.
        expect(after['ac']).to eq before['ac'] + 1
        expect(after['speeds']['land']).to eq before['speeds']['land'] - 5
        expect(after['barding']).to eq 'Light Barding (Small or Medium)'
        expect(Pf2egear::Bulk.total(Character[@char.id])).to eq carried - 20
        expect(gear_section['rows']).to eq [ [ [ t('pf2e.companion_label_barding'), 'Light Barding (Small or Medium)' ] ] ]

        run(PF2CompanionRemoveCmd, "companion/remove gear=#{number('gear', 'Light Barding (Small or Medium)', :worn => true)}")

        expect(@client.successes.last).to eq t('pf2e.companion_gear_removed', :mid => 'Ash', :item => 'Light Barding (Small or Medium)')
        expect(rows('gear', 'Light Barding (Small or Medium)').map { |item| [ item.quantity, item.companion ] }).to eq [ [ 2, nil ] ]
        expect(stats['ac']).to eq before['ac']
        expect(Pf2egear::Bulk.total(Character[@char.id])).to eq carried
      end

      it "should keep a bought barding apart from the one it wears" do
        give('gear', 'Light Barding (Small or Medium)')
        run(PF2CompanionWearCmd, "companion/wear gear=#{number('gear', 'Light Barding (Small or Medium)')}")
        give('gear', 'Light Barding (Small or Medium)')

        expect(rows('gear', 'Light Barding (Small or Medium)').map { |item| [ item.quantity, item.companion ] })
          .to contain_exactly([ 1, nil ], [ 1, 'animal-companion' ])
      end

      it "should refuse a second barding and barding of the wrong size" do
        give('gear', 'Light Barding (Small or Medium)')
        give('gear', 'Heavy Barding (Small or Medium)')
        give('gear', 'Light Barding (Large)')

        run(PF2CompanionWearCmd, "companion/wear gear=#{number('gear', 'Light Barding (Large)')}")
        expect(@client.failures.last).to eq t('pf2e.companion_gear_wrong_size', :item => 'Light Barding (Large)', :sizes => 'Large',
                                              :mid => 'Ash', :size => 'Small')

        run(PF2CompanionWearCmd, "companion/wear gear=#{number('gear', 'Light Barding (Small or Medium)')}")
        run(PF2CompanionWearCmd, "companion/wear gear=#{number('gear', 'Heavy Barding (Small or Medium)')}")
        expect(@client.failures.last).to eq t('pf2e.companion_gear_second_barding', :name => 'Ash', :barding => 'Light Barding (Small or Medium)')
      end

      it "should invest two items and refuse a third, leaving the character's own investiture alone" do
        give('magicitem', 'Collar of Empathy')
        give('magicitem', 'Alacritous Horseshoes')
        give('magicitem', 'Collar of Inconspicuousness')

        run(PF2CompanionWearCmd, "companion/wear magicitem=#{number('magicitem', 'Collar of Empathy')}")
        expect(@client.successes.last).to eq t('pf2e.companion_gear_worn_invested', :name => 'Ash', :item => 'Collar of Empathy', :count => 1, :max => 2)

        land = stats['speeds']['land']
        run(PF2CompanionWearCmd, "companion/wear magicitem=#{number('magicitem', 'Alacritous Horseshoes')}")
        expect(@client.successes.last).to eq t('pf2e.companion_gear_worn_invested', :name => 'Ash', :item => 'Alacritous Horseshoes', :count => 2, :max => 2)
        expect(stats['speeds']['land']).to eq land + 5

        run(PF2CompanionWearCmd, "companion/wear magicitem=#{number('magicitem', 'Collar of Inconspicuousness')}")
        expect(@client.failures.last).to eq t('pf2e.companion_gear_invest_full', :name => 'Ash', :max => 2,
                                              :items => 'Collar of Empathy and Alacritous Horseshoes')

        worn = rows('magicitem', 'Collar of Empathy').first
        expect(worn.companion_invested).to be true
        expect(worn.invested).to be_falsey
        expect(worn.invest_on_refresh).to be_falsey
        expect(gear_section['rows']).to eq [ [ [ t('pf2e.companion_sheet_invested', :count => 2, :max => 2),
                                                 'Collar of Empathy, Alacritous Horseshoes' ] ] ]

        run(PF2CompanionRemoveCmd, "companion/remove magicitem=#{number('magicitem', 'Collar of Empathy', :worn => true)}")
        off = rows('magicitem', 'Collar of Empathy').first
        expect(off.companion).to be_nil
        expect(off.companion_invested).to be_falsey
      end

      it "should refuse to sell, store, or invest a worn item, and refuse to put on what the character has invested" do
        give('magicitem', 'Collar of Empathy')
        give('magicitem', 'Collar of Inconspicuousness')
        index = number('magicitem', 'Collar of Empathy')
        run(PF2CompanionWearCmd, "companion/wear magicitem=#{index}")
        refused = t('pf2egear.item_on_companion', :name => 'Ash', :item => 'Collar of Empathy')

        run(Pf2egear::PF2SellCmd, "sell magicitem=#{index}")
        expect(@client.failures.last).to eq refused
        expect(rows('magicitem', 'Collar of Empathy')).not_to be_empty

        run(Pf2egear::PF2InvestCmd, "invest magicitem=#{index}")
        expect(@client.failures.last).to eq refused

        bag = PF2Bag.create(:character => @char, :name => 'Backpack', :capacity => 4)
        stored = Pf2egear::Stowing.store(bag, 'magicitem', rows('magicitem', 'Collar of Empathy').first)
        expect(stored.code).to eq :on_companion

        other = number('magicitem', 'Collar of Inconspicuousness')
        run(Pf2egear::PF2InvestCmd, "invest magicitem=#{other}")
        run(PF2CompanionWearCmd, "companion/wear magicitem=#{other}")
        expect(@client.failures.last).to eq t('pf2e.companion_gear_invested_yours', :item => 'Collar of Inconspicuousness', :mid => 'Ash')
      end

      it "should mark a worn item in the gear list" do
        give('magicitem', 'Collar of Empathy')
        run(PF2CompanionWearCmd, "companion/wear magicitem=#{number('magicitem', 'Collar of Empathy')}")

        shown = Pf2egear::Pf2eDisplayGearTemplate.new(Character[@char.id], @client).magic_items.join("\n")
        expect(shown).to include(t('pf2e.companion_gear_worn_mark', :name => 'Ash'))
        expect(shown).to include(t('pf2e.companion_gear_invested_column'))
      end

      it "should refuse a plain item, unless staff put it on, and let staff take it off" do
        give('gear', 'Rope')
        index = number('gear', 'Rope')

        run(PF2CompanionWearCmd, "companion/wear gear=#{index}")
        expect(@client.failures.last).to eq t('pf2e.companion_gear_not_companion', :item => 'Rope', :mid => 'Ash')

        run(PF2CompanionWearCmd, "companion/wear #{@char.name}=gear=#{index}")
        expect(@client.failures.last).to eq t('dispatcher.not_allowed')

        run(PF2CompanionWearCmd, "companion/wear #{@char.name}=gear/#{index}", @staff)
        expect(@client.successes.last).to eq t('pf2e.companion_gear_worn_staff', :name => 'Ash', :char => @char.name, :item => 'Rope')
        expect(gear_section['rows']).to eq [ [ [ t('pf2e.companion_sheet_also_wears'), 'Rope' ] ] ]

        run(PF2CompanionRemoveCmd, "companion/remove #{@char.name}=gear=#{number('gear', 'Rope', :worn => true)}", @staff)
        expect(@client.successes.last).to eq t('pf2e.companion_gear_removed_staff', :mid => 'Ash', :char => @char.name, :item => 'Rope')
        expect(rows('gear', 'Rope').first.companion).to be_nil
      end

      it "should speak to staff about the character's gear, not their own" do
        give('gear', 'Rope')
        give('gear', 'Torch')
        run(PF2CompanionWearCmd, "companion/wear #{@char.name}=gear=#{number('gear', 'Rope')}", @staff)

        run(PF2CompanionWearCmd, "companion/wear #{@char.name}=gear=#{number('gear', 'Rope', :worn => true)}", @staff)
        expect(@client.failures.last).to eq t('pf2e.companion_gear_already_staff', :name => 'Ash', :char => @char.name, :item => 'Rope')

        run(PF2CompanionRemoveCmd, "companion/remove #{@char.name}=gear=#{number('gear', 'Torch')}", @staff)
        expect(@client.failures.last).to eq t('pf2e.companion_gear_not_worn_staff', :name => 'Ash', :char => @char.name, :item => 'Torch')

        run(PF2CompanionWearCmd, "companion/wear #{@char.name}=weapons=1", @staff)
        expect(@client.failures.last).to eq t('pf2e.companion_gear_category_staff', :char => @char.name)
      end

      it "should call a companion without a name the character's, for staff" do
        give('gear', 'Torch')
        @char.update(:pf2_companions => {})
        @char = Character[@char.id]
        unnamed = t('pf2e.companion_subject_unnamed_of', :char => @char.name)

        run(PF2CompanionWearCmd, "companion/wear #{@char.name}=gear=#{number('gear', 'Torch')}", @staff)
        expect(@client.successes.last).to eq t('pf2e.companion_gear_worn_staff', :name => unnamed, :char => @char.name, :item => 'Torch')

        run(PF2CompanionRemoveCmd, "companion/remove #{@char.name}=gear=#{number('gear', 'Torch', :worn => true)}", @staff)
        expect(@client.successes.last).to eq t('pf2e.companion_gear_removed_staff', :mid => unnamed, :char => @char.name, :item => 'Torch')

        run(PF2CompanionRemoveCmd, "companion/remove gear=#{number('gear', 'Torch')}")
        expect(@client.failures.last).to eq t('pf2e.companion_gear_not_worn', :name => 'Your animal companion', :item => 'Torch')
      end

      it "should take off what a companion they no longer have wore" do
        give('magicitem', 'Collar of Empathy')
        run(PF2CompanionWearCmd, "companion/wear magicitem=#{number('magicitem', 'Collar of Empathy')}")
        rows('magicitem', 'Collar of Empathy').first.update(:companion => 'gone-companion')

        expect(Companion::Gear.settle!(Character[@char.id])).to eq [ 'Collar of Empathy' ]
        expect(rows('magicitem', 'Collar of Empathy').first.companion).to be_nil
      end

      it "should take off what a replacement can't wear when staff approve it, and say so" do
        give('gear', 'Light Barding (Small or Medium)')
        give('magicitem', 'Collar of Empathy')
        run(PF2CompanionWearCmd, "companion/wear gear=#{number('gear', 'Light Barding (Small or Medium)')}")
        run(PF2CompanionWearCmd, "companion/wear magicitem=#{number('magicitem', 'Collar of Empathy')}")

        run(PF2CompanionReplaceCmd, 'companion/replace Horse (Large)')
        run(PF2CompanionNameCmd, 'companion/name Blaze')
        run(PF2CompanionApproveCmd, "companion/approve #{@char.name}", @staff)

        expect(@client.oocs).to eq [ t('pf2e.companion_gear_came_off_staff', :name => 'Blaze', :char => @char.name,
                                       :item => 'Light Barding (Small or Medium)') ]
        expect(rows('gear', 'Light Barding (Small or Medium)').first.companion).to be_nil
        expect(rows('magicitem', 'Collar of Empathy').first.companion).to eq 'animal-companion'
        expect(stats['barding']).to be_nil
      end

      it "should pay a sale for the number sold" do
        give('gear', 'Torch', 5)
        money = Character[@char.id].pf2_money
        price = rows('gear', 'Torch').first.price / 2

        run(Pf2egear::PF2SellCmd, "sell gear=#{number('gear', 'Torch')}/1")

        expect(rows('gear', 'Torch').first.quantity).to eq 4
        expect(Character[@char.id].pf2_money).to eq money + price
      end

      describe "growing out of its barding" do
        it "should warn in advance/review and take it off at advance/done" do
          give('gear', 'Light Barding (Small or Medium)')
          run(PF2CompanionWearCmd, "companion/wear gear=#{number('gear', 'Light Barding (Small or Medium)')}")
          Pf2e.award_xp(@char, 9000, 'spec', 'level')
          @char = Character[@char.id]
          @builder.instance_variable_set(:@char, @char)

          (2..8).each do |level|
            @builder.clear
            @builder.run('advance')
            @builder.run('advance/feat charclass=Mature Animal Companion (Druid)') if level == 4
            @builder.run('advance/feat charclass=Incredible Companion (Druid)') if level == 8
            6.times { break if @builder.resolve_outstanding(:advance).zero? }

            if level == 8
              review = Companion::Preview.for(Character[@char.id])['notes']
              expect(review).to include(t('pf2e.companion_level_comes_off', :subject => 'Ash', :item => 'Light Barding (Small or Medium)'))
            end

            @builder.run('advance/done')
            expect(@builder.failures).to be_empty
            # Mature at 4 makes it Medium, which the barding still fits.
            expect(rows('gear', 'Light Barding (Small or Medium)').first.companion).to eq 'animal-companion' if level < 8
          end

          expect(@builder.client.oocs).to include(t('pf2e.companion_gear_came_off', :name => 'Ash', :item => 'Light Barding (Small or Medium)'))
          expect(rows('gear', 'Light Barding (Small or Medium)').first.companion).to be_nil
          expect(stats['size']).to eq 'Large'
        end
      end
    end
  end
end
