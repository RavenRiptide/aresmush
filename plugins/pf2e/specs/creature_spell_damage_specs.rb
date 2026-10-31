require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # In a playtest, weak creatures' spells did nothing: a weak caster's Force Barrage was one shard of 1d4-3,
    # which nearly always fell to 0, and a spell DC left blank in the web editor was kept as 0.
    describe "what a creature's spells deal" do

      before(:each) do
        allow(Pf2e).to receive(:roll_dice) { |count, _sides| [ 1 ] * count.to_i }
      end

      def creature(block = {}, adjustment = nil)
        Pf2eNpc.new(:described => { 'name' => 'Barrow Hound', 'level' => 9 }.merge(block), :adjustment => adjustment)
      end

      describe "the least a hit deals" do
        it "should deal 1 where a creature's or a spell's penalties take its dice below it" do
          expect(DamageRoll.of_formulas([ [ '1d4-5', 'force', nil ] ], false).first['amount']).to eq 1
        end

        it "should deal 1 where a character's penalties take their weapon's dice below it" do
          instance = { 'dice' => [ [ 1, 'd4' ] ], 'modifier' => -5, 'damage_type' => 'bludgeoning' }

          expect(DamageRoll.of_instances([ instance ], false).first['amount']).to eq 1
        end

        it "should leave a flat amount that rolls no dice at what it is" do
          expect(DamageRoll.of_formulas([ [ '0', 'force', nil ] ], false).first['amount']).to eq 0
        end
      end

      describe "Force Barrage" do
        def shards(words, rank = 1)
          _name, base = Acting.spell_mechanics('Force Barrage')

          Acting.spell_damage(Acting.variant(base, Acting.said(words, false)), rank).map(&:first)
        end

        it "should fire a shard for each action it is cast with" do
          expect(shards([])).to eq [ '1d4+1' ]
          expect(shards([ 'actions 2' ])).to eq [ '2d4+2' ]
          expect(shards([ 'actions 3' ])).to eq [ '3d4+3' ]
        end

        it "should fire one more shard for each action at every second rank" do
          expect(shards([ 'actions 3' ], 3)).to eq [ '6d4+6' ]
          expect(shards([], 5)).to eq [ '3d4+3' ]
        end

        it "should spend the actions it is cast with" do
          _name, base = Acting.spell_mechanics('Force Barrage')

          expect(Acting.variant(base, Acting.said([ 'actions 3' ], false))['time']).to eq '3'
        end

        # Monster Core: a weak creature's spells, which it cannot cast every round, deal 4 less - once, on
        # all the shards together.
        it "should take a weak caster's 4 once off all its shards" do
          weak = creature({}, 'weak')

          expect(Adjustments.spell_damage(weak, { 'rank' => 1 }, [ [ '3d4+3', 'force', nil ] ]).map(&:first)).to eq [ '3d4-1' ]
        end
      end

      describe "a spell DC or attack left blank" do
        it "should be kept as none, not 0" do
          kept = CreatureBlock.casting('name' => 'Arcane Innate Spells', 'dc' => '', 'attack' => ' ', 'spells' => {})

          expect(kept['dc']).to be_nil
          expect(kept['attack']).to be_nil
        end

        it "should keep one written as a number" do
          expect(CreatureBlock.casting('dc' => '20', 'attack' => 12, 'spells' => {}).values_at('dc', 'attack')).to eq [ 20, 12 ]
        end

        # Creatures saved before kept the blank as 0, which no stat block has.
        it "should read a 0 kept before as none, for the GM to set" do
          expect(Npcs.stat(creature, 'spell_dc', { 'dc' => 0, 'attack' => 0 })).to be_nil
          expect(Npcs.stat(creature, 'spell_attack', { 'dc' => 0, 'attack' => 0 })).to be_nil
        end

        it "should warn of spells with no DC, and offer the level's moderate one" do
          block = { 'level' => 3, 'spellcasting' => [ { 'name' => 'Arcane Innate Spells', 'tradition' => 'arcane', 'type' => 'innate',
                                                        'dc' => nil, 'spells' => {} } ] }
          warned = CreatureCheck.warnings(block).find { |one| one['code'] == :creature_casting }

          expect(warned['args']['casting']).to eq 'Arcane Innate Spells'
          expect(warned['args']['what']).to include('level 3', CreatureBenchmarks.figure_at('spell', 3, 'moderate_dc').to_s)
          expect(CreatureCheck.errors(block).map { |one| one['code'] }).to_not include(:creature_casting)
        end

        it "should show only the figures it has" do
          block = { 'name' => 'Barrow Hound', 'level' => 3, 'spellcasting' => [ { 'name' => 'Arcane Innate Spells', 'dc' => 20, 'attack' => nil,
                                                                                    'spells' => { '1' => [ 'Fear' ] } } ] }

          expect(StatBlock.lines('Barrow Hound', block).join("\n")).to include('Arcane Innate Spells DC 20; ')
        end
      end

      describe "the rank of a spell its stat block does not list" do
        def rank(holder, spell, words = [])
          name, mechanics = Acting.spell_mechanics(spell)

          Acting.spell_rank(holder, name, mechanics, Acting.said(words, true), nil)
        end

        it "should be a creature's highest, half its level rounded up" do
          expect(rank(creature, 'Fireball')).to eq 5
        end

        it "should never be below the spell's own" do
          expect(rank(creature('level' => 1), 'Fireball')).to eq 3
        end

        it "should be the rank the GM says" do
          expect(rank(creature, 'Fireball', [ 'rank 4' ])).to eq 4
        end

        it "should stay the one its stat block lists it at" do
          listed = creature('spellcasting' => [ { 'name' => 'Arcane Innate Spells', 'dc' => 28, 'attack' => 20,
                                                  'spells' => { '3' => [ 'Fireball' ] } } ])

          expect(rank(listed, 'Fireball')).to eq 3
        end

        it "should leave a character's at the spell's own" do
          expect(rank(double('character', :pf2_level => 9), 'Fireball')).to eq 3
        end
      end
    end
  end
end
