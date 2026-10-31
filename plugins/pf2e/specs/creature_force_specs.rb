require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A creature does what its stat block gives it: the actions anyone may use, its own abilities, and the
    # spells it lists. In a playtest a creature with no spells cast Force Barrage, and one cast Rage, because
    # nothing asked. The GM improvising says `/force`.
    describe "what a creature may do" do

      def creature(block = {})
        Pf2eNpc.new(:described => { 'name' => 'Barrow Hound', 'level' => 3 }.merge(block))
      end

      def caster
        creature('spellcasting' => [ { 'name' => 'Arcane Innate Spells', 'dc' => 20, 'attack' => 12,
                                        'spells' => { '0' => [ 'Ignition' ], '1' => [ 'Charm (At Will)' ] } } ])
      end

      def scene(holder, gm: true)
        allow(Combatants).to receive(:gm?).and_return(gm)

        Acting::Scene.new(double('encounter'), double('combatant', :holder => holder, :label => 'Barrow Hound #3'),
                          double('target', :label => 'Aria', :holder => Object.new), double('enactor'), gm)
      end

      describe "the spells it lists" do
        it "should find a spell it lists, without the notes after its name" do
          expect(Npcs.lists_spell?(caster, 'Ignition')).to be true
          expect(Npcs.lists_spell?(caster, 'charm')).to be true
        end

        it "should not find one it does not list, nor any for a creature with no spells" do
          expect(Npcs.lists_spell?(caster, 'Force Barrage')).to be false
          expect(Npcs.lists_spell?(creature, 'Force Barrage')).to be false
        end
      end

      describe "casting" do
        it "should cast a spell it lists" do
          expect(Acting.unlisted_spell(scene(caster), 'Ignition', [])).to be_nil
        end

        it "should refuse one it does not list" do
          refused = Acting.unlisted_spell(scene(creature), 'Force Barrage', [])

          expect(refused.key).to eq 'pf2e.cast_not_listed'
          expect(refused.args['actor']).to eq 'Barrow Hound #3'
        end

        it "should cast one it does not list where the GM forces it" do
          expect(Acting.unlisted_spell(scene(creature), 'Force Barrage', [ 'force' ])).to be_nil
        end

        it "should not let anyone but the GM force it" do
          expect(Acting.unlisted_spell(scene(creature, :gm => false), 'Force Barrage', [ 'force' ])).to be_an(Err)
        end

        it "should leave a character's spells to their magic" do
          expect(Acting.unlisted_spell(scene(double('character')), 'Force Barrage', [])).to be_nil
        end

        it "should not take force for a circumstance" do
          said = Acting.said([ 'force' ], false)

          expect(said['force']).to be true
          expect(said['words']).to eq []
          expect(said['options']).to eq []
        end

        # Forced, a creature with no spell attack had nothing to roll it with, and raised.
        it "should have the GM roll a spell attack it has no bonus for" do
          out = Acting.report

          Acting.spell_attack(scene(creature), 'Ignition', {}, nil, [ [ '2d4', 'fire', nil ] ], Acting.said([], true), out)

          expect(Telling.lines(out['lines']).join).to include('GM rolls the spell attack against Aria')
        end
      end

      describe "actions" do
        before(:each) do
          allow(Actions).to receive(:info) { |name| name == 'Trip' ? { 'for' => 'everyone' } : { 'for' => 'class' } }
          allow(Actions).to receive(:find) { |term| Ok.new(:state => term.split.map(&:capitalize).join(' ')) }
        end

        it "should use an action anyone may" do
          expect(Acting.action_named(scene(creature), 'trip')).to eq 'Trip'
        end

        it "should use its own ability, which no catalogue gives it" do
          hound = creature('actions' => [ { 'name' => 'Rage', 'type' => 'action', 'cost' => 1, 'text' => 'It rages.' } ])

          expect(Acting.action_named(scene(hound), 'rage')).to eq 'Rage'
        end

        it "should refuse an action its stat block does not give it" do
          refused = Acting.action_named(scene(creature), 'rage')

          expect(refused.key).to eq 'pf2e.action_not_creatures'
          expect(refused.args['action']).to eq 'Rage'
        end

        it "should use it where the GM forces it" do
          expect(Acting.action_named(scene(creature), 'rage', [ 'force' ])).to eq 'Rage'
        end

        it "should not let anyone but the GM force it" do
          expect(Acting.action_named(scene(creature, :gm => false), 'rage', [ 'force' ])).to be_an(Err)
        end
      end
    end
  end
end
