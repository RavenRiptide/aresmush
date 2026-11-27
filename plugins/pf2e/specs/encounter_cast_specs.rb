require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # `+e/cast`, through the command a player types.
    #
    # A caster who names no class casts from the one they have, which the command works out from their
    # spellcasting entries. Nothing covered that, and it asked those entries for a key they do not carry,
    # so every class caster was told they had no magical ability.
    describe "casting in an encounter", :dbtest => true do

      class CastClient
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

        @client = CastClient.new
        @room = Room.create(:name => "Hall#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Cora#{rand(1000000)}", :room => @room, :pf2_level => 1,
                                 :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {},
                                 :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @combat = Pf2eCombat.create(:character => @hero)
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 6)
        @magic = PF2Magic.create(:character => @hero,
                                 :tradition => { 'Sorcerer' => [ 'primal', 'trained' ] },
                                 :spell_abil => { 'Sorcerer' => 'Charisma' },
                                 :spells_per_day => { 'Sorcerer' => { '1' => 3 } },
                                 :repertoire => { 'Sorcerer' => { '1' => [ 'Charm' ] } })
        @hero.update(:combat => @combat, :hp => @hp, :magic => @magic,
                     :pf2_base_info => { 'charclass' => 'Sorcerer' })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :organizer => @gm.name, :round => 1,
                                         :is_active => true)
        Combatants.join(@encounter, @hero.name, 10, :holder => Character[@hero.id])

        allow_any_instance_of(Room).to receive(:emit)
        allow_any_instance_of(Room).to receive(:emit_ooc)
        allow(Scenes).to receive(:add_to_scene)
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * 0.75).ceil, 1 ].max ] * amount.to_i }
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete
        (@abilities + [ @magic, @hp, @combat, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def rested
        PF2EncounterRestCmd.new(@client, Command.new('e/rest'), Character[@gm.id]).on_command
      end

      def cast(text)
        PF2EncounterCastCmd.new(@client, Command.new(text), Character[@hero.id]).on_command
      end

      def standing
        CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id])
      end

      def slots_left
        (standing.magic.spells_today['Sorcerer'] || {})['1']
      end

      it "should cast from their own casting class when they name none" do
        rested
        expect(slots_left).to eq 3

        cast('e/cast Charm')

        expect(@client.failures).to eq []
        expect(slots_left).to eq 2
      end

      it "should cast from the class they name" do
        rested

        cast('e/cast Charm/class Sorcerer')

        expect(@client.failures).to eq []
        expect(slots_left).to eq 2
      end

      # A character who casts as two classes casts the spell from the list that holds it.
      it "should cast from whichever of their classes knows the spell" do
        @magic.update(:tradition => { 'Sorcerer' => [ 'primal', 'trained' ], 'Bard' => [ 'occult', 'trained' ] },
                      :spell_abil => { 'Sorcerer' => 'Charisma', 'Bard' => 'Charisma' },
                      :spells_per_day => { 'Sorcerer' => { '1' => 3 }, 'Bard' => { '1' => 2 } },
                      :repertoire => { 'Sorcerer' => { '1' => [ 'Charm' ] }, 'Bard' => { '1' => [ 'Soothe' ] } })

        ordered = PF2EncounterCastCmd.new(@client, Command.new('e/cast Soothe'), Character[@hero.id])
        ordered.parse_args

        expect(ordered.casting_class(Character[@hero.id])).to eq 'Bard'
      end

      # A wizard's Drain Bonded Item lets them cast again a spell they prepared today and have cast.
      describe "Drain Bonded Item" do
        before(:each) do
          @magic.update(:tradition => { 'Wizard' => [ 'arcane', 'trained' ] }, :spell_abil => { 'Wizard' => 'Intelligence' },
                        :spells_per_day => { 'Wizard' => { '1' => 1 } }, :repertoire => {},
                        :spells_prepared => { 'Wizard' => { '1' => [ 'Fear' ] } })
          @hero.update(:pf2_base_info => { 'charclass' => 'Wizard' },
                       :pf2_features => { 'charclass_features' => [ 'Drain Bonded Item' ], 'archetype_features' => [] })
          rested
        end

        def drain(text = 'e/act drain bonded item/fear')
          PF2EncounterActCmd.new(@client, Command.new(text), Character[@hero.id]).on_command
        end

        def fear_left
          Array((standing.magic.spells_today['Wizard'] || {})['1']).count('Fear')
        end

        it "should give back a spell cast today, to cast again" do
          cast('e/cast Fear')
          expect(fear_left).to eq 0

          drain

          expect(@client.failures).to eq []
          expect(fear_left).to eq 1
        end

        it "should refuse a spell not yet cast today" do
          drain

          expect(@client.failures.join).to include('Fear')
          expect(fear_left).to eq 1
        end

        # Superior Bond: a second drain a day, for a spell 2 or more ranks below the highest slot.
        describe "with Superior Bond" do
          before(:each) do
            @magic.update(:spells_per_day => { 'Wizard' => { '1' => 1, '2' => 1, '3' => 1 } },
                          :spells_prepared => { 'Wizard' => { '1' => [ 'Fear' ], '3' => [ 'Fireball' ] } })
            @hero.update(:pf2_feats => { 'charclass' => [ 'Superior Bond' ] })
            rested
            allow(Telling).to receive(:event).and_call_original
          end

          it "should allow a second drain a day" do
            expect(Actions.frequency(standing, 'Drain Bonded Item')).to include('max' => 2)
          end

          it "should say nothing of a second drain of a low enough spell" do
            2.times do
              cast('e/cast Fear')
              drain
            end

            expect(@client.failures).to eq []
            expect(fear_left).to eq 1
            expect(Telling).to_not have_received(:event).with('pf2e.drain_extra_too_high', anything)
          end

          it "should tell the GM of a second drain of a spell too high for it" do
            cast('e/cast Fear')
            drain
            cast('e/cast Fireball')
            drain('e/act drain bonded item/fireball')

            expect(Telling).to have_received(:event).with('pf2e.drain_extra_too_high',
                                                          hash_including(:feat => 'Superior Bond', :rank => '3', :highest => 1))
          end
        end

        # Linked Focus: a Focus Point back, once a day, for draining to cast a curriculum spell.
        describe "with Linked Focus" do
          before(:each) do
            @magic.update(:spells_prepared => { 'Wizard' => { '1' => [ 'Command' ] } })
            @hero.update(:pf2_feats => { 'charclass' => [ 'Linked Focus' ] },
                         :pf2_base_info => { 'charclass' => 'Wizard', 'specialize' => 'Department of Mana Syntaxia' })
            Pf2emagic::Entries.grant_focus!(Character[@hero.id], 'school', [ 'Hand of the Apprentice' ], :kind => 'spell')
            rested
            standing.update(:focus_current => 0)
          end

          after(:each) do
            Character[@hero.id].spellcasting_entries.each(&:delete)
          end

          it "should give back a Focus Point for draining to cast a curriculum spell" do
            cast('e/cast Command')
            drain('e/act drain bonded item/command')

            expect(@client.failures).to eq []
            expect(standing.focus_current).to eq 1
          end

          it "should give it back only once a day" do
            cast('e/cast Command')
            drain('e/act drain bonded item/command')
            standing.update(:focus_current => 0)
            cast('e/cast Command')
            drain('e/act drain bonded item/command')

            expect(standing.focus_current).to eq 0
          end

          it "should give nothing for a spell outside the curriculum" do
            @magic.update(:spells_prepared => { 'Wizard' => { '1' => [ 'Fear' ] } })
            rested
            standing.update(:focus_current => 0)
            cast('e/cast Fear')
            drain

            expect(standing.focus_current).to eq 0
          end
        end
      end

      # A prepared spell named without a rank is cast from the rank it is prepared at.
      it "should cast a prepared spell named without a rank" do
        @magic.update(:tradition => { 'Wizard' => [ 'arcane', 'trained' ] }, :spell_abil => { 'Wizard' => 'Intelligence' },
                      :spells_per_day => { 'Wizard' => { '1' => 1, '2' => 1 } }, :repertoire => {},
                      :spells_prepared => { 'Wizard' => { '2' => [ 'Fear' ] } })
        @hero.update(:pf2_base_info => { 'charclass' => 'Wizard' })
        rested

        cast('e/cast Fear')

        expect(@client.failures).to eq []
        expect(Array(standing.magic.spells_today['Wizard']['2'])).to eq []
      end

      # Storm's Lash grants Electric Arc innately. A Fighter has no class to cast from, so the command
      # found none and told them they had no magical ability unless they typed /innate.
      describe "a spell a feat grants innately" do
        def grant_electric_arc
          @magic.update(:innate_spells => [ { 'name' => 'Electric Arc', 'level' => 'cantrip',
                                              'tradition' => 'primal', 'cast_stat' => 'Charisma' } ])
        end

        it "should cast it as innate for a character with no casting class" do
          @magic.update(:tradition => { 'innate' => [ 'innate', 'trained' ] }, :spell_abil => {},
                        :spells_per_day => {}, :repertoire => {})
          @hero.update(:pf2_base_info => { 'charclass' => 'Fighter' })
          grant_electric_arc

          cast("e/cast Electric Arc=#{@hero.name}")

          expect(@client.failures).to eq []
        end

        # Before, a caster fell back to their own class, which does not know it.
        it "should cast it as innate when none of their classes knows it" do
          grant_electric_arc
          rested

          cast("e/cast Electric Arc=#{@hero.name}")

          expect(@client.failures).to eq []
          expect(slots_left).to eq 3
        end

        it "should still cast from a class that knows the spell" do
          grant_electric_arc

          ordered = PF2EncounterCastCmd.new(@client, Command.new('e/cast Charm'), Character[@hero.id])
          ordered.parse_args

          expect(ordered.innate_by_default?(Character[@hero.id])).to be false
        end
      end

      # Form Retention: a battle form cast from a slot 2 ranks higher lasts 10 minutes.
      describe "Form Retention" do
        before(:each) do
          per_day = (1..5).to_h { |rank| [ rank.to_s, 1 ] }
          @magic.update(:tradition => { 'Wizard' => [ 'arcane', 'trained' ] }, :spell_abil => { 'Wizard' => 'Intelligence' },
                        :spells_per_day => { 'Wizard' => per_day }, :repertoire => {},
                        :spellbook => { 'Wizard' => { '3' => [ 'Insect Form' ] } }, :spells_prepared => { 'Wizard' => {} })
          @hero.update(:pf2_level => 9, :pf2_base_info => { 'charclass' => 'Wizard' },
                       :pf2_feats => { 'charclass' => [ 'Form Retention' ] })
          Pf2emagic::SlotFeats.prepare_pair(Character[@hero.id], Pf2emagic::SlotFeats.for_switch(Character[@hero.id], 'formretention'),
                                            5, [ 'Insect Form' ])
          rested
        end

        it "should put the battle form on them for 10 minutes, at its own rank" do
          cast('e/cast Insect Form/ant')

          effect = standing.pf2_effects.to_a.find { |one| one.name == 'Spell Effect: Insect Form' }

          expect(@client.failures).to eq []
          expect([ effect.unit, effect.duration.to_i ]).to eq [ 'minutes', 10 ]
          expect(Array((standing.magic.spells_today[Pf2emagic::SlotFeats::TODAY] || {})['Wizard'])).to eq []
        end
      end

      it "should say which class casts it, so the lookup cannot quietly answer nothing" do
        expect(PF2EncounterCastCmd.new(@client, Command.new('e/cast Charm'), Character[@hero.id])
                 .casting_class(Character[@hero.id])).to eq 'Sorcerer'
      end
    end
  end
end
