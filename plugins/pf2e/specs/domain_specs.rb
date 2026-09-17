require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a statistic answers to. An effect names a domain, so "a penalty to everything" is one row
    # rather than a line per statistic, and a skill added later is covered without touching the effect.
    describe Domains do

      it "should give a save its own name, its group and its attribute" do
        expect(Domains.for('save', 'Fortitude', 'Constitution'))
          .to include 'fortitude', 'saving-throw', 'con-based', 'all'
      end

      it "should give a skill the attribute-specific check group as well" do
        expect(Domains.for('skill', 'Athletics', 'Strength'))
          .to include 'athletics', 'skill-check', 'str-skill-check', 'str-based', 'all'
      end

      # A lore's name is the player's invention, so an effect reaches every lore through the group
      # rather than by naming any of them.
      it "should let an effect reach every lore at once" do
        expect(Domains.for('lore', 'Dragon Lore')).to include 'dragon-lore', 'lore-skill-check'
      end

      it "should slug a multi-word name" do
        expect(Domains.for('lore', 'Holy Order of Ea Lore')).to include 'holy-order-of-ea-lore'
      end

      # Every check and every DC takes a penalty written against `all`. Hit points and speed are
      # neither, and a Frightened character's hit points do not move.
      it "should put every check and DC in all" do
        %w{ac perception save skill lore class_dc spell_dc spell_attack attack}.each do |kind|
          expect(Domains.for(kind, 'Something', 'Wisdom')).to include('all'), kind
        end
      end

      it "should keep hit points and speed out of it" do
        expect(Domains.for('hp')).to_not include 'all'
        expect(Domains.for('speed')).to_not include 'all'
      end

      it "should omit the attribute domain when the statistic reads no attribute" do
        expect(Domains.for('ac').grep(/-based/)).to eq []
      end

      it "should refuse a kind of statistic it does not know rather than answer nothing" do
        expect { Domains.for('vibes') }.to raise_error(ArgumentError, /vibes/)
      end

      describe "matching an effect against a statistic" do
        it "should match when the selector names one of the domains" do
          expect(Domains.matches?('all', Domains.for('save', 'Will', 'Wisdom'))).to be true
        end

        it "should match when a selector naming several hits one" do
          expect(Domains.matches?([ 'hp', 'fortitude' ], Domains.for('save', 'Fortitude', 'Constitution')))
            .to be true
        end

        it "should not match a domain the statistic does not have" do
          expect(Domains.matches?('dex-based', Domains.for('save', 'Fortitude', 'Constitution')))
            .to be false
        end

        it "should read a selector written the way a person would write it" do
          expect(Domains.matches?('Saving Throw', Domains.for('save', 'Will', 'Wisdom'))).to be true
        end
      end
    end
  end
end
