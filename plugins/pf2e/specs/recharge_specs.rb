require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An ability a creature cannot use again for some rounds, in each way a stat block words it.
    describe Recharge do

      def ability(name, text)
        { 'name' => name, 'text' => text }
      end

      describe "how long an ability is gone" do
        WAITS = [
          [ 'Flame Breath', "The scamp can't use Flame Breath again for 1d4 rounds.", '1d4' ],
          [ 'Captivating Pollen', "The viper vine can't use Captivating Pollen for 1d4 rounds.", '1d4' ],
          [ 'Slice of Death', "The ghost can't use Slice Of Death for 1d4 rounds.", '1d4' ],
          [ 'Leap Attack', "The morlock can't use Leap Attack for 1 round.", '1' ],
          [ 'Word of Wisdom', "The dragon can't use this ability again for 1d4 rounds.", '1d4' ],
          [ 'Ghostly Swoop', "The drinesh can't use it again for 1d4 rounds.", '1d4' ],
          [ 'Poison Breath', "The catoblepas can't use its Poison Breath again for 1d4 rounds.", '1d4' ],
          [ 'Fog of Chance', "The dragonet can't use Fortune Fog again for 1d4 rounds.", '1d4' ],
          [ 'Soporific Spores', "Soporific Spores can't be used again for 1d4 rounds.", '1d4' ],
          [ 'Double Breath', "The linnorm can't use Corrosive Breath or Double Breath again for 2d4 rounds.", '2d4' ],
          [ 'Destructive Finale', "The drummer can't use March to War or Destructive Finale for 1d4 rounds.", '1d4' ]
        ].freeze

        WAITS.each do |name, text, rounds|
          it "should read #{rounds} from: #{text}" do
            expect(Recharge.rounds_of(name, ability(name, text))).to eq rounds
          end
        end

        it "should read the wait and not what the ability does to its targets" do
          text = "A creature that fails can't use reactions for 1 round. The brigade can't use Crushing Despair again for 1d4 rounds."

          expect(Recharge.rounds_of('Crushing Despair', ability('Crushing Despair', text))).to eq '1d4'
        end

        NOT_WAITS = [
          [ 'Crushing Despair', "A creature that fails can't use reactions for 1 round." ],
          [ 'Godslayer', "The target can't use divine spells or abilities for 1 round." ],
          [ 'Eye Ray', "Once the retriever has used all four options, the eye ray Strike can't be used for 1d4 rounds." ],
          [ 'Tail Sweep', 'Each creature within reach takes 2d6 bludgeoning damage.' ]
        ].freeze

        NOT_WAITS.each do |name, text|
          it "should read no wait from: #{text}" do
            expect(Recharge.rounds_of(name, ability(name, text))).to be_nil
          end
        end
      end

      describe "abilities that wait together" do
        it "should name each of the creature's abilities the words name" do
          own = ability('Corrosive Breath', "The linnorm can't use Corrosive Breath or Double Breath again for 1d4 rounds.")
          others = [ own, ability('Double Breath', ''), ability('Tail Sweep', '') ]

          expect(Recharge.waiting('Corrosive Breath', own, others)).to eq [ 'Corrosive Breath', 'Double Breath' ]
        end

        it "should not take a part of the ability's own name for another ability" do
          own = ability('Blackfrost Breath', "The zombie can't use Blackfrost Breath again for 1d4 rounds.")

          expect(Recharge.waiting('Blackfrost Breath', own, [ own, ability('Blackfrost', '') ])).to eq [ 'Blackfrost Breath' ]
        end

        it "should name the ability alone where its words name no other" do
          own = ability('Word of Wisdom', "The dragon can't use this ability again for 1d4 rounds.")

          expect(Recharge.waiting('Word of Wisdom', own, [ own, ability('Dragon Breath', '') ])).to eq [ 'Word of Wisdom' ]
        end
      end
    end
  end
end
