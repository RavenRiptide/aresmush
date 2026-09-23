require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An encounter's GM: whoever owns it, wherever they are, and staff.
    describe "an encounter's GM", :dbtest => true do

      class GmClient
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
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = GmClient.new
        @room = Room.create(:name => "Keep#{rand(1000000)}")
        @elsewhere = Room.create(:name => "Tavern#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @elsewhere)
        @other = Character.create(:name => "Other#{rand(1000000)}", :room => @elsewhere)
        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :organizer => @gm.name, :round => 1,
                                         :is_active => true)
        @encounters = [ @encounter ]

        allow(Login).to receive(:emit_ooc_if_logged_in)
      end

      after(:each) do
        @encounters.each { |one| PF2Encounter[one.id]&.delete }
        [ @gm, @other, @scene, @room, @elsewhere ].each { |one| one&.delete }
      end

      def run(cmd_class, text, who = @gm)
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
      end

      it "should be its owner, whatever they are called now" do
        Character[@gm.id].update(:name => "Renamed#{rand(1000000)}")

        expect(PF2Encounter.is_organizer?(Character[@gm.id], PF2Encounter[@encounter.id])).to be true
        expect(PF2Encounter.is_organizer?(Character[@other.id], PF2Encounter[@encounter.id])).to be false
      end

      it "should be any admin as well" do
        allow_any_instance_of(Character).to receive(:is_admin?).and_return(true)

        expect(PF2Encounter.is_organizer?(Character[@other.id], PF2Encounter[@encounter.id])).to be true
      end

      it "should reach the encounter they run from away from its scene" do
        expect(Combatants.encounter_here(Character[@gm.id])).to eq PF2Encounter[@encounter.id]
        expect(Combatants.encounter_here(Character[@other.id])).to be_nil
      end

      it "should need to choose among several they run, with +e/focus" do
        second = PF2Encounter.create(:owner => @gm, :organizer => @gm.name, :round => 1, :is_active => true)
        @encounters << second

        expect(Combatants.encounter_here(Character[@gm.id])).to be_nil

        run(PF2EncounterFocusCmd, "e/focus #{second.id}")

        expect(Combatants.encounter_here(Character[@gm.id])).to eq second
      end

      it "should refuse a focus on someone else's encounter" do
        run(PF2EncounterFocusCmd, "e/focus #{@encounter.id}", @other)

        expect(@client.failures).to eq [ t('pf2e.not_organizer') ]
      end

      it "should hand the encounter to someone else, who runs it from then on" do
        run(PF2EncounterOwnerCmd, "e/owner #{@encounter.id}=#{@other.name}")

        handed = PF2Encounter[@encounter.id]
        expect(PF2Encounter.is_organizer?(Character[@other.id], handed)).to be true
        expect(PF2Encounter.is_organizer?(Character[@gm.id], handed)).to be false
        expect(handed.organizer).to eq @other.name
      end

      it "should let only its GM hand it over" do
        run(PF2EncounterOwnerCmd, "e/owner #{@encounter.id}=#{@other.name}", @other)

        expect(@client.failures).to eq [ t('pf2e.not_organizer') ]
        expect(PF2Encounter.is_organizer?(Character[@other.id], PF2Encounter[@encounter.id])).to be false
      end

      it "should keep an encounter from before owners were held its organizer's, by name" do
        old = PF2Encounter.create(:organizer => @gm.name, :round => 1, :is_active => true)
        @encounters << old

        expect(PF2Encounter.is_organizer?(Character[@gm.id], old)).to be true
      end
    end
  end
end
