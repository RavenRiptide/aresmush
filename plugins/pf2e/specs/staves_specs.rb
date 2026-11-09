require "plugin_test_loader"
require "yaml"

module AresMUSH
  module Pf2e

    # The staff data, read straight from the config files: every staff's spells exist, every tier names a
    # stocked staff, and every stocked magical staff says what it holds.
    describe "staff data" do
      root = File.expand_path('../../../game/config', __dir__)
      weapons = YAML.load_file(File.join(root, 'pf2e_weapons.yml'))['pf2e_weapons']
      spells = Dir[File.join(root, 'pf2e_spells_*.yml')].each_with_object({}) { |file, all| all.merge!(YAML.load_file(file)['pf2e_spells']) }
      staves = weapons.select { |_name, entry| entry['staff'].is_a?(Hash) }

      it "should give every magical staff a staff block" do
        magical = weapons.select { |_name, entry| (Array(entry['traits']).map(&:downcase) & %w{magical staff}).size == 2 }

        expect(magical.keys - staves.keys).to eq []
      end

      it "should name only spells the game has" do
        listed = staves.values.flat_map { |entry| (entry['staff']['spells'] || {}).values.flatten }.uniq
        known = spells.keys.map(&:downcase)

        expect(listed.reject { |name| known.include?(name.downcase) }).to eq []
      end

      it "should name a stocked staff as each tier's staff" do
        expect(staves.values.map { |entry| entry['staff']['of'] }.uniq - staves.keys).to eq []
      end

      it "should key spells by cantrip or a rank from 1 to 10" do
        keys = staves.values.flat_map { |entry| (entry['staff']['spells'] || {}).keys }.uniq

        expect(keys.reject { |key| key == 'cantrip' || (1..10).include?(key) }).to eq []
      end
    end

    describe Staves, :dbtest => true do

      class StaffClient
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

        @client = StaffClient.new
        @room = Room.create(:name => "Tower#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @made = []

        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow_any_instance_of(Room).to receive(:emit_ooc)
        allow(Scenes).to receive(:add_to_scene)
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * 0.75).ceil, 1 ].max ] * amount.to_i }
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete if @encounter
        PF2Weapon.find(:character_id => @hero.id).each(&:delete) if @hero
        (@made + [ @gm, @scene, @room ]).each { |one| one&.delete }
      end

      # A caster: a wizard by default, with Fireball prepared twice at rank 3.
      def caster(charclass: 'Wizard', level: 5, thesis: nil, magic: {})
        @hero = Character.create(:name => "Staff#{rand(1000000)}", :room => @room, :pf2_level => level,
                                 :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {},
                                 :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] },
                                 :pf2_base_info => { 'charclass' => charclass, 'specialize_info' => thesis })
        combat = Pf2eCombat.create(:character => @hero)
        hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 6)
        wizard = {
          :tradition => { 'Wizard' => [ 'arcane', 'trained' ] },
          :spell_abil => { 'Wizard' => 'Intelligence' },
          :spells_per_day => { 'Wizard' => { 'cantrip' => 5, '1' => 3, '2' => 3, '3' => 2 } },
          :spellbook => { 'Wizard' => { 'cantrip' => [ 'Ignition', 'Shield' ], '1' => [ 'Breathe Fire', 'Force Barrage' ],
                                        '3' => [ 'Fireball' ] } },
          :spells_prepared => { 'Wizard' => { 'cantrip' => [ 'Ignition' ], '1' => [ 'Breathe Fire' ], '3' => [ 'Fireball', 'Fireball' ] } }
        }
        found = PF2Magic.create(wizard.merge(magic).merge(:character => @hero))
        @hero.update(:combat => combat, :hp => hp, :magic => found)
        abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
        @made += [ @hero, combat, hp, found ] + abilities

        @hero
      end

      def hero
        Character[@hero.id]
      end

      def run(klass, text, who = hero)
        klass.new(@client, Command.new(text), who).on_command
      end

      def staff(name = 'Staff of Fire (Greater)', equipped: true)
        made = Pf2egear.create_item(hero, 'weapons', name, 1, Global.read_config('pf2e_weapons', name))
        made.update(:equipped => equipped)
        made
      end

      def start
        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :organizer => @gm.name, :round => 1, :is_active => true)
        hero.encounters.add @encounter
        Combatants.join(@encounter, @hero.name, 10, :holder => hero)
      end

      def state
        CombatantStates.of(PF2Encounter[@encounter.id], hero)
      end

      def copy
        state.weapons.to_a.find { |one| Staves.staff?(one) && !Staves.makeshift?(one) }
      end

      def number(holder)
        Pf2egear::Inventory.held(holder, 'weapons').index { |one| Staves.staff?(one) && !Staves.makeshift?(one) }
      end

      def use(text)
        run(Pf2egear::PF2EncounterUseCmd, text)
      end

      describe "what a staff holds" do
        it "should hold its own tier's spells and every lower tier's" do
          names = Staves.catalogue_spells('Staff of Fire (Greater)').map { |one| [ one['rank'], one['name'] ] }

          expect(names).to eq [ [ 0, 'Ignition' ], [ 1, 'Breathe Fire' ], [ 2, 'Breathe Fire' ], [ 2, 'Floating Flame' ],
                                [ 3, 'Fireball' ], [ 3, 'Floating Flame' ] ]
        end

        it "should leave out a higher tier's" do
          expect(Staves.catalogue_spells('Staff of Fire').map { |one| one['name'] }).to eq [ 'Ignition', 'Breathe Fire' ]
        end
      end

      describe "preparing" do
        before(:each) { caster }

        it "should give charges equal to their highest slot's rank" do
          staff
          run(PF2PrepareStaffCmd, 'prepare/staff staff of fire (greater)')

          expect(@client.failures).to eq []
          expect(Staves.prepared(hero)['charges']).to eq 3
        end

        it "should expend a prepared spell for its rank in charges, once a day for a prepared caster" do
          staff
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)/3 = fireball')
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)/3 = fireball')

          expect(Staves.prepared(hero)['charges']).to eq 6
          expect(Staves.prepared(hero)['expended']).to eq [ { 'class' => 'Wizard', 'rank' => 3, 'spell' => 'Fireball' } ]
          expect(@client.failures).to eq [ t('pf2e.staff_expend_limit', :count => 1) ]
        end

        it "should refuse a spell they haven't prepared at that rank" do
          staff
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)/2 = fireball')

          expect(@client.failures).to eq [ t('pf2e.staff_expend_not_prepared', :spell => 'Fireball', :rank => '2') ]
          expect(Staves.prepared(hero)).to be_nil
        end

        it "should prepare only one staff a day" do
          staff
          staff('Staff of Fire')
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)')
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire')

          expect(@client.failures).to eq [ t('pf2e.staff_one_a_day', :staff => 'Staff of Fire (Greater)') ]
        end

        it "should refuse a staff with none of their spells" do
          staff('Staff of Healing')
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Healing')

          expect(@client.failures).to eq [ t('pf2e.staff_not_on_list', :staff => 'Staff of Healing') ]
        end

        it "should take a preparation back with the spell it expended" do
          staff
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)/3 = fireball')
          run(PF2UnprepareStaffCmd, 'unprepare/staff')

          expect(@client.failures).to eq []
          expect(Staves.prepared(hero)).to be_nil
        end
      end

      describe "in an encounter" do
        before(:each) do
          caster
          staff
          allow(Acting).to receive(:cast).and_call_original
        end

        it "should charge their copy at a fresh join, with the expended spell gone" do
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)/3 = fireball')
          start

          expect(copy.staff_charges).to eq 6
          expect(state.spells_today['Wizard']['3']).to eq [ 'Fireball' ]
        end

        it "should charge their copy where they stand when they prepare it there" do
          start
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)/3 = fireball')

          expect(copy.staff_charges).to eq 6
          expect(state.spells_today['Wizard']['3']).to eq [ 'Fireball' ]
        end

        it "should cast a spell for its rank in charges, with their own casting" do
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)')
          start
          use("e/use weapons=#{number(state)}/#{@hero.name}/fireball")

          expect(@client.failures).to eq []
          expect(Acting).to have_received(:cast) do |_scene, spell, _targets, _words, cast:, noted:|
            expect([ spell, cast['spell level'], cast['tradition'] ]).to eq [ 'Fireball', '3', 'arcane' ]
          end
          expect(copy.staff_charges).to eq 0
        end

        it "should cast a cantrip for nothing, heightened as theirs are" do
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)')
          start
          use("e/use weapons=#{number(state)}/#{@hero.name}/ignition")

          expect(@client.failures).to eq []
          expect(Acting).to have_received(:cast) do |_scene, _spell, _targets, _words, cast:, noted:|
            expect(cast['spell level']).to eq 'cantrip/3'
          end
          expect(copy.staff_charges).to eq 3
        end

        it "should refuse a spell that costs more charges than are left" do
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)')
          start
          use("e/use weapons=#{number(state)}/#{@hero.name}/fireball")
          use("e/use weapons=#{number(state)}/#{@hero.name}/breathe fire")

          expect(@client.failures).to eq [ t('pf2e.staff_no_charges', :item => 'Staff of Fire (Greater)', :cost => 1, :left => 0) ]
        end

        it "should refuse a staff they haven't prepared, or haven't equipped" do
          start
          use("e/use weapons=#{number(state)}/#{@hero.name}/fireball")
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)')
          copy.update(:equipped => false)
          use("e/use weapons=#{number(state)}/#{@hero.name}/fireball")

          expect(@client.failures).to eq [ t('pf2e.staff_unprepared', :item => 'Staff of Fire (Greater)'),
                                           t('pf2e.staff_unequipped', :item => 'Staff of Fire (Greater)') ]
        end

        it "should ask which spell when it holds several and none is named" do
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)')
          start
          use("e/use weapons=#{number(state)}/#{@hero.name}")

          expect(@client.failures.first).to include 'Fireball'
        end

        it "should fade with a rest, and need preparing again" do
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)')
          start
          Pf2e.rest(state)

          expect(copy.staff_charges).to eq 0
          expect(Staves.prepared(hero)).to be_nil
        end

        it "should refuse to take back a staff once cast from" do
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)')
          start
          use("e/use weapons=#{number(state)}/#{@hero.name}/breathe fire")
          run(PF2UnprepareStaffCmd, 'unprepare/staff')

          expect(@client.failures).to eq [ t('pf2e.staff_cast_from', :staff => 'Staff of Fire (Greater)') ]
        end
      end

      describe "a spontaneous caster" do
        before(:each) do
          caster(:charclass => 'Sorcerer', :magic => {
                   :tradition => { 'Sorcerer' => [ 'arcane', 'trained' ] }, :spell_abil => { 'Sorcerer' => 'Charisma' },
                   :spells_per_day => { 'Sorcerer' => { 'cantrip' => 5, '1' => 4, '2' => 4, '3' => 3 } },
                   :repertoire => { 'Sorcerer' => { '1' => [ 'Charm' ] } }, :spellbook => {}, :spells_prepared => {} })
          staff
          allow(Acting).to receive(:cast).and_call_original
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)')
          start
        end

        it "should spend 1 charge and a slot of the rank they name, casting at the staff's rank" do
          use("e/use weapons=#{number(state)}/#{@hero.name}/fireball/rank 3")

          expect(@client.failures).to eq []
          expect(Acting).to have_received(:cast) do |_scene, _spell, _targets, words, cast:, noted:|
            expect([ cast['spell level'], words ]).to eq [ '3', [] ]
          end
          expect(copy.staff_charges).to eq 2
          expect(state.spells_today['Sorcerer']['3'].to_i).to eq 2
        end

        it "should refuse a slot below the spell's rank" do
          use("e/use weapons=#{number(state)}/#{@hero.name}/fireball/rank 2")

          expect(@client.failures).to eq [ t('pf2e.staff_slot_too_low', :spell => 'Fireball', :rank => 3) ]
        end

        it "should refuse to expend a spell for one who doesn't prepare them" do
          run(PF2UnprepareStaffCmd, 'unprepare/staff')
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)/3 = fireball')

          expect(@client.failures).to eq [ t('pf2e.staff_expend_prepared_only') ]
        end
      end

      describe "runes" do
        it "should refuse a property rune on a staff" do
          caster
          staff
          allow_any_instance_of(Character).to receive(:is_admin?).and_return(true)
          index = Pf2egear::Inventory.held(hero, 'weapons').index { |one| Staves.staff?(one) }
          run(Pf2egear::PF2EtchPropertyCmd, "etch/property #{@hero.name}=weapons/#{index}/flaming", @gm)

          expect(@client.failures).to eq [ t('pf2egear.rune_property_staff', :item_name => 'Staff of Fire (Greater)') ]
        end
      end

      describe "Staff Nexus" do
        before(:each) { caster(:thesis => 'Staff Nexus', :level => 8) }

        def makeshift
          Pf2egear::Inventory.all(hero, 'weapons').find { |one| Staves.makeshift?(one) }
        end

        it "should make the makeshift staff at the commit, bound to the thesis" do
          BoundItems.settle!(hero)

          expect(makeshift.bound_to).to eq 'Staff Nexus'
          expect(BoundItems.usable?(hero, makeshift)).to be true
        end

        # The makeshift staff's spells as chargen or staff left them.
        def holding(cantrip: 'Shield', first: 'Force Barrage')
          hero.magic.update(:makeshift_spells => { 'cantrip' => cantrip, '1' => first }.compact)
        end

        describe "in chargen" do
          before(:each) do
            allow_any_instance_of(Character).to receive(:is_approved?).and_return(false)
            allow(Pf2e).to receive(:in_chargen?).and_return(true)
            hero.update(:pf2_baseinfo_locked => true)
          end

          it "should open the two picks when the thesis is chosen, and wait on them" do
            opened = PF2Magic.update_magic(hero, 'Wizard', { 'makeshift_staff' => true }, @client)
            hero.update(:pf2_to_assign => opened)

            expect(opened['makeshift staff']).to eq({ 'cantrip' => 'open', '1' => 'open' })
            expect(Pf2e.open_magic_choices?(hero)).to be true
          end

          it "should pick its two spells from the spellbook with addspell, and refuse others" do
            hero.update(:pf2_to_assign => { 'makeshift staff' => { 'cantrip' => 'open', '1' => 'open' } })
            run(Pf2emagic::PF2ChargenSpellsCmd, 'addspell makeshift/cantrip = shield')
            run(Pf2emagic::PF2ChargenSpellsCmd, 'addspell makeshift/1 = force barrage')
            run(Pf2emagic::PF2ChargenSpellsCmd, 'addspell makeshift/1 = breathe fire')
            run(Pf2emagic::PF2ChargenSpellsCmd, 'addspell makeshift/cantrip = force barrage')
            run(Pf2emagic::PF2ChargenSpellsCmd, 'addspell makeshift/cantrip = detect magic/ignition')

            expect(Staves.makeshift_picks(hero)).to eq({ 'cantrip' => 'Shield', '1' => 'Force Barrage' })
            expect(@client.failures).to eq [
              t('pf2e.staff_makeshift_already', :slot => '1st-rank spell', :spell => 'Force Barrage', :rank => '1'),
              t('pf2e.staff_makeshift_already', :slot => 'cantrip', :spell => 'Shield', :rank => 'cantrip'),
              t('pf2e.staff_makeshift_not_held', :spell => 'detect magic')
            ]
            expect(Pf2e.open_magic_choices?(hero)).to be false
          end

          it "should swap one, and refuse a spell outside their spellbook" do
            hero.update(:pf2_to_assign => { 'makeshift staff' => { 'cantrip' => 'Shield', '1' => 'open' } })
            holding(:first => nil)
            run(Pf2emagic::PF2ChargenSpellsCmd, 'addspell makeshift/cantrip = shield/ignition')
            run(Pf2emagic::PF2ChargenSpellsCmd, 'addspell makeshift/cantrip = ignition/detect magic')

            expect(Staves.makeshift_picks(hero)).to eq({ 'cantrip' => 'Ignition' })
            expect(hero.pf2_to_assign['makeshift staff']).to eq({ 'cantrip' => 'Ignition', '1' => 'open' })
            expect(@client.failures).to eq [ t('pf2e.staff_makeshift_book', :spell => 'Detect Magic', :slot => 'cantrip') ]
          end

          it "should refuse to swap a spell the makeshift staff holds out of the spellbook" do
            holding
            hero.update(:pf2_to_assign => { 'spellbook' => { '1' => [ 'Breathe Fire', 'Force Barrage' ] } })
            refused = Pf2emagic.select_spell(hero, 'Wizard', '1', 'force barrage', 'breathe fire')

            expect(refused).to eq t('pf2emagic.spell_in_makeshift_staff', :spell => 'Force Barrage', :slot => '1st-rank spell')
          end
        end

        describe "admin/set" do
          it "should set one from the spellbook, and refuse one outside it" do
            holding
            state = CharState.of(hero)
            set = AdminSet.plan(state, 'makeshift', [ '1', 'Breathe', 'Fire' ])
            outside = AdminSet.plan(state, 'makeshift', [ 'Cantrip', 'Detect', 'Magic' ])

            expect(set.state['magic_ops']).to eq [ { 'op' => 'makeshift', 'slot' => '1', 'spell' => 'Breathe Fire' } ]
            expect(outside.code).to eq :not_in_book

            Staves.write_makeshift!(hero, '1', 'Breathe Fire')

            expect(Staves.makeshift_picks(hero)).to eq({ 'cantrip' => 'Shield', '1' => 'Breathe Fire' })
          end

          it "should refuse to take a spell the makeshift staff holds out of the spellbook" do
            holding
            state = CharState.of(hero)
            refused = AdminSet.plan(state, 'spellbook', [ 'Wizard', 'delete', 'Force', 'Barrage', '1' ])

            expect(refused.code).to eq :makeshift_holds
            expect(AdminSet.plan(state, 'spellbook', [ 'Wizard', 'delete', 'Breathe', 'Fire', '1' ])).to be_ok
          end

          it "should refuse one for a wizard without the thesis" do
            hero.update(:pf2_base_info => { 'charclass' => 'Wizard' })

            expect(AdminSet.plan(CharState.of(hero), 'makeshift', [ '1', 'Breathe', 'Fire' ]).code).to eq :not_nexus
          end
        end

        it "should prepare the makeshift staff on its own, holding its two spells" do
          BoundItems.settle!(hero)
          holding
          run(PF2PrepareStaffCmd, 'prepare/staff makeshift staff')

          expect(@client.failures).to eq []
          expect(Staves.spells(hero, makeshift).map { |one| one['name'] }).to eq [ 'Shield', 'Force Barrage' ]
          expect(Staves.prepared(hero)['charges']).to eq 0
          expect(@client.said.last).to eq t('pf2e.staff_prepared_makeshift', :staff => 'Makeshift Staff')
        end

        it "should give the makeshift staff on its own only the charges of the spells expended on it" do
          BoundItems.settle!(hero)
          holding
          run(PF2PrepareStaffCmd, 'prepare/staff makeshift staff/3 = fireball')
          run(PF2PrepareStaffCmd, 'prepare/staff makeshift staff/1 = breathe fire')

          expect(@client.failures).to eq []
          expect(Staves.prepared(hero)['charges']).to eq 4
        end

        it "should merge its two spells into another staff they prepare" do
          made = staff
          holding

          expect(Staves.spells(hero, made).map { |one| one['name'] }).to include 'Force Barrage'
        end

        it "should give a staff the makeshift staff merges into its usual charges" do
          staff
          holding
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)')

          expect(Staves.prepared(hero)['charges']).to eq 3
        end

        it "should expend two spells from 8th level" do
          staff
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)/3 = fireball')
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)/1 = breathe fire')
          run(PF2PrepareStaffCmd, 'prepare/staff Staff of Fire (Greater)/3 = fireball')

          expect(Staves.prepared(hero)['charges']).to eq 7
          expect(@client.failures).to eq [ t('pf2e.staff_expend_limit', :count => 2) ]
        end

        it "should refuse makeshift staff spells to a wizard without the thesis" do
          hero.update(:pf2_base_info => { 'charclass' => 'Wizard' }, :pf2_to_assign => { 'makeshift staff' => { 'cantrip' => 'open' } })

          expect(Staves.choose_makeshift!(hero, 'cantrip', nil, 'shield').code).to eq :not_nexus
        end
      end
    end
  end
end
