require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A familiar with the Spellcasting ability casts the spell its master named with prepare/familiar, once a
    # day, with its master's tradition, spell attack and spell DC. The master is a level 12 witch who
    # prepared Fear, with an approved familiar, Smudge.
    describe "a familiar casting its Spellcasting spell", :dbtest => true do

      class FamiliarCastClient
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

        @client = FamiliarCastClient.new
        @room = Room.create(:name => "Field#{rand(1000000)}")
        @scene = Scene.create(:room => @room, :temp_room => true)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @made = []
        @witch = witch("Morwen#{rand(1000000)}")
        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :organizer => @gm.name, :round => 0, :is_active => true)

        allow_any_instance_of(Character).to receive(:has_permission?).and_call_original
        allow_any_instance_of(Character).to receive(:has_permission?).with('kill_pc') { |char, _| char.name == @gm.name }
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
        slots = { 'cantrip' => 5 }.merge((1..6).to_h { |rank| [ rank.to_s, 3 ] })
        magic = PF2Magic.create(:character => char, :tradition => { 'Witch' => [ 'occult', 'expert' ] },
                                :spell_abil => { 'Witch' => 'Intelligence' }, :spells_per_day => { 'Witch' => slots },
                                :spellbook => { 'Witch' => { '1' => [ 'Fear' ], '3' => [ 'Slow' ] } },
                                :spells_prepared => { 'Witch' => { '1' => [ 'Fear' ], '3' => [ 'Slow' ] } },
                                :spells_today => { 'Witch' => { '1' => [ 'Fear' ], '3' => [ 'Slow' ] } })
        char.update(:combat => combat, :hp => hp, :magic => magic, :pf2_level => 12, :pf2_conditions => {}, :pf2_traits => [],
                    :pf2_derived => {}, :pf2_feats => {}, :pf2_daily_choices => {},
                    :pf2_base_info => { 'charclass' => 'Witch', 'specialize' => 'Night' },
                    :pf2_features => { 'charclass_features' => [ 'Familiar' ] })
        @made += [ combat, hp, magic ] + Pf2e::ABILITIES.map do |ability|
          Pf2eAbilities.create(:character => char, :name => ability, :base_val => ability == 'Intelligence' ? 18 : 12)
        end
        Paths.apply_all!(Character[char.id])
        record = { 'name' => 'Smudge', 'species' => 'black cat', 'form' => 'land', 'source' => 'Familiar' }
        Character[char.id].update(:pf2_familiar => { 'approved' => record })
        @scene.participants.add char
        @made << char
        Character[char.id]
      end

      def encounter
        PF2Encounter[@encounter.id]
      end

      def run(cmd_class, text, who)
        @client.failures.clear
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
      end

      def pick(text)
        found = DailyChoices.pick!(Character[@witch.id], 'familiar', text)
        expect(found.ok?).to be(true), found.respond_to?(:code) ? found.code.to_s : ''
      end

      # Joined first in the order, with its familiar and a goblin; on Morwen's turn unless exploring.
      def fight(exploring: false)
        encounter.update(:mode => Exploration::MODE) if exploring
        @master_row = Combatants.join(encounter, @witch.name, 40, :holder => Character[@witch.id])
        Character[@witch.id].encounters.add encounter
        encounter.characters.add Character[@witch.id]
        run(PF2EncounterAddCmd, 'e/add Goblin=ac 15 hp 30', @gm)
        run(PF2EncounterFamiliarCmd, 'encounter/familiar', @witch)
        @ref = "##{Combatants.rows(encounter).find { |row| row['master'] }['id']}"
        @goblin = "##{Combatants.rows(encounter).find { |row| row['npc'] && !row['master'] }['id']}"
        run(PF2EncounterNextCmd, 'encounter/next', @gm) unless exploring
      end

      def master
        Pf2eCombatantState[@master_row['state']]
      end

      def familiar
        Pf2eNpc[Combatants.rows(encounter).find { |row| row['master'] }['npc']]
      end

      def command
        run(PF2EncounterActCmd, 'encounter/act command a minion=Smudge', @witch)
      end

      def cast(spell)
        run(PF2EncounterAsCmd, "encounter/as #{@ref}=cast #{spell}=#{@goblin}", @witch)
      end

      describe "its stat block" do
        it "should carry the spell with its master's tradition, spell DC and attack" do
          pick('Spellcasting (Fear)')
          fight

          entry = familiar.stat_block['spellcasting'].first
          stats = Pf2emagic.get_caster_stats(master, 'Witch')

          expect(entry['tradition']).to eq 'occult'
          expect(entry['dc']).to eq Acting.spell_figure(master, 'spell_dc', stats)
          expect(entry['attack']).to eq Acting.spell_figure(master, 'spell_attack', stats)
          expect(entry['spells']).to eq('1' => [ 'Fear' ])
        end

        it "should carry none without the ability" do
          pick('Darkvision')
          fight

          expect(familiar.stat_block['spellcasting']).to eq []
        end
      end

      describe "casting" do
        before(:each) do
          pick('Spellcasting (Fear)')
          fight
        end

        it "should cast the spell once a day, Commanded, without spending a slot" do
          command
          cast('fear')

          expect(@client.failures).to eq []
          expect(@client.said.join).to include(t('pf2e.familiar_cast_drawback', :name => 'Smudge', :master => @witch.name))
          expect(TurnState.used(master, 'Spellcasting')).to eq 1
          expect(master.magic.spells_today['Witch']['1']).to eq [ 'Fear' ]

          TurnState.write(familiar, 'turn' => TurnState.turn(familiar).merge('actions' => 0))
          cast('fear')

          expect(@client.failures.join).to include(t('pf2e.familiar_action_used', :name => 'Smudge', :action => 'Spellcasting'))
        end

        it "should need a command" do
          cast('fear')

          expect(@client.failures.join).to include('Smudge has no actions left this turn')
        end

        it "should refuse another spell" do
          command
          cast('slow')

          expect(@client.failures.join).to include(t('pf2e.familiar_cast_only', :name => 'Smudge', :spell => 'Fear'))
        end

        it "should refuse the spell once it is no longer prepared" do
          master.magic.update(:spells_today => { 'Witch' => { '3' => [ 'Slow' ] } })
          command
          cast('fear')

          expect(@client.failures.join).to include(t('pf2e.familiar_cast_gone', :spell => 'Fear'))
        end

        it "should carry the day's casting into an encounter carried on from this one" do
          command
          cast('fear')

          later = PF2Encounter.create(:scene => @scene, :owner => @gm, :round => 0, :carries_on_from => @encounter.id)
          carried = CombatantStates.for_join(later, Character[@witch.id])

          expect(TurnState.used(carried, 'Spellcasting')).to eq 1
        end
      end

      it "should cast while exploring without a command" do
        pick('Spellcasting (Fear)')
        fight(exploring: true)

        cast('fear')

        expect(@client.failures).to eq []
        expect(TurnState.used(master, 'Spellcasting')).to eq 1
      end

      it "should refuse a familiar without the ability" do
        pick('Darkvision')
        fight
        command
        cast('fear')

        expect(@client.failures.join).to include(t('pf2e.familiar_cast_none', :name => 'Smudge'))
      end
    end
  end
end
