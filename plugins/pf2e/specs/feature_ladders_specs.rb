require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The main sheet names only the highest step of a class feature progression it holds.
    describe FeatureLadders do

      def collapse(*names)
        FeatureLadders.collapse(names)
      end

      it "should keep the highest of Expert, Master and Legendary" do
        expect(collapse('Expert Spellcaster', 'Master Spellcaster', 'Legendary Spellcaster')).to eq [ 'Legendary Spellcaster' ]
      end

      it "should keep the highest of Expertise, Mastery and Legend" do
        expect(collapse('Perception Expertise', 'Perception Mastery')).to eq [ 'Perception Mastery' ]
        expect(collapse('Light Armor Expertise', 'Light Armor Mastery')).to eq [ 'Light Armor Mastery' ]
      end

      it "should keep a Greater feature over the bare one" do
        expect(collapse('Juggernaut', 'Greater Juggernaut')).to eq [ 'Greater Juggernaut' ]
        expect(collapse('Weapon Specialization', 'Greater Weapon Specialization')).to eq [ 'Greater Weapon Specialization' ]
      end

      it "should keep the highest curse" do
        expect(collapse('Major Curse', 'Extreme Curse')).to eq [ 'Extreme Curse' ]
      end

      it "should leave a step whose later steps aren't held" do
        expect(collapse('Expert Spellcaster', 'Weapon Expertise')).to eq [ 'Expert Spellcaster', 'Weapon Expertise' ]
      end

      # A monk's Expert Strikes and a rogue's Master Strike aren't one progression.
      it "should need the rest of the name to match exactly" do
        expect(collapse('Expert Strikes', 'Master Strike')).to eq [ 'Expert Strikes', 'Master Strike' ]
      end

      # Weapon Expertise's later steps belong to Weapon, not to Light Armor.
      it "should not collapse across different progressions" do
        expect(collapse('Weapon Expertise', 'Light Armor Mastery')).to eq [ 'Weapon Expertise', 'Light Armor Mastery' ]
      end

      it "should keep the order it was given" do
        expect(collapse('Rage', 'Juggernaut', 'Bravery', 'Greater Juggernaut')).to eq [ 'Rage', 'Bravery', 'Greater Juggernaut' ]
      end
    end
  end
end
