require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # An animal companion on the web portal: the profile's Animal Companion tab and the picture chosen for it on the
    # Edit page, the Inventory tab's section for what it wears, and its row on the encounter page. The master is a
    # level 1 druid of the animal order with an approved wolf, Ash.
    describe "an animal companion on the portal", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        allow(Jobs).to receive(:notify)
        allow(Login).to receive(:notify)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Scenes).to receive(:add_to_scene)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))

        @client = AutoBuilder::CaptureClient.new
        @char = Character.create(:name => "Rowan#{rand(1000000)}")
        @viewer = Character.create(:name => "Viewer#{rand(1000000)}")

        builder = AutoBuilder.new(@char)
        builder.prefer.merge!('Animal Companion' => 'Wolf')
        builder.build_level_one('Druid', specialty: 'Animal')

        run(PF2CompanionNameCmd, 'companion/name Ash')
        Roles.add_role(Character[@char.id], 'approved')
        Ledger.commit_chargen!(Character[@char.id])
        Companion.approve_with_app!(Character[@char.id])
        @char = Character[@char.id]
      end

      after(:each) do
        PF2Encounter.find(:scene_id => @scene.id).each do |one|
          one.npcs.each(&:delete)
          one.states.each(&:delete)
          one.delete
        end if @scene
        [ @char, @viewer, @gm, @scene, @room ].each { |one| one&.delete }
      end

      def run(klass, text, who = @char)
        @client.clear
        klass.new(@client, Command.new(text), Character[who.id]).on_command
        @char = Character[@char.id]
      end

      def view
        Companion::ProfileView.of(Character[@char.id])
      end

      def stats
        Companion.stats(@char, Companion.main(@char), :draft => false)
      end

      def give(category, name)
        Pf2egear.create_item(Character[@char.id], category, name, 1, Global.read_config(Pf2egear::Inventory.config(category), name))
        @char = Character[@char.id]
      end

      def wear_barding!
        give('gear', 'Light Barding (Small or Medium)')
        index = Pf2egear::Inventory.held(@char, 'gear').index { |item| item.name == 'Light Barding (Small or Medium)' }
        run(PF2CompanionWearCmd, "companion/wear gear=#{index}")
        expect(@client.failures).to eq []
      end

      # Files in the character's folder, as the Edit page offers them.
      def files!(names)
        folder = "#{@char.name.downcase}"
        allow(Profile).to receive(:character_page_folder).and_return(folder)
        allow(FamiliarPicture).to receive(:files).and_return(names.map { |name| "#{folder}/#{name}" })
        allow(Website).to receive(:get_file_info) { |path| { name: File.basename(path), path: path } }
        folder
      end

      describe "the Animal Companion tab" do
        it "should be drawn for a character with an approved companion" do
          expect(ProfileSheet.flags(@char, @viewer)).to include(companion: true)
          expect(ProfileSheet.refusal(@char, @viewer, 'companion')).to be_nil
        end

        it "should be refused for a companion staff haven't approved" do
          held = Companion.record(@char)
          held['companions'].each_value { |entry| entry.delete('approved') }
          @char.update(:pf2_companions => held)

          expect(ProfileSheet.refusal(Character[@char.id], @viewer, 'companion').code).to eq :no_companion
          expect(ProfileSheet.flags(Character[@char.id], @viewer)).to include(companion: false)
        end

        it "should give the companion's name, master and stats as the sheet works them out" do
          shown = view

          expect(shown[:name]).to eq 'Ash'
          expect(shown[:master]).to eq @char.name
          expect(shown[:type]).to eq 'Wolf'
          expect(shown[:level]).to eq 1
          expect(shown[:hp]).to eq stats['hp']
          expect(shown[:ac]).to eq stats['ac']
          expect(shown[:saves].map { |save| save[:value] }).to eq stats['saves'].values
          expect(shown[:attacks].first).to include(name: 'Jaws', attack: stats['attacks'].first['bonus'], rank: 'trained')
          expect(shown[:attacks].first[:damage]).to eq Companion.damage(stats['attacks'].first)
          expect(shown[:maneuver]).to eq(later: 'Takedown')
          expect(shown[:dead]).to be false
        end

        it "should send its advanced maneuver as HTML, with its markdown and line breaks formatted" do
          shown = Companion::ProfileView.maneuver({ 'type' => 'Wolf' }, { 'maneuver' => true })

          expect(shown[:name]).to start_with 'Takedown'
          expect(shown[:description]).to include '<strong>Requirements</strong>'
          expect(shown[:description]).not_to include '%r'
          expect(shown[:description]).not_to include '**'
        end

        it "should send its support benefit as HTML" do
          expect(view[:support]).to start_with '<p>'
          expect(view[:support]).to include 'Your wolf tears tendons'
        end

        it "should name the companion and its master in its notes, and send no colour codes" do
          expect(view[:notes]).to include("Ash acts when #{@char.name} Commands an Animal, gaining 2 actions.")
          expect(view.to_s).not_to include('%x')
        end

        it "should list what it wears" do
          wear_barding!

          expect(view[:gear][:barding][:name]).to eq 'Light Barding (Small or Medium)'
          expect(view[:gear][:invested]).to eq []
          expect(view[:gear][:invest_limit]).to eq 2
          expect(view[:ac]).to eq stats['ac']
        end

        it "should stay for a dead companion, saying so" do
          Companion.mark_dead!(@char, :dead => true)

          expect(ProfileSheet.flags(Character[@char.id], @viewer)).to include(companion: true)
          expect(view[:dead]).to be true
        end

        it "should answer the portal's request" do
          request = double(:args => { 'id' => @char.id }, :enactor => nil)
          allow(ProfileSheet).to receive(:anonymous?).and_return(true)

          expect(PF2ProfileCompanionHandler.new.handle(request)[:name]).to eq 'Ash'
        end
      end

      describe "the companion's picture" do
        it "should be chosen from the character's files, shown on the tab, and cleared" do
          folder = files!([ 'ash.png' ])

          expect(Companion::Picture.choose!(@char, 'Ash.png').ok?).to be true
          expect(view[:image]).to eq "#{folder}/ash.png"

          Companion::Picture.choose!(Character[@char.id], '')
          expect(view[:image]).to be_nil
        end

        it "should refuse a file that isn't theirs" do
          files!([ 'ash.png' ])

          expect(Companion::Picture.choose!(@char, 'other.png').code).to eq :not_their_file
        end

        it "should be offered and saved through the Edit page" do
          folder = files!([ 'ash.png' ])

          fields = Profile::CustomCharFields.get_fields_for_editing(@char, @char)
          expect(fields[:pf2_companion]).to eq(name: 'Ash', image: nil)

          errors = Profile::CustomCharFields.save_fields_from_profile_edit2(@char, @char, 'custom' => { 'pf2_companion_image' => 'ash.png' })
          expect(errors).to eq []
          expect(Companion::Picture.path(Character[@char.id])).to eq "#{folder}/ash.png"
        end
      end

      describe "the Inventory tab" do
        it "should give what the companion wears a section of its own" do
          wear_barding!
          shown = Pf2egear::InventoryView.of(Character[@char.id])

          expect(shown[:companion_worn][:name]).to eq 'Ash'
          expect(shown[:companion_worn][:items].map { |one| one[:item][:name] }).to eq [ 'Light Barding (Small or Medium)' ]
          expect(shown[:companion_worn][:items].first).to include(kind: 'Barding', bulk: '2', invested: nil)
          expect(shown[:gear].map { |one| one[:item][:name] }).not_to include('Light Barding (Small or Medium)')
        end

        it "should have no such section when the companion wears nothing" do
          expect(Pf2egear::InventoryView.of(@char)[:companion_worn]).to be_nil
        end
      end

      describe "the encounter page" do
        before(:each) do
          @room = Room.create(:name => "Field#{rand(1000000)}")
          @scene = Scene.create(:room => @room, :temp_room => true)
          @room.update(:scene => @scene)
          @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
          @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :round => 0)

          goblin = Pf2eNpc.create(:encounter => @encounter, :name => 'Goblin', :number => @encounter.last_number.to_i + 1,
                                  :described => { 'name' => 'Goblin', 'level' => 1, 'hp' => 20, 'ac' => 8, 'perception' => 5,
                                                  'saves' => { 'fortitude' => 5, 'reflex' => 7, 'will' => 3 } })
          Combatants.join(PF2Encounter[@encounter.id], 'Goblin', 20, :holder => goblin)
          Combatants.join(PF2Encounter[@encounter.id], @char.name, 15, :holder => Character[@char.id])
          Character[@char.id].encounters.add PF2Encounter[@encounter.id]
          PF2Encounter[@encounter.id].characters.add Character[@char.id]
          Combatants.join(PF2Encounter[@encounter.id], 'Orc', 10)
          Character[@char.id].update(:room => @room)
          run(PF2EncounterCompanionCmd, 'encounter/companion')
        end

        def page(viewer)
          request = double(:args => { 'id' => @encounter.id }, :enactor => viewer)
          allow(Website).to receive(:check_login).and_return(nil)
          PF2EncounterHandler.new.handle(request)
        end

        def row(viewer, name)
          page(viewer)[:combatants].find { |one| one[:name] == name }
        end

        it "should list the companion straight after its master, with no initiative" do
          names = page(@viewer)[:combatants].map { |one| one[:name] }

          expect(names).to eq [ 'Goblin', @char.name, 'Ash', 'Orc' ]
          expect(row(@viewer, 'Ash')[:initiative]).to be_nil
          expect(row(@viewer, 'Ash')[:minion]).to be true
          expect(row(@viewer, @char.name)[:initiative]).to eq 15
        end

        it "should say whose companion it is, and show its hit points as a character's" do
          ash = row(@viewer, 'Ash')

          expect(ash[:lines]).to eq [ "#{@char.name}'s animal companion" ]
          expect(ash[:hp]).to eq Harm.hit_points(Combatants.find(PF2Encounter[@encounter.id], 'Ash').state.holder)
          expect(row(@viewer, 'Goblin')[:hp]).to eq Harm.looks(Combatants.find(PF2Encounter[@encounter.id], 'Goblin').state.holder)
        end

        it "should say who rides whom, and that rider and mount share the attack penalty" do
          allow(Companion::Block).to receive(:of).and_wrap_original { |original, npc| original.call(npc).merge('size' => 'Large') }
          2.times { run(PF2EncounterNextCmd, 'encounter/next', @gm) }
          run(PF2EncounterActCmd, 'encounter/act mount=Ash')
          allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ sides.to_i == 20 ? 10 : 3 ] * amount.to_i }
          run(PF2EncounterStrikeCmd, 'encounter/strike fist=Goblin')

          expect(row(@viewer, @char.name)[:lines]).to eq [ 'riding Ash' ]
          expect(row(@viewer, 'Ash')[:lines]).to eq [ "#{@char.name}'s animal companion", "ridden by #{@char.name}" ]
          expect(row(@viewer, 'Ash')[:turn]).to end_with("next attack at -5, shared with #{@char.name}")
        end

        it "should say what a ranger hunts" do
          state = Combatants.find(PF2Encounter[@encounter.id], @char.name).state.holder
          HuntPrey.mark!(state, HuntPrey::EFFECT, HuntPrey::SLUG, 'Goblin', @char.name, PF2Encounter[@encounter.id])

          expect(row(@viewer, @char.name)[:lines]).to eq [ 'hunting Goblin (#1)' ]
        end
      end
    end
  end
end
