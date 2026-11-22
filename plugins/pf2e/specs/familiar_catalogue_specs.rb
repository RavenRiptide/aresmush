require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The familiar catalogues agree with each other and with the rest of the config.
    describe "familiar catalogues" do

      before(:all) do
        @abilities = YAML.load_file('game/config/pf2e_familiar_abilities.yml')['pf2e_familiar_abilities']
        @specific = YAML.load_file('game/config/pf2e_specific_familiars.yml')['pf2e_specific_familiars']
        @witch = YAML.load_file('game/config/pf2e_specialty.yml')['pf2e_specialty']['Witch']
      end

      it "should give every ability a kind, a source and a description" do
        bad = @abilities.reject do |_name, info|
          %w{familiar master patron}.include?(info['kind']) && !info['source'].blank? && !info['shortdesc'].blank?
        end

        expect(bad.keys).to be_empty
      end

      it "should take abilities only from Player Core and Player Core 2" do
        expect(@abilities.values.map { |info| info['source'] }.uniq.sort).to eq [ 'Player Core', 'Player Core 2' ]
      end

      it "should list the ten pet abilities" do
        pets = @abilities.select { |_name, info| info['pet'] }.keys.sort

        expect(pets).to eq [ 'Amphibious', 'Burrower', 'Climber', 'Darkvision', 'Echolocation', 'Fast Movement',
                             'Flier', 'Manual Dexterity', 'Scent', 'Tough' ]
      end

      it "should give each Witch patron one ability, and name only patrons the Witch has" do
        given = @abilities.select { |_name, info| info['kind'] == 'patron' }.map { |_name, info| info['patron'] }

        expect(given.sort).to eq @witch.keys.sort
      end

      it "should require only abilities the catalogue has" do
        named = @abilities.flat_map { |_name, info| Array((info['prereq'] || {})['abilities']) }

        expect(named - @abilities.keys).to be_empty
      end

      it "should require only specific familiars the catalogue has" do
        named = @abilities.filter_map { |_name, info| (info['prereq'] || {})['specific'] }

        expect(named - @specific.keys).to be_empty
      end

      # `familiar_innate` on a feat that gives a familiar: abilities it has free, and sets to pick one from.
      it "should give a familiar free only abilities the catalogue has" do
        feats = %w{ancestry class dedication general skill}.each_with_object({}) do |file, out|
          out.merge!(YAML.load_file("game/config/pf2e_feat_#{file}.yml")['pf2e_feats'] || {})
        end
        innate = feats.values.filter_map { |info| info.is_a?(Hash) ? info['familiar_innate'] : nil }
        named = innate.flat_map { |one| Array(one['abilities']) + Array(one['choose']) }

        expect(innate).to_not be_empty
        expect(named - @abilities.keys).to be_empty
      end

      describe "specific familiars" do
        it "should be the six in Player Core 2, without the imp" do
          expect(@specific.keys.sort).to eq [ 'Aeon Wyrd', 'Fey Dragonet', 'Homunculus', 'Pipefox', 'Poppet', 'Spellslime' ]
        end

        it "should give only abilities the catalogue has" do
          named = @specific.flat_map { |_name, info| Array(info['abilities']) + Array(info['porter']) }

          expect(named - @abilities.keys).to be_empty
        end

        it "should use at least as many abilities as it gives" do
          short = @specific.reject do |_name, info|
            given = Array(info['abilities']).size + (info['porter'] ? 1 : 0)
            info['uses'].to_i >= given
          end

          expect(short.keys).to be_empty
        end

        it "should only ask for a choice an ability it gives makes, or one it describes itself" do
          bad = @specific.flat_map do |name, info|
            Array(info['choices']).reject do |choice|
              %w{porter linguist}.include?(choice) ||
                (Array(info['abilities']).include?(choice) && @abilities[choice]['choice'])
            end.map { |choice| "#{name}: #{choice}" }
          end

          expect(bad).to be_empty
        end

        it "should describe every special ability in terms of the familiar's name" do
          texts = @specific.values.flat_map { |info| (info['specials'] || {}).values }

          expect(texts).to all(include('%{name}'))
        end
      end
    end
  end
end
