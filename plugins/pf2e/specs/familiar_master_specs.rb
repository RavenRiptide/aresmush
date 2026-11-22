require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Master abilities that change the master: what their familiar's day gives them. The witch is level 6
    # with a Night patron and an approved familiar.
    describe "a familiar's master abilities", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Morwen#{rand(1000000)}")
        @combat = Pf2eCombat.create(:character => @char, :key_abil => 'Intelligence', :perception => 'trained',
                                    :armor_prof => { 'unarmored' => 'trained' })
        @char.update(:combat => @combat, :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {},
                     :pf2_lang => [ 'Kamin' ], :pf2_daily_choices => {})
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14) }
        char.update(:pf2_base_info => { 'charclass' => 'Witch', 'specialize' => 'Night' }, :pf2_level => 6, :pf2_feats => {},
                    :pf2_features => { 'charclass_features' => [ 'Familiar' ] })
        Paths.apply_all!(char)
        approve
      end

      after(:each) do
        PF2MagicItem.all.to_a.select { |one| one.character_id == @char.id }.each(&:delete)
        @abilities.each(&:delete)
        @combat.delete
        @char.delete
      end

      # Ohm's `update` saves every attribute, so each write goes through a fresh copy.
      def char
        Character[@char.id]
      end

      def approve(extra = {})
        approved = { 'name' => 'Smudge', 'species' => 'black cat', 'form' => 'land', 'source' => 'Familiar' }.merge(extra)
        char.update(:pf2_familiar => { 'approved' => approved })
      end

      # Today's picks, as prepare/familiar leaves them. Extra Alchemy and Extra Vial ask for an alchemist,
      # which the witch isn't, so they are written straight in rather than picked.
      def today(*names)
        allow(Familiar::Daily).to receive(:today).and_return(names.map { |name| { 'name' => name } })
      end

      describe "a master ability today" do
        it "should be one picked today" do
          DailyChoices.pick!(char, 'familiar', 'Darkvision, Lifelink')

          expect(Familiar::Daily.master_ability?(char, 'Lifelink')).to be true
          expect(Familiar::Daily.master_ability?(char, 'Extra Vial')).to be false
        end

        it "should need the familiar approved" do
          today('Extra Vial')
          char.update(:pf2_familiar => {})

          expect(Familiar::Daily.master_ability?(char, 'Extra Vial')).to be false
        end
      end

      describe "Extra Alchemy and Extra Vial" do
        before(:each) do
          allow(Alchemy).to receive(:allowances).and_return('vials' => 3, 'prepared' => 4, 'gathers' => true)
        end

        it "should leave an alchemist's allowances alone without them" do
          today('Darkvision')

          expect(Alchemy.prepared_limit(char)).to eq 4
          expect(Alchemy.rest_vials(char)).to eq 3
        end

        it "should let Extra Alchemy make one more item" do
          today('Extra Alchemy')

          expect(Alchemy.prepared_limit(char)).to eq 5
          expect(Alchemy.day(char)['prepared']).to eq 5
        end

        it "should give one more vial at a rest with Extra Vial, but no bigger pool" do
          today('Extra Vial')
          granted = nil
          allow(Equipment).to receive(:grant!) { |_holder, _kind, _name, many, *_rest| granted = many }
          allow(Alchemy).to receive(:plan).and_return({})

          Alchemy.at_rest!(char)

          expect(granted).to eq 4
          expect(Alchemy.day(char)['vials']).to eq 4
          expect(Alchemy.max_vials(char)).to eq 3
        end
      end

      describe "Aeon Stone Reservoir" do
        before(:each) { approve('specific' => 'Aeon Wyrd') }

        def stones(count, invested:)
          stone = 'Aeon Stone (Preserving)'

          Array.new(count) do
            item = Pf2egear.create_item(char, 'magicitem', stone, 1, Global.read_config('pf2e_magicitem', stone))
            item.update(:invested => invested, :invest_on_refresh => invested)
            PF2MagicItem[item.id]
          end
        end

        def invest(item)
          said = []
          client = double
          %i{emit_failure emit_success emit_ooc emit}.each { |name| allow(client).to receive(name) { |message| said << message.to_s } }
          number = Pf2egear::Inventory.held(char, 'magicitem').index { |one| one.id == item.id }
          cmd = Pf2egear::PF2InvestCmd.new(client, Command.new("invest magicitem/#{number}"), char)
          cmd.parse_args
          cmd.handle
          said
        end

        it "should leave one aeon stone out of the count" do
          held = stones(2, invested: true)

          expect(Familiar.invest_count(char, held)).to eq 1
        end

        it "should count every stone once the familiar isn't an approved aeon wyrd" do
          held = stones(2, invested: true)
          approve

          expect(Familiar.invest_count(char, held)).to eq 2
        end

        it "should let invest go one past the limit with an aeon stone housed" do
          stones(10, invested: true)
          eleventh = stones(1, invested: false).first

          invest(eleventh)

          expect(PF2MagicItem[eleventh.id].invested).to be true
        end

        it "should still stop at the limit past the housed stone" do
          stones(11, invested: true)
          twelfth = stones(1, invested: false).first

          said = invest(twelfth)

          expect(PF2MagicItem[twelfth.id].invested).to be_falsey
          expect(said.join).to include t('pf2egear.too_many_invested', :max => 10)
        end

        it "should stop at the limit for a master without an aeon wyrd" do
          approve
          stones(10, invested: true)
          eleventh = stones(1, invested: false).first

          invest(eleventh)

          expect(PF2MagicItem[eleventh.id].invested).to be_falsey
        end
      end
    end
  end
end
