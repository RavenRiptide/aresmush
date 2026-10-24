require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # A creature that changes shape fights as the shape it is in: a werewolf has its weapons and its jaws
    # and claws as a hybrid, its fist and weapons as a human, and only its jaws and claws as a wolf.
    describe "a creature's shapes", :dbtest => true do
      include FightBench

      before(:each) { bench! }
      after(:each) { clear_bench! }

      def strikes(number = 2)
        Npcs.strikes(Pf2eNpc[npc(number).id]).map { |one| one['name'] }
      end

      it "should offer the Strikes of the shape it is in" do
        add('werewolf')
        expect(strikes).to eq [ 'Battle Axe', 'Composite Shortbow', 'Claw', 'Jaws' ]

        RollOptions.set(npc, 'change-shape', 'animal')
        expect(strikes).to eq [ 'Claw', 'Jaws' ]

        RollOptions.set(Pf2eNpc[npc.id], 'change-shape', 'humanoid')
        expect(strikes).to eq [ 'Battle Axe', 'Composite Shortbow', 'Fist' ]
      end

      it "should start in the shape it is added in, and refuse a shape it has none of" do
        add('2 werewolf/animal')
        expect([ strikes(2), strikes(3) ]).to eq [ [ 'Claw', 'Jaws' ], [ 'Claw', 'Jaws' ] ]

        run(PF2EncounterAddCmd, 'e/add werewolf/dragon')
        expect(refused.join).to include('Werewolf', 'hybrid, humanoid, animal')
      end

      it "should change shape as an action of its turn, which undo takes back" do
        add('werewolf')
        turn_to(npc.name)

        as(2, 'act change shape/animal')

        expect(refused).to eq []
        expect(heard).to include('animal')
        expect(strikes).to eq [ 'Claw', 'Jaws' ]
        expect(TurnState.turn(Pf2eNpc[npc.id])['actions'].to_i).to eq 1

        run(PF2EncounterUndoCmd, 'e/undo')
        expect(strikes).to eq [ 'Battle Axe', 'Composite Shortbow', 'Claw', 'Jaws' ]
      end

      it "should show the GM the shape each is in, and no player" do
        add('werewolf/animal')

        run(PF2EncounterCreatureCmd, "e/creature #2")
        expect(heard).to include('Current Form: animal')

        gm = EncounterWeb.combatant(encounter, Combatants.find(encounter, '#2').state, Character[@gm.id], true)
        player = EncounterWeb.combatant(encounter, Combatants.find(encounter, '#2').state, Character[@hero.id], false)
        expect([ gm[:shapes], player[:shapes] ]).to eq [ [ 'Current Form: animal' ], nil ]
      end

      it "should start a saved creature in the shape it was saved to start in" do
        CreatureStore.create!(@gm, 'Moon Wolf', Bestiary.entry('Werewolf').merge('shape' => 'animal'))

        add('c:moon wolf')
        expect(strikes).to eq [ 'Claw', 'Jaws' ]
        Pf2eCreature.find(:name_slug => 'moon-wolf').to_a.each(&:delete)
      end

      it "should list each Strike's shape in its stat block" do
        run(PF2EncounterCreatureCmd, 'e/creature werewolf')

        expect(heard).to include('Melee Jaws +11 (unarmed), 1d8+8 piercing; not as humanoid')
        expect(heard).to include('Melee Battle Axe +11 (sweep), 1d8+8 slashing; not as animal')
        expect(heard).to include('Melee Fist +11 (unarmed), 1d4+8 bludgeoning; only as humanoid')
      end
    end
  end
end
