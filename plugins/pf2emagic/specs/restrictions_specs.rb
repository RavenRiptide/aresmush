require "plugin_test_loader"
require_relative "support/magic_stub"

module AresMUSH
  module Pf2emagic

    # Which of a caster's slots at one rank are restricted, and to what.
    #
    # Each kind of restriction is a row: how many slots it grants at a rank, and which spells may go
    # in them. Adding a kind is adding a row.
    describe Restrictions do
      include MagicStub

      def stats(restricted = {})
        magic_stub(:restricted_slots => { 'Wizard' => restricted, 'Cleric' => {} },
                   :tradition => { 'Wizard' => [ 'arcane', 'trained' ], 'Cleric' => [ 'divine', 'trained' ] },
                   :spells_per_day => { 'Wizard' => { 'cantrip' => 5, '1' => 3, '2' => 2 },
                                        'Cleric' => { 'cantrip' => 5, '1' => 2 } })
      end

      def char_for(magic, specialize = 'Battle Magic')
        double(:magic => magic,
               :pf2_base_info => { 'specialize' => specialize },
               :name => 'Someone')
      end

      describe "a curriculum" do
        before(:each) do
          allow(Pf2emagic).to receive(:curriculum_spells).and_return([ 'Fireball' ])
        end

        it "should grant the slots the stat block says" do
          char = char_for(stats('curriculum' => { '2' => 1 }))

          expect(Restrictions.at(char, 'Wizard', '2')['curriculum']['count']).to eq 1
        end

        it "should grant nothing at a rank the stat block does not mention" do
          char = char_for(stats('curriculum' => { '2' => 1 }))

          expect(Restrictions.at(char, 'Wizard', '1')).to eq({})
        end

        it "should take its eligible spells from the curriculum" do
          char = char_for(stats('curriculum' => { '2' => 1 }))

          expect(Restrictions.at(char, 'Wizard', '2')['curriculum']['eligible']).to eq [ 'Fireball' ]
        end
      end

      # PF2e: "You gain 4 additional spell slots each day at your highest rank of cleric spell
      # slots", rising to 5 at 5th level and 6 at 15th, and they must hold the font's own spell.
      describe "a divine font" do
        def cleric(font = 'heal', level: 3, slots: { 'cantrip' => 5, '1' => 3, '2' => 2 })
          magic = magic_stub(:restricted_slots => { 'Cleric' => {} },
                             :tradition => { 'Cleric' => [ 'divine', 'trained' ] },
                             :spells_per_day => { 'Cleric' => slots },
                             :divine_font => font)

          double(:magic => magic, :pf2_base_info => {}, :pf2_level => level, :name => 'Someone')
        end

        it "should grant four slots at the cleric's highest rank" do
          expect(Restrictions.at(cleric, 'Cleric', '2')['divine font']['count']).to eq 4
        end

        it "should grant nothing at a lower rank, even one with slots" do
          expect(Restrictions.at(cleric, 'Cleric', '1')).to eq({})
        end

        it "should grant five from 5th level and six from 15th" do
          expect(Restrictions.at(cleric(level: 4), 'Cleric', '2')['divine font']['count']).to eq 4
          expect(Restrictions.at(cleric(level: 5), 'Cleric', '2')['divine font']['count']).to eq 5
          expect(Restrictions.at(cleric(level: 14), 'Cleric', '2')['divine font']['count']).to eq 5
          expect(Restrictions.at(cleric(level: 15), 'Cleric', '2')['divine font']['count']).to eq 6
        end

        # Miraculous Spell's 10th-rank slot is a rank of its own; the font stays at 9th.
        it "should not follow the cleric to the 10th rank" do
          slots = (1..9).each_with_object({ 'cantrip' => 5 }) { |rank, all| all[rank.to_s] = 3 }.merge('10' => 1)
          capstone = cleric(level: 19, slots: slots)

          expect(Restrictions.at(capstone, 'Cleric', '9')['divine font']['count']).to eq 6
          expect(Restrictions.at(capstone, 'Cleric', '10')).to eq({})
        end

        it "should only take the font's own spell" do
          expect(Restrictions.at(cleric, 'Cleric', '2')['divine font']['eligible']).to eq [ 'Heal' ]
          expect(Restrictions.at(cleric('harm'), 'Cleric', '2')['divine font']['eligible']).to eq [ 'Harm' ]
        end

        it "should grant no cantrip slot" do
          expect(Restrictions.at(cleric, 'Cleric', 'cantrip')).to eq({})
        end

        it "should grant nothing at a rank with no slots" do
          expect(Restrictions.at(cleric, 'Cleric', '4')).to eq({})
        end

        it "should grant nothing with no font chosen" do
          expect(Restrictions.at(cleric(nil), 'Cleric', '2')).to eq({})
        end

        it "should grant nothing to a class that has no font" do
          char = char_for(stats)

          expect(Restrictions.at(char, 'Wizard', '1')).to eq({})
        end
      end

      describe :counts_at do
        it "should give just the counts, for callers that only size the pools" do
          allow(Pf2emagic).to receive(:curriculum_spells).and_return([ 'Fireball' ])
          char = char_for(stats('curriculum' => { '2' => 1 }))

          expect(Restrictions.counts_at(char, 'Wizard', '2')).to eq('curriculum' => 1)
        end
      end

      describe "an unknown restriction" do
        it "should grant its slots but restrict them to nothing, rather than to anything" do
          char = char_for(stats('moon phase' => { '1' => 1 }))

          restriction = Restrictions.at(char, 'Wizard', '1')['moon phase']

          expect(restriction['count']).to eq 1
          expect(restriction['eligible']).to eq []
        end
      end
    end
  end
end
