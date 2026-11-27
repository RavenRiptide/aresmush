require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Spell Combination (Wizard 20): which two spells may be prepared to cast as one. Each must target, or
    # be able to target, a single creature or object, and both must be settled the same way: a spell
    # attack, the same save, or neither.
    describe "combining two spells" do
      before(:all) do
        @mechanics = YAML.load_file('game/config/pf2e_spell_mechanics.yml')['pf2e_spell_mechanics']
      end

      def row(name)
        [ name, @mechanics.fetch(name) ]
      end

      def refusal(first, second)
        SlotFeats.combination_refusal(row(first), row(second))
      end

      it "should combine two single-target spells against the same save" do
        expect(refusal('Blindness', 'Slow')).to be_nil
      end

      it "should combine two spell attacks" do
        expect(refusal('Acid Arrow', 'Briny Bolt')).to be_nil
      end

      it "should combine two spells with neither attack nor save" do
        expect(refusal('Haste', 'Heroism')).to be_nil
      end

      it "should refuse a spell with an area" do
        expect(refusal('Slow', 'Fireball').code).to eq :combination_area
      end

      it "should refuse a spell with no target" do
        expect(refusal('Haste', 'Mirror Image').code).to eq :combination_no_target
      end

      it "should refuse a spell that targets more than one at once" do
        expect(refusal('Haste', 'Forbidding Ward').code).to eq :combination_many_targets
      end

      it "should refuse spells against different saves, naming each one's" do
        found = refusal('Fear', 'Slow')

        expect(found.code).to eq :combination_resolves_differently
        expect(found.args).to include('first_way' => 'a Will save', 'second_way' => 'a Fortitude save')
      end

      it "should refuse a spell attack with a save" do
        expect(refusal('Acid Arrow', 'Slow').code).to eq :combination_resolves_differently
      end

      it "should refuse a spell attack with a spell that has neither" do
        expect(refusal('Acid Arrow', 'Haste').code).to eq :combination_resolves_differently
      end

      it "should refuse a spell the catalogue has no mechanics for" do
        expect(SlotFeats.combination_refusal([ 'Nonesuch', nil ], row('Slow')).code).to eq :combination_unknown
      end

      describe "a single target" do
        it "should allow a count that can be one, or one particular creature" do
          [ '1 creature', '1 willing living creature', 'one creature', 'up to 5 creatures', '1 or 2 creatures',
            '1 or more creatures', '1 to 3 willing creatures', 'your familiar', 'the triggering creature',
            'you or 1 ally', '1 creature or object', 'self', 'any number of creatures',
            '1 door no more than 10 feet tall and 5 feet wide', '1 creature, plus any number of additional creatures' ].each do |target|
            expect(SlotFeats.single_target?(target)).to be(true), target
          end
        end

        # Every distinct target in the catalogue, on a spell with no area, that the pattern refuses: read this
        # list to see where the line falls. A change to the data or to the pattern that moves the line fails
        # here, to be read again.
        refused = [
          "1 ally and 1 enemy",
          "1 creature and 1 object",
          "1 cubic foot",
          "1 enemy, and 1 weapon that is either unattended or wielded by you or a willing ally",
          "1 foe, and either yourself or 1 ally",
          "1 item you're holding and 1 item in another creature's possession you can see, each no more than light Bulk",
          "1 object held by 1 creature and the creature holding it",
          "1 square mile",
          "1 touched shield (unattended or in your possession) and 1 willing creature",
          "1 willing ally and 1 enemy",
          "1 willing creature and 1 non-magical stone object of 1 or 2 Bulk",
          "1-mile emanation",
          "10 pieces of siege weapon ammunition, such as a ballista bolt or catapult stone",
          "10-foot burst",
          "100 feet × 100 feet, up to 20 feet high",
          "2 containers, each no larger than 5 feet in any dimension",
          "2 creatures",
          "2 creatures no more than 10 feet from each other",
          "2 creatures of the same ancestry, whose respective levels are no more than twice the rank of the ritual",
          "2 creatures that each have an unfriendly or worse attitude toward the other",
          "2 creatures who are hostile toward each other",
          "2 creatures who you know",
          "2 to 4 creatures in range",
          "2 willing creatures",
          "4 creatures",
          "5 willing creatures",
          "Doorway to the Red Star",
          "Primary and Secondary Casters",
          "Ulgrem-Axaan's eggs",
          "You and up to 10 willing living allies",
          "all casters involved in ritual",
          "all creatures in range",
          "audience of up to 200 people",
          "body of water no larger than a 7-mile radius area",
          "cube of stone 10 feet across or smaller",
          "dead creatures and living creatures of your choice within range",
          "each ally targeted by the triggering spell",
          "non-magical object of light Bulk or less",
          "petrified creature or human-size stone object",
          "two creatures",
          "unattended written materials of up to 1 Bulk or less",
          "varies",
          "you and 1 ally",
          "you and 1 enemy",
          "you and 1 other humanoid",
          "you and 1 willing creature",
          "you and all secondary casters",
          "you and any number of willing allies",
          "you and the triggering ally",
          "you and up to 10 willing creatures touched",
          "you and up to 4 targets touched, either willing creatures or objects roughly the size of a creature.",
          "you and up to 4 willing creatures touched",
          "you and up to 5 willing creatures",
          "you and up to 5 willing targets",
          "you and up to 6 willing creatures",
          "you and up to 9 allies",
          "yourself and the secondary casters",
          "yourself and up to 3 other willing creatures",
          "yourself and up to 5 willing creatures",
        ]

        it "should refuse exactly these targets" do
          targets = @mechanics.values.select { |one| one['target'] && !one['area'] }.map { |one| one['target'] }.uniq.sort

          expect(targets.reject { |target| SlotFeats.single_target?(target) }).to eq refused
        end
      end
    end
  end
end
