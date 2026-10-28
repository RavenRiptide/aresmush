require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # The pointer at the foot of 'magic' to the command that lists a character's spells. A
    # Cleric or Druid prepares from the whole tradition list and keeps no spellbook, so they
    # get no pointer to one.
    describe PF2MagicDisplayTemplate do

      def help_for(*charclasses)
        magic = double('magic', :tradition => charclasses.to_h { |cc| [ cc, [ 'arcane', 'trained' ] ] })

        PF2MagicDisplayTemplate.new(double('char'), magic, double('client')).help_text
      end

      it "should point a Wizard at their spellbook" do
        expect(help_for('Wizard')).to eq t('pf2emagic.spellbook_help')
      end

      it "should point a Sorcerer at their repertoire" do
        expect(help_for('Sorcerer')).to eq t('pf2emagic.repertoire_help')
      end

      it "should not point a Cleric or Druid at a spellbook" do
        expect(help_for('Cleric')).to eq ''
        expect(help_for('Druid')).to eq ''
      end

      it "should point a Cleric with the Wizard archetype at the archetype's spellbook" do
        expect(help_for('Cleric', 'Wizard Archetype')).to eq t('pf2emagic.spellbook_help')
      end

      it "should point a Cleric with the Sorcerer archetype at the repertoire alone" do
        expect(help_for('Cleric', 'Sorcerer Archetype')).to eq t('pf2emagic.repertoire_help')
      end

      it "should ignore innate spells" do
        expect(help_for('innate')).to eq ''
      end
    end
  end
end
