require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Daily choices that name a creature: a witch's charges, the ally given a Root Magic pouch, and the allies
    # a mastermind reviews stratagems with.
    describe "designations", :dbtest => true do

      class DesignationClient
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

        @client = DesignationClient.new
        @room = Room.create(:name => "Grove#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @made = []

        @giver = person("Giver", 'Witch', [ "Witch's Charge", 'Root Magic', 'Inspired Stratagem' ])
        @ally = person("Ally", 'Fighter', [])
        @other = person("Other", 'Fighter', [])
        @stranger = person("Stranger", 'Fighter', [])
        @occultism = Pf2eSkills.create(:character => @giver, :name => 'Occultism', :prof_level => 'expert')

        unapproved = @stranger.id
        allow_any_instance_of(Character).to receive(:is_approved?) { |char| char.id != unapproved }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow(Scenes).to receive(:add_to_scene)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Login).to receive(:notify)
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete if @encounter
        @occultism.delete
        @made.reverse.each(&:delete)
        [ @scene, @room ].each(&:delete)
      end

      def person(prefix, charclass, feats)
        char = Character.create(:name => "#{prefix}#{rand(1000000)}", :room => @room, :pf2_level => 10, :pf2_conditions => {},
                                :pf2_traits => [], :pf2_derived => {}, :pf2_roll_options => {}, :pf2_daily_choices => {},
                                :pf2_base_info => { 'charclass' => charclass }, :pf2_feats => { 'charclass' => feats },
                                :pf2_features => { 'charclass_features' => [] })
        hp = Pf2eHP.create(:character => char, :ancestry_hp => 8, :charclass_hp => 8)
        combat = Pf2eCombat.create(:character => char, :saves => { 'Will' => 'expert', 'Fortitude' => 'trained', 'Reflex' => 'trained' })
        char.update(:hp => hp, :combat => combat)
        abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => char, :name => name, :base_val => name == 'Intelligence' ? 18 : 12) }

        @made += abilities + [ hp, combat, char ]
        char
      end

      def fresh(char)
        Character[char.id]
      end

      def prepare(text, who = @giver)
        PF2PrepareDailyCmd.new(@client, Command.new(text), fresh(who)).on_command
      end

      def unprepare(text, who = @giver)
        PF2UnprepareDailyCmd.new(@client, Command.new(text), fresh(who)).on_command
      end

      def start
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => @giver.name, :round => 1, :is_active => true)
      end

      def join(char)
        fresh(char).encounters.add @encounter
        PF2Encounter[@encounter.id].characters.add fresh(char)
        Combatants.join(PF2Encounter[@encounter.id], char.name, 10, :holder => fresh(char))
      end

      def state(char)
        CombatantStates.of(PF2Encounter[@encounter.id], fresh(char))
      end

      def effects(char, name)
        ActiveEffects.named_on(state(char), name)
      end

      describe "naming" do
        it "should route the switches a designation declares" do
          %w{charge rootmagic stratagem}.each do |switch|
            expect(Pf2emagic.get_cmd_handler(@client, Command.new("prepare/#{switch} x"), fresh(@giver))).to eq PF2PrepareDailyCmd
          end
        end

        it "should name an approved character, and record them by name" do
          prepare("prepare/charge #{@ally.name.downcase}")

          expect(@client.failures).to eq []
          expect(fresh(@giver).pf2_daily_choices['charge']['names']).to eq [ @ally.name ]
        end

        it "should refuse an unapproved character, and someone who isn't there at all" do
          prepare("prepare/charge #{@stranger.name}")
          prepare('prepare/charge Nobody At All')

          expect(@client.failures).to eq [ t('pf2e.daily_unapproved', :name => @stranger.name, :source => "Witch's Charge"),
                                           t('pf2e.daily_no_creature', :name => 'Nobody At All', :source => "Witch's Charge") ]
        end

        it "should refuse themselves where the source says so" do
          prepare("prepare/rootmagic #{@giver.name}")

          expect(@client.failures).to eq [ t('pf2e.daily_not_self', :source => 'Root Magic') ]
        end

        it "should name one charge, or as many as Witch's Communion gives" do
          prepare("prepare/charge #{@ally.name}, #{@other.name}")

          expect(@client.failures).to eq [ t('pf2e.daily_too_many', :source => "Witch's Charge", :count => 1, :named => 2) ]

          @giver.update(:pf2_feats => { 'charclass' => [ "Witch's Charge", "Witch's Communion" ] })
          prepare("prepare/charge #{@ally.name}, #{@other.name}")

          expect(@client.failures.size).to eq 1
          expect(fresh(@giver).pf2_daily_choices['charge']['names']).to eq [ @ally.name, @other.name ]
        end

        it "should name a creature only in an encounter, by its label there" do
          start
          join(@giver)
          npc = Pf2eNpc.create(:name => 'Wolf', :level => 1)
          Combatants.join(PF2Encounter[@encounter.id], 'Wolf', 5, :holder => npc)
          @made << npc

          prepare('prepare/charge wolf')

          expect(@client.failures).to eq []
          expect(fresh(@giver).pf2_daily_choices['charge']['creatures']).to eq [ { 'creature' => 'Wolf', 'encounter' => @encounter.id.to_s } ]
          expect(ActiveEffects.named_on(Pf2eNpc[npc.id], "Effect: Witch's Charge").size).to eq 1
        end
      end

      describe "what a designation gives" do
        it "should put the effect on a charge already in an encounter, from the witch" do
          start
          join(@ally)
          prepare("prepare/charge #{@ally.name}")

          given = effects(@ally, "Effect: Witch's Charge")

          expect(given.size).to eq 1
          expect(given.first.granted_by).to eq "#{@giver.name}'s Witch's Charge"
        end

        it "should put it on them when they join an encounter later" do
          prepare("prepare/charge #{@ally.name}")
          start
          join(@ally)

          expect(effects(@ally, "Effect: Witch's Charge").size).to eq 1
        end

        it "should take it back with the pick" do
          start
          join(@ally)
          prepare("prepare/charge #{@ally.name}")
          unprepare('unprepare/charge')

          expect(effects(@ally, "Effect: Witch's Charge")).to eq []
        end

        it "should give Root Magic's bonus by the giver's Occultism rank, to the first save against a spell" do
          start
          join(@ally)
          prepare("prepare/rootmagic #{@ally.name}")

          spell = DamageAbout.spell('Fear')
          against = Check.of(state(@ally), 'save', 'will', spell).total
          plain = Check.of(state(@ally), 'save', 'will', []).total

          expect(against - plain).to eq 2

          Resolve.roll(Check.of(state(@ally), 'save', 'will', spell), :dc => 15)

          expect(effects(@ally, 'Effect: Root Magic')).to eq []
        end
      end

      # encounter/act ends by recording the roll on the acting character. Ohm saves every attribute, so the
      # record has to be written to the character as the action left it, not as the command found it.
      describe "a write to the acting character during encounter/act" do
        it "should survive the command's record of the roll" do
          start
          join(@giver)
          allow(Acting).to receive(:spend).and_wrap_original do |original, *args|
            original.call(*args)
            Character[@giver.id].update(:pf2_alchemy_plan => { 'Marker' => 1 })
          end

          PF2EncounterActCmd.new(@client, Command.new('e/act take cover'), fresh(@giver)).on_command

          expect(Acting).to have_received(:spend)
          expect(fresh(@giver).pf2_alchemy_plan).to eq('Marker' => 1)
        end
      end

      describe "Inspired Stratagem" do
        before(:each) do
          start
          join(@giver)
          join(@ally)
          join(@other)
        end

        def refusal(target)
          found = Combatants.find(PF2Encounter[@encounter.id], target.name)

          DailyChoices.limit_refusal(state(@giver), 'Inspired Stratagem', found.state, PF2Encounter[@encounter.id])
        end

        it "should reach only the allies picked, before anyone is picked too" do
          expect(refusal(@ally).code).to eq :unpicked

          prepare("prepare/stratagem #{@ally.name}")

          expect(refusal(@ally)).to be_nil
          expect(refusal(@other).code).to eq :not_named
        end

        it "should put the effect on the ally through encounter/act, and refuse them the second time" do
          prepare("prepare/stratagem #{@ally.name}")
          act = lambda do
            PF2EncounterActCmd.new(@client, Command.new("e/act inspired stratagem=#{@ally.name}"), fresh(@giver)).on_command
          end

          act.call

          expect(@client.failures).to eq []
          expect(effects(@ally, 'Effect: Inspired Stratagem').size).to eq 1

          @client.said.clear
          act.call

          immune = t('pf2e.daily_limited_immune', :target => @ally.name, :action => 'Inspired Stratagem')

          expect((@client.failures + @client.said).join).to include immune
          expect(effects(@ally, 'Effect: Inspired Stratagem').size).to eq 1
        end

        it "should make the ally immune once it reaches them, until the giver's rest" do
          prepare("prepare/stratagem #{@ally.name}")
          found = Combatants.find(PF2Encounter[@encounter.id], @ally.name).state
          DailyChoices.limit_used!(state(@giver), 'Inspired Stratagem', found)

          expect(refusal(@ally).code).to eq :immune

          Pf2e.rest(state(@giver))

          expect(refusal(@ally).code).to eq :unpicked

          prepare("prepare/stratagem #{@ally.name}")

          expect(refusal(@ally)).to be_nil
        end
      end
    end
  end
end
