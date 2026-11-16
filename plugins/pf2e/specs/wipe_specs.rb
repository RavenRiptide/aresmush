require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # `condition/wipe` clears every condition set on a combatant, and `effect/wipe` ends every effect on
    # one. What something else still brings stays until that ends, and death is not a condition.
    describe "wiping conditions and effects", :dbtest => true do
      include FightBench

      before(:each) { bench! }

      after(:each) { clear_bench! }

      describe "condition/wipe" do
        before(:each) do
          run(PF2ConditionSetCmd, "condition/set #{@hero.name}=dying/1")
          run(PF2ConditionSetCmd, "condition/set #{@hero.name}=frightened/2")
          PersistentDamage.add(hero, '1d6', 'fire')
          @client.said.clear
        end

        it "should clear them all, held in place or not, and the persistent damage with them" do
          expect(held.keys).to include('Dying', 'Unconscious', 'Frightened', 'Persistent')

          run(PF2ConditionWipeCmd, "condition/wipe #{@hero.name}")

          expect(refused).to eq []
          expect(held).to eq({})
          expect(PersistentDamage.held(hero)).to eq []
          expect(heard).to include(t('pf2e.conditions_wiped', :targets => @hero.name))
        end

        it "should be taken back by encounter/undo" do
          run(PF2ConditionWipeCmd, "condition/wipe #{@hero.name}")
          run(PF2EncounterUndoCmd, 'e/undo')

          expect(held.keys).to include('Dying', 'Frightened')
          expect(PersistentDamage.held(hero)).to_not eq []
        end

        it "should say so where there is nothing to clear" do
          run(PF2ConditionWipeCmd, "condition/wipe #{@hero.name}")
          @client.failures.clear
          run(PF2ConditionWipeCmd, "condition/wipe #{@hero.name}")

          expect(refused).to eq [ t('pf2e.conditions_none', :name => @hero.name) ]
        end
      end

      it "should leave a condition a creature has for good, and tell its GM why" do
        add('zombie shambler')
        run(PF2ConditionSetCmd, 'condition/set #2=frightened/1')
        @client.said.clear

        run(PF2ConditionWipeCmd, 'condition/wipe #2')

        expect(Pf2e.condition_level(npc, 'Frightened')).to eq 0
        expect(Pf2e.condition_level(npc, 'Slowed')).to eq 1
        expect(heard).to include(t('pf2e.condition_kept', :condition => 'Slowed', :target => 'Zombie Shambler #2', :from => 'Slow'))
      end

      it "should leave the dead dead" do
        run(PF2ConditionSetCmd, "condition/set #{@hero.name}=dead")
        run(PF2ConditionWipeCmd, "condition/wipe #{@hero.name}")

        expect(Pf2e.dead?(hero)).to be true
      end

      describe "effect/wipe" do
        before(:each) do
          ActiveEffects.apply(hero, 'Effect: Rage', :encounter => encounter)
          ActiveEffects.apply(hero, 'Spell Effect: Light', :applied_by => @hero.name, :encounter => encounter)
          @client.said.clear
        end

        it "should end every effect, and what each brought with it" do
          expect(Pf2eHP.get_hp_obj(hero).temp_hp.to_i).to be > 0

          run(PF2EffectWipeCmd, "effect/wipe #{@hero.name}")

          expect(refused).to eq []
          expect(ActiveEffects.on(hero)).to eq []
          expect(Pf2eHP.get_hp_obj(hero).temp_hp.to_i).to eq 0
          expect(heard).to include(t('pf2e.effects_wiped', :targets => @hero.name))
        end

        it "should leave conditions set on them alone" do
          run(PF2ConditionSetCmd, "condition/set #{@hero.name}=frightened/1")
          run(PF2EffectWipeCmd, "effect/wipe #{@hero.name}")

          expect(held).to have_key('Frightened')
        end

        it "should be taken back by encounter/undo" do
          run(PF2EffectWipeCmd, "effect/wipe #{@hero.name}")
          run(PF2EncounterUndoCmd, 'e/undo')

          expect(ActiveEffects.on(hero).map(&:name)).to contain_exactly('Effect: Rage', 'Spell Effect: Light')
        end

        it "should say so where there is nothing to end" do
          run(PF2EffectWipeCmd, "effect/wipe #{@hero.name}")
          run(PF2EffectWipeCmd, "effect/wipe #{@hero.name}")

          expect(refused).to eq [ t('pf2e.effects_none', :name => @hero.name) ]
        end
      end
    end
  end
end
