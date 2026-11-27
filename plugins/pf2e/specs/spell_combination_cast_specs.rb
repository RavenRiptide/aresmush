require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Spell Combination (Wizard 20) in an encounter: the two spells in a combination slot are cast as one
    # spell at one target. One spell attack or one save decides both, each applies its own outcome at that
    # degree, and their damage is dealt together.
    describe "casting a combined spell in an encounter", :dbtest => true do
      include FightBench

      before(:each) do
        bench!(level: 20, hp: 300)
        add('goblin warrior')

        per_day = (1..9).to_h { |rank| [ rank.to_s, 1 ] }
        @magic = PF2Magic.create(:character => @hero,
                                 :tradition => { 'Wizard' => [ 'arcane', 'trained' ] },
                                 :spell_abil => { 'Wizard' => 'Intelligence' },
                                 :spells_per_day => { 'Wizard' => per_day },
                                 :spellbook => { 'Wizard' => { '1' => [ 'Hydraulic Push' ], '3' => [ 'Blindness', 'Slow' ],
                                                               '6' => [ 'Disintegrate' ] } },
                                 :spells_prepared => { 'Wizard' => {} })
        @hero.update(:magic => @magic, :pf2_base_info => { 'charclass' => 'Wizard' },
                     :pf2_feats => { 'charclass' => [ 'Spell Combination' ] })
      end

      after(:each) do
        @magic&.delete
        clear_bench!
      end

      def combine(*spells, rank: 5)
        char = Character[@hero.id]
        prepared = Pf2emagic::SlotFeats.prepare_pair(char, Pf2emagic::SlotFeats.for_switch(char, 'spellcombination'), rank, spells)
        expect(prepared).to be_ok

        run(PF2EncounterRestCmd, 'e/rest')
        turn_to(@hero.name)
      end

      def goblins
        Combatants.all(encounter).reject { |one| one.label == @hero.name }
      end

      def goblin
        found = goblins.first
        found.holder.class[found.holder.id]
      end

      def combinations_left
        Array((hero.magic.spells_today[Pf2emagic::SlotFeats::TODAY] || {})['Wizard'])
      end

      describe "two spells against the same save" do
        before(:each) { combine('Blindness', 'Slow') }

        it "should roll one save, and apply both spells' critical failure" do
          hero_types("e/cast Slow=##{goblins.first.number}", FightBench::LOW)

          expect(refused).to eq []
          expect(heard).to include 'casts Blindness + Slow at rank 3'
          expect(heard.scan('rolls Fortitude').size).to eq 1
          expect(goblin.pf2_conditions).to have_key('Blinded')
          expect(goblin.pf2_conditions['Slowed']['value'].to_i).to eq 2
        end

        it "should tell the shorter range, spend the slot, and cost two actions once" do
          used = TurnState.turn(hero)['actions'].to_i

          hero_types("e/cast Blindness=##{goblins.first.number}", FightBench::LOW)

          expect(heard).to include 'range is 30 feet'
          expect(combinations_left).to eq []
          expect(TurnState.turn(hero)['actions'].to_i).to eq used + 2
        end

        it "should refuse more than one target, spending nothing" do
          add('goblin warrior')

          hero_types("e/cast Slow=#{goblins.map { |one| "##{one.number}" }.join(',')}")

          expect(refused.join).to include 'one target'
          expect(combinations_left.size).to eq 1
        end

        it "should refuse no target, spending nothing" do
          hero_types('e/cast Slow')

          expect(refused.join).to include 'one target'
          expect(combinations_left.size).to eq 1
        end

        it "should be taken back as one cast" do
          before = History.entries(encounter).size

          hero_types("e/cast Slow=##{goblins.first.number}", FightBench::LOW)

          expect(History.entries(encounter).size).to eq before + 1

          History.undo(encounter)

          expect(goblin.pf2_conditions || {}).to_not have_key('Slowed')
          expect(combinations_left.size).to eq 1
        end
      end

      describe "two spell attacks" do
        before(:each) { combine('Hydraulic Push', 'Disintegrate', :rank => 8) }

        it "should roll one attack, double both spells' damage on a critical hit, and deal it in one line" do
          hero_types("e/cast Hydraulic Push=##{goblins.first.number}", FightBench::HIGH)

          expect(refused).to eq []
          expect(heard.scan('strikes').size).to eq 1
          expect(heard.scan('Damage to').size).to eq 1
          # Rank 6: Hydraulic Push 13d6 and Disintegrate 12d10, every die at its highest, then doubled.
          expect(heard).to include '156 bludgeoning', '240 untyped'
        end

        it "should count as an attack for the multiple attack penalty" do
          hero_types("e/cast Hydraulic Push=##{goblins.first.number}", FightBench::HIGH)

          expect(TurnState.turn(hero)['attacks'].to_i).to eq 1
        end
      end
    end
  end
end
