require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # `prepared` lists every rank a class has slots at, so a caster sees how many slots they have
    # before they fill them, and the spells in each rank they have filled.
    describe PF2DisplayPreparedSpellsTemplate do

      # `font` is { rank => count } of divine font slots, which take only Heal.
      def spells_for(slots, prepared, font: {}, split_slots: {})
        magic = double('magic')
        char = double('char', :name => 'Tester', :magic => magic)

        allow(Entries).to receive(:slots_by_source).with(magic).and_return(slots)
        allow(Restrictions).to receive(:at) do |_char, _charclass, level|
          font[level.to_s] ? { 'divine font' => { 'count' => font[level.to_s], 'eligible' => [ 'Heal' ] } } : {}
        end
        allow(Pf2emagic).to receive(:restricted_slots_at) do |_char, _charclass, level|
          font[level.to_s] ? { 'divine font' => font[level.to_s] } : {}
        end
        allow(SlotFeats).to receive(:placeholders) do |_magic, _charclass, level|
          Array.new(split_slots[level.to_s].to_i, SlotFeats::PLACEHOLDER)
        end
        allow(SlotFeats).to receive(:pairs).and_return([])
        allow(SlotFeats).to receive(:mastered).and_return({})

        template = PF2DisplayPreparedSpellsTemplate.new(char, prepared, double('client', :screen_reader => true))
        allow(template).to receive(:item_color).and_return('')

        template.spells.join
      end

      it "should show every rank's slots when nothing is prepared" do
        shown = spells_for({ 'Cleric' => { 'cantrip' => 5, '1' => 2 } }, { 'Cleric' => {} })

        expect(shown).to include 'Cantrip (5 slots)'
        expect(shown).to include '1st-rank (2 slots)'
        expect(shown.scan(t('pf2emagic.prepared_rank_empty')).size).to eq 2
      end

      it "should show an empty rank beside one with spells prepared" do
        shown = spells_for({ 'Cleric' => { 'cantrip' => 5, '1' => 3, '2' => 2 } },
                           { 'Cleric' => { '1' => [ 'Bless', 'Heal' ] } })

        expect(shown).to include "1st-rank (3 slots)%xn%r%b%b%b%bBless, Heal"
        expect(shown).to include "2nd-rank (2 slots)%xn%r%b%b%b%b#{t('pf2emagic.prepared_rank_empty')}"
        expect(shown).to include "Bless, Heal%r2nd-rank"
        expect(shown.index('Cantrip')).to be < shown.index('1st-rank')
        expect(shown.index('1st-rank')).to be < shown.index('2nd-rank')
      end

      it "should list a rank once whatever case its key is in" do
        shown = spells_for({ 'Wizard' => { 'Cantrip' => 5, '1' => 2 } },
                           { 'Wizard' => { 'cantrip' => [ 'Light' ] } })

        expect(shown.scan('Cantrip (').size).to eq 1
        expect(shown).to include 'Light'
      end

      it "should show a Wizard's slots at ranks with nothing prepared" do
        shown = spells_for({ 'Wizard' => { 'cantrip' => 5, '1' => 2, '2' => 1 } },
                           { 'Wizard' => { '1' => [ 'Fear' ] } })

        expect(shown).to include '2nd-rank (1 slot)'
      end

      it "should leave out a rank with no slots and nothing prepared" do
        shown = spells_for({ 'Cleric' => { '1' => 2, '2' => 0 } }, { 'Cleric' => {} })

        expect(shown).not_to include '2nd-rank'
      end

      # A Cleric's font slots take only their font spell, so they're shown apart from the rest, with
      # how many are filled: otherwise a Cleric can't tell whether they've filled them.
      describe "divine font slots" do
        it "should show the font slots empty before anything is prepared" do
          shown = spells_for({ 'Cleric' => { '1' => 2 } }, { 'Cleric' => {} }, font: { '1' => 4 })

          expect(shown).to include '1st-rank (2 slots + 4 divine font slots)'
          expect(shown).to include "Any spell (0 of 2): #{t('pf2emagic.prepared_rank_empty')}"
          expect(shown).to include "Divine font (0 of 4): #{t('pf2emagic.prepared_rank_empty')}"
        end

        it "should put Heal in the font slots before the others" do
          shown = spells_for({ 'Cleric' => { '1' => 2 } }, { 'Cleric' => { '1' => %w(Heal Bless Heal) } },
                             font: { '1' => 4 })

          expect(shown).to include 'Any spell (1 of 2): Bless'
          expect(shown).to include 'Divine font (2 of 4): Heal, Heal'
        end

        it "should put Heal in the other slots once the font slots are full" do
          shown = spells_for({ 'Cleric' => { '1' => 2 } }, { 'Cleric' => { '1' => %w(Heal Heal) } },
                             font: { '1' => 1 })

          expect(shown).to include 'Any spell (1 of 2): Heal'
          expect(shown).to include 'Divine font (1 of 1): Heal'
        end

        it "should leave a rank without font slots as one line" do
          shown = spells_for({ 'Cleric' => { '1' => 3, '2' => 2 } }, { 'Cleric' => { '1' => %w(Bless) } },
                             font: { '2' => 4 })

          expect(shown).to include "1st-rank (3 slots)%xn%r%b%b%b%bBless%r"
          expect(shown).not_to include 'Any spell (1 of 3)'
        end

        # After the font changes, Harm prepared yesterday no longer fits; show what they have rather than drop it.
        it "should list a set that no longer fits as one line" do
          shown = spells_for({ 'Cleric' => { '1' => 1 } }, { 'Cleric' => { '1' => %w(Harm Harm) } },
                             font: { '1' => 4 })

          expect(shown).to include "%b%b%b%bHarm, Harm"
          expect(shown).not_to include 'Divine font ('
        end

        it "should count a Split Slot pair against the other slots without listing it there" do
          shown = spells_for({ 'Cleric' => { '1' => 2 } }, { 'Cleric' => { '1' => %w(Bless) } },
                             font: { '1' => 4 }, split_slots: { '1' => 1 })

          expect(shown).to include 'Any spell (2 of 2): Bless%r'
          expect(shown).not_to include SlotFeats::PLACEHOLDER
        end
      end
    end
  end
end
