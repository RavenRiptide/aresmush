require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The traditions a character casts as: what Adapted Cantrip chooses away from, and what the
    # `caster` prerequisite asks for. A class whose tradition is only there for its focus spells does
    # not count; a dedication that grants spellcasting does, at its bloodline's tradition.
    describe "own traditions" do

      def ranger_entry
        { 'name' => 'Ranger', 'source_type' => 'class', 'category' => nil, 'tradition' => 'primal', 'proficiency' => 'trained' }
      end

      def sorcerer_archetype(tradition)
        { 'name' => 'Sorcerer Archetype', 'source_type' => 'archetype', 'category' => 'spontaneous',
          'tradition' => tradition, 'proficiency' => 'trained' }
      end

      def druid_entry
        { 'name' => 'Druid', 'source_type' => 'class', 'category' => 'prepared', 'tradition' => 'primal', 'proficiency' => 'trained' }
      end

      def someone(entries, innate: [])
        magic = double(:innate_spells => innate)
        allow(Pf2emagic::Entries).to receive(:casting).with(magic).and_return(entries)

        double(:name => 'Someone', :magic => magic)
      end

      describe "Adapted Cantrip's other traditions" do
        it "should offer Primal to a Ranger whose Sorcerer dedication is of a Hag bloodline" do
          char = someone([ ranger_entry, sorcerer_archetype('occult') ])

          expect(Pf2e.choice_dynamic_options(char, 'other_traditions')).to eq [ 'Arcane', 'Divine', 'Primal' ]
        end

        it "should leave out Primal for a Ranger whose Sorcerer dedication is of a Fey bloodline" do
          char = someone([ ranger_entry, sorcerer_archetype('primal') ])

          expect(Pf2e.choice_dynamic_options(char, 'other_traditions')).to eq [ 'Arcane', 'Divine', 'Occult' ]
        end

        it "should leave out Primal for a Druid" do
          char = someone([ druid_entry ])

          expect(Pf2e.choice_dynamic_options(char, 'other_traditions')).to eq [ 'Arcane', 'Divine', 'Occult' ]
        end
      end

      describe "the caster prerequisite" do
        it "should not count a Ranger with only focus spells as a caster" do
          expect(Pf2e.character_is_caster?(someone([ ranger_entry ]))).to be false
        end

        it "should count a Ranger with a Sorcerer dedication as a caster" do
          expect(Pf2e.character_is_caster?(someone([ ranger_entry, sorcerer_archetype('occult') ]))).to be true
        end
      end
    end
  end
end
