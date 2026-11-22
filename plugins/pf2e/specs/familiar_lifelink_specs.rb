require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Lifelink: a hit that drops a familiar whose master has Lifelink today is kept, and the master may take
    # it instead with e/act lifelink. The master is a level 6 witch with an approved familiar, Smudge.
    describe "a familiar's Lifelink", :dbtest => true do

      class LifelinkClient
        attr_reader :failures, :said

        def initialize
          @failures = []
          @said = []
        end

        def logged_in?
          true
        end

        def emit_failure(message)
          @failures << message.to_s
        end

        %w{emit_success emit emit_ooc}.each { |name| define_method(name) { |message| @said << message.to_s } }

        def screen_reader
          false
        end
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = LifelinkClient.new
        @room = Room.create(:name => "Field#{rand(1000000)}")
        @scene = Scene.create(:room => @room, :temp_room => true)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @made = []
        @witch = witch("Morwen#{rand(1000000)}")
        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :round => 0)

        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow(Scenes).to receive(:add_to_scene)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
        allow(Login).to receive(:notify)
        allow(Login).to receive(:emit_ooc_if_logged_in)
      end

      after(:each) do
        PF2Encounter.find(:scene_id => @scene.id).each do |one|
          one.npcs.each(&:delete)
          one.states.each(&:delete)
          one.delete
        end
        (@made + [ @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def witch(name)
        char = Character.create(:name => name, :room => @room)
        combat = Pf2eCombat.create(:character => char, :key_abil => 'Intelligence', :perception => 'trained',
                                   :armor_prof => { 'unarmored' => 'trained' },
                                   :saves => { 'Fortitude' => 'trained', 'Reflex' => 'trained', 'Will' => 'expert' })
        hp = Pf2eHP.create(:character => char, :ancestry_hp => 6, :charclass_hp => 6)
        char.update(:combat => combat, :hp => hp, :pf2_level => 6, :pf2_conditions => {}, :pf2_traits => [],
                    :pf2_derived => {}, :pf2_feats => {}, :pf2_daily_choices => {},
                    :pf2_base_info => { 'charclass' => 'Witch', 'specialize' => 'Night' },
                    :pf2_features => { 'charclass_features' => [ 'Familiar' ] })
        @made += [ combat, hp ] + Pf2e::ABILITIES.map do |ability|
          Pf2eAbilities.create(:character => char, :name => ability, :base_val => ability == 'Intelligence' ? 18 : 12)
        end
        Paths.apply_all!(Character[char.id])
        @scene.participants.add char
        @made << char
        approve(char)
        Character[char.id]
      end

      def approve(char, extra = {})
        record = { 'name' => 'Smudge', 'species' => 'black cat', 'form' => 'land', 'source' => 'Familiar' }.merge(extra)
        Character[char.id].update(:pf2_familiar => { 'approved' => record })
      end

      def encounter
        PF2Encounter[@encounter.id]
      end

      def run(cmd_class, text, who)
        @client.failures.clear
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
      end

      def familiar_row
        Combatants.rows(encounter).find { |row| row['master'] }
      end

      def familiar
        Pf2eNpc[familiar_row['npc']]
      end

      def master
        Pf2eCombatantState[@master_row['state']]
      end

      def hp(holder)
        Actors.of(holder.class[holder.id]).creature? ? holder.class[holder.id].hp_left.to_i : Pf2eHP.get_current_hp(holder.class[holder.id])
      end

      def pick(text)
        expect(DailyChoices.pick!(Character[@witch.id], 'familiar', text).ok?).to be true
      end

      def fight
        Combatants.join(encounter, 'Goblin', 20)
        @master_row = Combatants.join(encounter, @witch.name, 15, :holder => Character[@witch.id])
        Character[@witch.id].encounters.add encounter
        encounter.characters.add Character[@witch.id]
        run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
      end

      # A hit on the familiar, as a Strike or a spell deals it.
      def hit(amount)
        whom = Combatants.find(encounter, 'Smudge').state
        scene = Acting::Scene.new(encounter, nil, whom, @gm, true)
        out = Acting.report
        Acting.deal(scene, whom, [ { 'amount' => amount, 'type' => 'bludgeoning' } ], out)
        @client.said << Telling.lines(out['lines']).join("\n")
      end

      def lifelink
        run(PF2EncounterActCmd, 'encounter/act lifelink', @witch)
      end

      describe "the offer" do
        it "should be made when the hit drops the familiar" do
          pick('Lifelink')
          fight

          hit(hp(familiar) + 1)

          expect(hp(familiar)).to eq 0
          expect(@client.said.join).to include(t('pf2e.familiar_lifelink_offer', :master => @witch.name, :name => 'Smudge'))
          expect(TurnState.of(familiar)['lifelinked']).not_to be_nil
        end

        it "should not be made when the familiar stays up" do
          pick('Lifelink')
          fight

          hit(1)

          expect(@client.said.join).not_to include('Lifelink')
          expect(TurnState.of(familiar)['lifelinked']).to be_nil
        end

        it "should not be made without Lifelink" do
          pick('Darkvision')
          fight

          hit(hp(familiar) + 1)

          expect(@client.said.join).not_to include('Lifelink')
        end
      end

      describe "taking the hit" do
        before(:each) do
          pick('Lifelink')
          fight
        end

        it "should put the familiar's hit points back and deal the master the damage, with their reaction" do
          full = hp(familiar)
          before = hp(master)

          hit(full + 1)
          lifelink

          expect(@client.failures).to eq []
          expect(hp(familiar)).to eq full
          expect(hp(master)).to eq before - (full + 1)
          expect(@client.said.join).to include(t('pf2e.familiar_lifelink_taken', :master => @witch.name, :name => 'Smudge', :amount => full + 1))
          expect(TurnState.turn(master)['reaction']).to be true
          expect(TurnState.of(familiar)['lifelinked']).to be_nil
        end

        it "should be too late once a hit point has moved" do
          hit(hp(familiar) + 1)
          Harm.damage(master, 1)

          lifelink

          expect(@client.failures.join).to include(t('pf2e.answer_too_late', :action => 'Lifelink'))
          expect(hp(familiar)).to eq 0
        end

        it "should have nothing to take before a drop" do
          lifelink

          expect(@client.failures.join).to include(t('pf2e.familiar_lifelink_no_hit', :name => 'Smudge'))
        end

        it "should be refused without the ability" do
          hit(hp(familiar) + 1)
          pick_none = Character[@witch.id]
          pick_none.update(:pf2_daily_choices => {})

          lifelink

          expect(@client.failures.join).to include(t('pf2e.familiar_lifelink_none'))
        end
      end

      describe "with Blood Link" do
        it "should undo the Blood Link damage before the master takes the hit" do
          approve(@witch, 'specific' => 'Homunculus')
          # A homunculus uses 6 abilities, more than a level 6 witch has; room for one more is all this needs.
          allow(Familiar::Daily).to receive(:budget).and_return(1)
          pick('Lifelink')
          fight
          full = hp(familiar)
          before = hp(master)
          allow(Pf2e).to receive(:thrown_formula).and_call_original
          allow(Pf2e).to receive(:thrown_formula).with('2d10').and_return('total' => 7, 'shown' => '2d10: 7')

          hit(full + 1)
          expect(hp(master)).to eq before - 7

          lifelink

          expect(@client.failures).to eq []
          expect(hp(familiar)).to eq full
          expect(hp(master)).to eq before - (full + 1)
          expect(@client.said.join).to include(t('pf2e.familiar_blood_link_undone', :master => @witch.name))
        end
      end
    end
  end
end
