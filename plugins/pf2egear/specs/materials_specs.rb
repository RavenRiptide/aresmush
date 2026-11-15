require "plugin_test_loader"

module AresMUSH

  # Weapons, armor, and shields made of a precious material (GM Core), bought with `buy/material` or given
  # with `item/give`. What a material does to the item's own stats is written onto the item when it's made;
  # what it does beyond them is read from its `material` where it applies.
  describe "precious materials", :dbtest => true do

    class MaterialClient
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

      @client = MaterialClient.new
      @player = Player.create(:name => "Mat#{rand(1000000)}", :available_rpp => 5, :total_rpp => 5)
      @char = Character.create(:name => "Mat#{rand(1000000)}", :pf2_level => 12, :pf2_money => 5_000_000,
                               :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {},
                               :player => @player)
      @combat = Pf2eCombat.create(:character => @char)
      @char.update(:combat => @combat)
      @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12) }

      allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
    end

    after(:each) do
      [ PF2Weapon, PF2Armor, PF2Shield ].each { |model| model.find(:character_id => @char.id).each(&:delete) }
      (@abilities + [ @combat ]).each(&:delete)
      @char.update(:player => nil)
      @char.delete
      Player[@player.id]&.update(:name => "gone")
    end

    def reread
      Character[@char.id]
    end

    def buy(text)
      Pf2egear::PF2BuyMaterialCmd.new(@client, Command.new(text), reread).on_command
    end

    def info(category, name)
      Global.read_config(Pf2egear::Inventory.config(category), name)
    end

    def made(category, name, material, grade)
      Pf2egear::Materials.prepare(category, name, info(category, name), material, grade)
    end

    describe "the table" do
      it "should list each material's grades by kind of item, and nothing for a kind GM Core leaves out" do
        materials = Pf2egear::Materials.materials

        expect(materials.keys).to eq [ 'Cold Iron', 'Silver', 'Adamantine', 'Dawnsilver', 'Duskwood', 'Orichalcum' ]
        expect(materials.select { |_name, row| row['grades']['tower_shield'] }.keys).to eq [ 'Duskwood' ]
        expect(materials['Orichalcum']['grades'].values.map(&:keys).uniq).to eq [ [ 'high' ] ]
        expect(materials.values.map { |row| row['rarity'] }).to eq %w{common common uncommon uncommon uncommon rare}
      end
    end

    describe "price and stats" do
      it "should price a weapon at the grade's price plus a tenth of it per Bulk, light counting as 1" do
        expect(made('weapons', 'Longsword', 'cold iron', 'standard').state['info'].values_at('price', 'level')).to eq [ 96_800, 10 ]
        expect(made('weapons', 'Greatsword', 'Cold Iron', 'low').state['info']['price']).to eq 4_800
        expect(made('weapons', 'Dagger', 'silver', 'low').state['info']['price']).to eq 4_400
      end

      it "should price a shield at the listed price whatever its Bulk, with the material's Hardness and Hit Points" do
        expect(made('shields', 'Steel Shield', 'adamantine', 'standard').state['info'].values_at('price', 'hardness', 'hp', 'level'))
          .to eq [ 44_000, 10, 40, 8 ]
        expect(made('shields', 'Buckler', 'silver', 'low').state['info'].values_at('hardness', 'hp')).to eq [ 1, 4 ]
      end

      it "should make dawnsilver lighter, and dawnsilver armor easier to wear" do
        expect(made('weapons', 'Longsword', 'dawnsilver', 'standard').state['info']['bulk']).to eq 0.1
        expect(made('weapons', 'Dagger', 'dawnsilver', 'standard').state['info']['bulk']).to eq 0.1

        plain = info('armor', 'Breastplate')
        armor = made('armor', 'Breastplate', 'dawnsilver', 'standard').state['info']

        expect(armor['bulk']).to eq plain['bulk'] - 1
        expect(armor['min_str']).to eq plain['min_str'] - 2
        expect(armor['speed_penalty']).to eq [ plain['speed_penalty'] + 5, 0 ].min
      end

      it "should cost 2 RPP for an uncommon material and 4 for a rare one" do
        expect(made('weapons', 'Longsword', 'cold iron', 'low').state['rpp']).to eq 0
        expect(made('weapons', 'Longsword', 'adamantine', 'standard').state['rpp']).to eq 2
        expect(made('weapons', 'Longsword', 'orichalcum', 'high').state['rpp']).to eq 4
      end
    end

    describe "what can be made of what" do
      it "should keep duskwood to wooden items and the metals to metal ones" do
        expect(made('weapons', 'Longbow', 'cold iron', 'low').code).to eq :wood_only
        expect(made('weapons', 'Longbow', 'duskwood', 'standard').ok?).to be true
        expect(made('weapons', 'Longsword', 'duskwood', 'standard').code).to eq :metal_only
        expect(made('weapons', 'Whip', 'silver', 'low').code).to eq :no_substance
        expect(made('armor', 'Leather', 'dawnsilver', 'standard').code).to eq :no_substance
      end

      it "should keep a wooden shield to duskwood and a steel shield to the metals, and let a buckler be anything" do
        expect(made('shields', 'Wooden Shield', 'silver', 'low').code).to eq :wood_only
        expect(made('shields', 'Wooden Shield', 'duskwood', 'standard').ok?).to be true
        expect(made('shields', 'Steel Shield', 'duskwood', 'standard').code).to eq :metal_only
        expect(made('shields', 'Buckler', 'duskwood', 'standard').ok?).to be true
        expect(made('shields', 'Buckler', 'cold iron', 'low').ok?).to be true
      end

      it "should refuse a grade the material doesn't come in, and a tower shield of anything but duskwood" do
        expect(made('weapons', 'Longsword', 'adamantine', 'low').code).to eq :no_such_grade
        expect(made('shields', 'Tower Shield', 'silver', 'standard').code).to eq :no_such_grade
        expect(made('shields', 'Tower Shield', 'duskwood', 'standard').state['info']['price']).to eq 56_000
      end

      it "should take an ordinary item above level 0, such as full plate, and keep its own level if higher" do
        expect(made('armor', 'Full Plate', 'silver', 'low').state['info']['level']).to eq 5
        expect(made('weapons', 'Composite Longbow', 'duskwood', 'standard').ok?).to be true
      end

      it "should treat Sildanyari Chain as dawnsilver already, and not make it of anything else" do
        expect(made('armor', 'Sildanyari Chain (Standard-Grade)', 'silver', 'low').code).to eq :specific

        chain = Pf2egear.create_item(reread, 'armor', 'Sildanyari Chain (Standard-Grade)', 1,
                                     info('armor', 'Sildanyari Chain (Standard-Grade)'))

        expect(Pf2egear::Materials.describe(chain)).to eq [ t('pf2egear.material_line', :material => 'Dawnsilver', :grade => 'standard') ]
        expect([ chain.check_penalty, chain.bulk, chain.traits ]).to eq [ 0, 0.1, [ 'uncommon', 'flexible' ] ]
      end

      it "should refuse a specific magic item, an unknown material, and an unknown grade" do
        expect(made('armor', 'Holy Chain', 'silver', 'low').code).to eq :specific
        expect(made('weapons', 'Longsword', 'mithral', 'low').code).to eq :no_material
        expect(made('weapons', 'Longsword', 'silver', 'superb').code).to eq :no_grade
      end
    end

    describe "buy/material" do
      it "should sell a common material for money alone, and keep the material on the item" do
        buy('buy/material weapons=Longsword/cold iron/standard')

        expect(@client.failures).to eq []
        sword = reread.weapons.to_a.first
        expect([ sword.name, sword.material, sword.price, sword.level ])
          .to eq [ 'Longsword', { 'name' => 'Cold Iron', 'grade' => 'standard' }, 96_800, 10 ]
        expect(reread.pf2_money).to eq 5_000_000 - 96_800
        expect(Player[@player.id].available_rpp).to eq 5
      end

      it "should spend RPP for an uncommon material" do
        buy('buy/material shields=Steel Shield/adamantine/standard')

        expect(@client.failures).to eq []
        expect(reread.shields.to_a.first.hardness).to eq 10
        expect(Player[@player.id].available_rpp).to eq 3
      end

      it "should refuse a material the character lacks the RPP for, and spend nothing" do
        @player.update(:available_rpp => 3)
        buy('buy/material weapons=Longsword/orichalcum/high')

        expect(@client.failures).to eq [ t('pf2egear.material_too_high', :item => 'Longsword (orichalcum, high grade)', :level => 18) ]

        @char.update(:pf2_level => 20)
        buy('buy/material weapons=Longsword/orichalcum/high')

        expect(@client.failures.last).to eq t('pf2egear.material_needs_rpp', :item => 'Longsword (orichalcum, high grade)', :rpp => 4,
                                              :rarity => 'rare', :held => 3)
        expect(reread.weapons.to_a).to eq []
        expect(reread.pf2_money).to eq 5_000_000
      end

      it "should go by the item's own rarity for access" do
        buy('buy/material weapons=Khazadi Dagger/silver/low')

        expect(@client.failures).to eq [ t('pf2egear.no_access', :item => 'Khazadi Dagger', :rarity => 'uncommon') ]
      end
    end

    describe "what a material does beyond its stats" do
      def sword(material, grade)
        buy("buy/material weapons=Longsword/#{material}/#{grade}")
        reread.weapons.to_a.first
      end

      it "should put the weapon's material in its Strikes" do
        expect(Pf2eCombat.attack_descriptor(reread, sword('cold iron', 'low'))['materials']).to include 'cold-iron'
      end

      it "should give orichalcum one more property-rune slot than its potency" do
        @char.update(:pf2_level => 20)
        blade = sword('orichalcum', 'high')
        blade.update(:runes => { 'fundamental' => { 'potency' => 2 }, 'property' => {} })

        expect(Pf2egear.rune_slots(PF2Weapon[blade.id])).to eq 3
        expect(Pf2egear::Materials.half_price_rune?(blade, 'Quickstrike')).to be true
        expect(Pf2egear::Materials.half_price_rune?(blade, 'Flaming')).to be false
      end

      it "should give orichalcum armor its initiative bonus as a rule" do
        @char.update(:pf2_level => 20, :pf2_money => 10_000_000)
        buy('buy/material armor=Breastplate/orichalcum/high')
        armor = reread.armor.to_a.first

        expect(@client.failures).to eq []

        expect(Pf2egear::Materials.rules('armor', armor).map { |row| row.values_at('selector', 'value') }).to eq [ [ 'initiative', 1 ] ]

        plain = Pf2e.initiative_bonus(reread, 'Perception')
        armor.update(:equipped => true)

        expect(Pf2e.initiative_bonus(reread, 'Perception')).to eq plain + 1
      end

      it "should show the material in the item view" do
        expect(Pf2egear::Materials.describe(sword('silver', 'low')))
          .to eq [ t('pf2egear.material_line', :material => 'Silver', :grade => 'low') ]
      end
    end

    describe "cold iron and silver armor against creatures weak to them" do
      before(:each) do
        buy('buy/material armor=Breastplate/cold iron/low')
        reread.armor.to_a.first.update(:equipped => true)
        @creature = double('creature')
        who = Struct.new(:holder, :label)
        @scene = Struct.new(:actor, :target).new(who.new(@creature, 'Imp'), who.new(reread, @char.name))
        @weak = { 'weakness' => [ { 'type' => [ 'cold-iron' ], 'value' => 5 } ] }
        allow(Pf2e::Actors).to receive(:of).and_call_original
        allow(Pf2e::Acting).to receive(:condition_consequence)
      end

      def strike(attack, degree, weakness = @weak)
        allow(Pf2e::IWR).to receive(:for).with(@creature).and_return(weakness)
        out = { 'lines' => [] }
        Pf2e::MaterialArmor.after_strike(@scene, attack, degree, out)
        out
      end

      it "should sicken a creature weak to it that critically fails an unarmed attack" do
        out = strike({ 'traits' => [ 'unarmed' ] }, Pf2e::Degree::CRITICAL_FAILURE)

        expect(Pf2e::Acting).to have_received(:condition_consequence)
          .with(@scene, @scene.actor, { 'condition' => 'Sickened', 'value' => 1 }, out)
        expect(out['lines'].first).to eq({ 'key' => 'pf2e.material_armor_sickens',
                                           'args' => { 'actor' => 'Imp', 'target' => @char.name, 'material' => 'cold iron' } })
      end

      it "should leave alone a failure, a weapon attack, and a creature without the weakness" do
        strike({ 'traits' => [ 'unarmed' ] }, Pf2e::Degree::FAILURE)
        strike({ 'traits' => [] }, Pf2e::Degree::CRITICAL_FAILURE)
        strike({ 'traits' => [ 'unarmed' ] }, Pf2e::Degree::CRITICAL_FAILURE, { 'weakness' => [ { 'type' => [ 'silver' ], 'value' => 5 } ] })

        expect(Pf2e::Acting).to_not have_received(:condition_consequence)
      end
    end

    describe "adamantine against Hardness" do
      def taken(hardness, about)
        npc = double('npc', :stat_block => { 'hardness' => hardness })
        Pf2e::Npcs.hardened(npc, { 'amount' => 30, 'applied' => [] }, about, nil)['amount']
      end

      it "should give an adamantine weapon its grade's Hardness" do
        buy('buy/material weapons=Longsword/adamantine/standard')
        sword = reread.weapons.to_a.first

        expect(Pf2eCombat.attack_descriptor(reread, sword)['material_hardness']).to eq 14
      end

      it "should halve a Hardness up to the weapon's own, and no higher" do
        standard = Pf2e::DamageAbout.of_attack({ 'traits' => [], 'material_hardness' => 14 }, [ 'item:material:adamantine' ])

        expect(taken(12, standard)).to eq 30 - 6
        expect(taken(16, standard)).to eq 30 - 16
        expect(taken(12, [ 'adamantine' ])).to eq 30 - 12
      end
    end

    describe "an orichalcum shield" do
      before(:each) do
        @char.update(:pf2_level => 20)
        buy('buy/material shields=Steel Shield/orichalcum/high')
        @shield = reread.shields.to_a.first
      end

      it "should survive being destroyed once, broken at 1 Hit Point, until a rest" do
        @shield.update(:damage => 70)

        expect(Pf2e::ShieldBlock.survives!(@shield)).to be true
        expect([ PF2Shield[@shield.id].damage, Pf2e::ShieldBlock.broken?(PF2Shield[@shield.id]) ]).to eq [ 63, true ]

        PF2Shield[@shield.id].update(:damage => 70)
        expect(Pf2e::ShieldBlock.survives!(PF2Shield[@shield.id])).to be false

        Pf2egear::Materials.rested!(reread)
        expect(PF2Shield[@shield.id].survived_today).to be false
      end
    end

    describe "shield bosses and spikes" do
      before(:each) do
        buy('buy/material shields=Steel Shield/cold iron/low')
        Pf2egear.create_item(reread, 'weapons', 'Shield Boss', 1, info('weapons', 'Shield Boss'))
        Pf2egear.create_item(reread, 'weapons', 'Longsword', 1, info('weapons', 'Longsword'))
      end

      def attach(text)
        Pf2egear::PF2GearAttachCmd.new(@client, Command.new(text), reread).on_command
      end

      def boss
        reread.weapons.to_a.find { |one| one.name == 'Shield Boss' }
      end

      it "should attach to one shield, and strike as the shield's material" do
        attach("gear/attach 0=#{reread.weapons.to_a.index(boss)}")

        expect(@client.failures).to eq []
        expect(reread.shields.to_a.first.weapon.name).to eq 'Shield Boss'
        expect(Pf2eCombat.attack_descriptor(reread, boss)['materials']).to include 'cold-iron'

        attach('gear/detach 0')

        expect(reread.shields.to_a.first.weapon).to be_nil
        expect(Pf2eCombat.attack_descriptor(reread, boss)['materials']).to_not include 'cold-iron'
      end

      it "should refuse a weapon that isn't a boss or spikes, and a second one on the same shield" do
        sword = reread.weapons.to_a.index { |one| one.name == 'Longsword' }
        attach("gear/attach 0=#{sword}")
        attach("gear/attach 0=#{reread.weapons.to_a.index(boss)}")
        attach("gear/attach 0=#{reread.weapons.to_a.index(boss)}")

        expect(@client.failures).to eq [ t('pf2egear.attach_not_attachable', :weapon => 'Longsword'),
                                         t('pf2egear.attach_has_one', :shield => 'Steel Shield', :weapon => 'Shield Boss') ]
      end
    end

    describe "item/give" do
      before(:each) do
        @staff = Character.create(:name => "Staff#{rand(1000000)}")
        allow_any_instance_of(Character).to receive(:has_permission?).and_return(true)
        allow(Login).to receive(:notify)
        allow(Login).to receive(:find_game_client).and_return(nil)
      end

      after(:each) { @staff&.delete }

      def give(text)
        Pf2egear::PF2ItemGiveCmd.new(@client, Command.new(text), Character[@staff.id]).on_command
      end

      it "should give an item of a material at its price, without spending RPP" do
        give("item/give #{@char.name}=weapons/Longsword/adamantine/standard")

        expect(@client.failures).to eq []
        expect(reread.weapons.to_a.first.material).to eq({ 'name' => 'Adamantine', 'grade' => 'standard' })
        expect(reread.pf2_money).to eq 5_000_000 - 154_000
        expect(Player[@player.id].available_rpp).to eq 5
      end

      it "should check the material's level, and refuse what the material can't make" do
        give("item/give #{@char.name}=weapons/Longsword/orichalcum/high")
        give("item/give #{@char.name}=weapons/Longbow/cold iron/low")

        expect(@client.failures).to eq [
          t('pf2egear.give_too_high', :item => 'Longsword (orichalcum, high grade)', :level => 18, :char => @char.name, :char_level => 12),
          t('pf2egear.material_wood_only', :item => 'Longbow') ]
      end
    end
  end
end
