require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Hero Points: a scene's, one to start with and three at most; awarded to the whole party by whoever
    # runs the scene; spent to roll a check again, to add 10 to a low one, or not to die.
    describe "Hero Points", :dbtest => true do
      include FightBench

      before(:each) do
        bench!
        # The bench decides every die; here it decides what is thrown, so the record of the dice is kept.
        allow(Pf2e).to receive(:roll_dice).and_call_original
        allow(Pf2e).to receive(:throw_dice) { |amount, sides| [ [ (sides.to_i * @dice).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit_ooc) { |_room, message| @client.said << message.to_s }
        allow(Login).to receive(:find_game_client).and_return(@client)
        allow(Global).to receive(:plugin_manager).and_return(double(:sorted_plugins => [ Pf2e, Pf2egear, Pf2emagic ], :shortcuts => {}))
        @friend = Character.create(:name => "Bren#{rand(1000000)}", :room => @room)
        @scene.participants.add @friend
      end

      after(:each) do
        @friend.delete
        clear_bench!
      end

      def scene
        Scene[@scene.id]
      end

      def points(char = @hero)
        HeroPoints.held(scene, char)
      end

      def as_friend(text)
        @client.said.clear
        @client.failures.clear
        run(Pf2e.get_cmd_handler(@client, Command.new(text), Character[@friend.id]), text, @friend)
      end

      def gm_types(text)
        @client.said.clear
        @client.failures.clear
        run(Pf2e.get_cmd_handler(@client, Command.new(text), Character[@gm.id]), text, @gm)
      end

      describe "what a scene gives" do
        it "should start each player character with one, and whoever runs it with none" do
          expect([ points, points(@friend), points(@gm) ]).to eq [ 1, 1, 0 ]
        end

        it "should tell a player what they hold" do
          hero_types('hero')

          expect(heard).to include(t('pf2e.hero_held', :count => 1, :most => 3))
        end

        it "should be on their combat sheet, and under their row of the GM's table" do
          run(PF2DisplayCombatSheetCmd, 'sheet/combat', @hero)
          expect(heard).to include("Hero Points%xn: #{t('pf2e.hero_sheet', :count => 1, :most => 3)}".gsub(/%x(?:\d{1,3}|[a-zA-Z])/, ''))

          @client.said.clear
          run(PF2EncounterScanCmd, 'e/scan')
          expect(heard).to include(t('pf2e.hero_scan', :count => 1))
        end

        it "should show whoever runs it the party's" do
          gm_types('hero')

          expect(heard).to include("#{@hero.name} 1", "#{@friend.name} 1")
          expect(heard).to_not include(@gm.name)
        end
      end

      describe "an award" do
        it "should give the whole party one, and tell the room" do
          gm_types('hero/award a clever plan')

          expect([ points, points(@friend), points(@gm) ]).to eq [ 2, 2, 0 ]
          expect(heard).to include('awards the party a Hero Point for a clever plan', "#{@hero.name} 2")
        end

        it "should stop at three" do
          3.times { gm_types('hero/award') }

          expect(points).to eq 3
          expect(heard).to include(t('pf2e.hero_award_full', :name => @hero.name, :count => 3))
        end

        it "should be refused to a player" do
          hero_types('hero/award')

          expect(refused).to eq [ t('pf2e.hero_not_runner') ]
          expect(points(@friend)).to eq 1
        end
      end

      describe "spent on their own Strike" do
        before(:each) do
          add('giant rat')
          next_turn
          next_turn
          expect(ActiveEffects.current_turn(encounter)).to eq @hero.name
          hero_types('e/strike #2=fist', FightBench::LOW)
        end

        def rat_damage
          npc.damage.to_i
        end

        it "should roll it again, and have the second roll stand" do
          expect(rat_damage).to eq 0
          entries = History.entries(encounter).size

          hero_types('hero/reroll', FightBench::HIGH)

          expect(refused).to eq []
          expect(rat_damage).to be > 0
          expect(heard).to include('spends a Hero Point to roll again a check that rolled 1', '- hit')
          expect(points).to eq 0
          expect(History.entries(encounter).size).to eq entries
          expect(History.latest(encounter).heroes).to eq [ @hero.name ]

          @client.said.clear
          run(PF2EncounterHistoryCmd, 'e/history')
          expect(heard).to include(t('pf2e.hero_history', :names => @hero.name))
        end

        it "should be one Strike made, and not two" do
          hero_types('hero/reroll', FightBench::HIGH)

          turn = TurnState.turn(hero)
          expect([ turn['attacks'].to_i, turn['actions'].to_i ]).to eq [ 1, 1 ]
        end

        it "should add 10 to a roll under 10" do
          hero_types('hero/boost')

          expect(refused).to eq []
          expect(heard).to include('spends a Hero Point to add 10 to a check that rolled 1')
          expect(DiceTape.last_check(History.latest(encounter).dice, @hero.name)['faces']).to eq [ 11 ]
          expect(points).to eq 0
        end

        it "should take only one Hero Point" do
          gm_types('hero/award')
          hero_types('hero/reroll', FightBench::LOW)
          hero_types('hero/reroll', FightBench::HIGH)

          expect(refused).to eq [ t('pf2e.hero_already') ]
          expect(points).to eq 1
        end

        it "should be refused to someone with none to spend" do
          HeroPoints.write!(scene, @hero.id => 0)

          hero_types('hero/reroll', FightBench::HIGH)

          expect(refused).to eq [ t('pf2e.hero_none') ]
          expect(rat_damage).to eq 0
        end

        it "should be refused once the fight has moved on" do
          next_turn

          hero_types('hero/reroll', FightBench::HIGH)

          expect(refused).to eq [ t('pf2e.hero_no_check') ]
          expect(points).to eq 1
        end

        it "should be refused to someone whose check it was not" do
          as_friend('hero/reroll')

          expect(refused).to eq [ t('pf2e.hero_no_check') ]
        end
      end

      describe "adding 10" do
        before(:each) do
          add('giant rat')
          next_turn
          next_turn
        end

        it "should be refused to a roll of 10 or more, and cost nothing" do
          hero_types('e/strike #2=fist', FightBench::HITS)

          hero_types('hero/boost')

          expect(refused).to eq [ t('pf2e.hero_not_low', :die => 12) ]
          expect(points).to eq 1
        end
      end

      # Fire Scamp: Flame Breath, a basic Reflex save, which it cannot use again for 1d4 rounds.
      describe "spent on a save against what the GM did" do
        before(:each) do
          add('fire scamp')
          next_turn
          as(2, "act flame breath=#{@hero.name}", FightBench::LOW)
          @burned = Pf2eHP.get_max_hp(hero) - hero_hp
          @dice_before = History.latest(encounter).dice
        end

        it "should roll their save again and leave every other die as it fell" do
          hero_types('hero/reroll', FightBench::HIGH)

          expect(refused).to eq []
          now = History.latest(encounter).dice
          others = ->(tape) { tape.reject { |row| row['who'] == @hero.name }.map { |row| row['faces'] } }
          expect(others.call(now)).to eq others.call(@dice_before)
          expect(DiceTape.last_check(now, @hero.name)['faces']).to eq [ 19 ]
        end

        it "should have them take what the new result deals, in place of what the old one did" do
          expect(@burned).to be > 0

          hero_types('hero/reroll', FightBench::HIGH)

          expect(Pf2eHP.get_max_hp(hero) - hero_hp).to be < @burned
        end

        it "should be refused while its GM is working in another encounter, and cost nothing" do
          allow(Combatants).to receive(:encounter_here).and_call_original
          allow(Combatants).to receive(:encounter_here).with(satisfy { |who| who.name == @gm.name }).and_return(nil)

          hero_types('hero/reroll', FightBench::HIGH)

          expect(refused).to eq [ t('pf2e.hero_no_replay') ]
          expect(points).to eq 1
          expect(History.latest(encounter).dice).to eq @dice_before
        end

        it "should leave the change made when it was, so a roll made since is still their last" do
          made = Time.now - 3600
          History.latest(encounter).update(:created_at => made)

          hero_types('hero/reroll', FightBench::HIGH)

          expect(History.latest(encounter).created_at.to_i).to eq made.to_i
        end

        it "should leave what the GM took back after it there to put back, where it comes to nothing" do
          next_turn
          run(PF2EncounterUndoCmd, 'e/undo')
          entries = History.entries(encounter).map { |entry| [ entry.seq, entry.said ] }
          allow_any_instance_of(PF2EncounterAsCmd).to receive(:on_command)

          hero_types('hero/reroll', FightBench::HIGH)

          expect(refused).to eq [ t('pf2e.hero_no_replay') ]
          expect(points).to eq 1
          expect(History.entries(encounter).map { |entry| [ entry.seq, entry.said ] }).to eq entries
          expect(History.redo(encounter).ok?).to be true
        end

        it "should leave the creature's turn as one use of its breath" do
          used = TurnState.turn(npc)['actions'].to_i

          hero_types('hero/reroll', FightBench::HIGH)

          expect(TurnState.turn(npc)['actions'].to_i).to eq used
        end
      end

      describe "spent on a roll" do
        before(:each) do
          allow(Pf2e).to receive(:broadcast_roll) { |_room, message| @client.said << message.to_s }
          hero_types('roll 1d20+5', FightBench::LOW)
        end

        it "should roll it again" do
          hero_types('hero/reroll', FightBench::HIGH)

          expect(refused).to eq []
          expect(DiceTape.last_check(Character[@hero.id].pf2_last_check['dice'], @hero.name)).to include('faces' => [ 19 ], 'hero' => true)
          expect(points).to eq 0
        end

        it "should not be a roll made in another scene" do
          Character[@hero.id].update(:pf2_last_check => Character[@hero.id].pf2_last_check.merge('scene' => 'elsewhere'))

          hero_types('hero/reroll', FightBench::HIGH)

          expect(refused).to eq [ t('pf2e.hero_no_check') ]
        end
      end

      describe "not to die" do
        before(:each) do
          gm_types('hero/award')
          Pf2e.set_condition(hero, 'Wounded', 1)
          Pf2eHP.get_hp_obj(hero).update(:damage => Pf2eHP.get_max_hp(hero))
          Pf2e.set_condition(hero, 'Dying', 2)
        end

        it "should spend every one they hold, and leave them unconscious and no more wounded" do
          hero_types('hero/survive')

          expect(refused).to eq []
          expect(Pf2e.condition_level(hero, 'Dying')).to eq 0
          expect(Pf2e.condition_level(hero, 'Wounded')).to eq 1
          expect(held.keys).to include('Unconscious')
          expect(hero_hp).to eq 0
          expect(points).to eq 0
        end

        it "should be offered as their dying worsens" do
          # A 1 on the recovery check: dying two worse, which is death.
          @dice = FightBench::LOW
          told = Turns.recovery(hero).map { |one| t(one['key'], **CharState.symbolize(one['args'])) }.join

          expect(hero.pf2_is_dead).to be true
          expect(told).to include(t('pf2e.hero_would_save', :name => @hero.name, :count => 2))
        end

        it "should be offered to someone a blow leaves dying, and not to someone with none" do
          expect(HeroPoints.dying_hint(hero)).to eq('name' => @hero.name, 'count' => 2)

          HeroPoints.write!(scene, @hero.id => 0)

          expect(HeroPoints.dying_hint(hero)).to be_nil
        end

        it "should bring back someone the encounter killed" do
          Pf2eHP.kill(hero)

          hero_types('hero/survive')

          expect(hero.pf2_is_dead).to be_falsey
          expect(Pf2e.condition_level(hero, 'Dying')).to eq 0
        end

        it "should be something the GM can take back" do
          hero_types('hero/survive')
          run(PF2EncounterUndoCmd, 'e/undo')

          expect(Pf2e.condition_level(hero, 'Dying')).to eq 2
        end

        it "should be for someone in an encounter here, where dying happens" do
          Character[@hero.id].update(:pf2_is_dead => true)
          allow(Combatants).to receive(:encounter_here).and_return(nil)

          hero_types('hero/survive')

          expect(refused).to eq [ t('pf2e.hero_not_dying') ]
          expect(Character[@hero.id].pf2_is_dead).to be true
        end

        it "should be refused to someone who is not dying, or has none" do
          Pf2e.remove_condition(hero, 'Dying', true)
          hero_types('hero/survive')
          expect(refused).to eq [ t('pf2e.hero_not_dying') ]

          Pf2e.set_condition(hero, 'Dying', 1)
          HeroPoints.write!(scene, @hero.id => 0)
          hero_types('hero/survive')
          expect(refused).to eq [ t('pf2e.hero_none') ]
        end
      end

      describe "bought" do
        it "should cost 3 RPP, and tell the room" do
          expect(Player).to receive(:spend_rpp).with(anything, 3, 'Hero Point').and_return(nil)

          hero_types('hero/buy')

          expect(points).to eq 2
          expect(heard).to include('buys a Hero Point for 3 RPP')
        end

        it "should be refused where the RPP is not there" do
          allow(Player).to receive(:spend_rpp).and_return('Not enough RPP.')

          hero_types('hero/buy')

          expect(refused).to eq [ t('pf2e.hero_rpp_refused', :why => 'Not enough RPP.') ]
          expect(points).to eq 1
        end

        it "should be refused at three, and cost nothing" do
          HeroPoints.write!(scene, @hero.id => 3)
          expect(Player).to_not receive(:spend_rpp)

          hero_types('hero/buy')

          expect(refused).to eq [ t('pf2e.hero_at_most', :most => 3) ]
        end
      end

      describe "given" do
        it "should go to someone in the scene who has none" do
          HeroPoints.write!(scene, @friend.id => 0)

          hero_types("hero/give #{@friend.name}")

          expect([ points, points(@friend) ]).to eq [ 0, 1 ]
        end

        it "should be refused to someone who has one, and to whoever runs the scene" do
          hero_types("hero/give #{@friend.name}")
          expect(refused).to eq [ t('pf2e.hero_has_some', :name => @friend.name) ]

          hero_types("hero/give #{@gm.name}")
          expect(refused).to eq [ t('pf2e.hero_not_party', :name => @gm.name) ]
        end
      end
    end
  end
end
