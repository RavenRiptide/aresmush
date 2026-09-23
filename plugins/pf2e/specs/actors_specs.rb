require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Who the engine is working on, asked once.
    #
    # A creature in an encounter answers the engine's questions differently from a character, and the
    # code that works on whoever it has asks the actor rather than asking which kind it is. That only
    # holds while every question one actor answers, the other answers too - a method added to one and
    # forgotten on the other would send a creature down a character's path, or raise.
    describe Actors do

      def answers(klass)
        klass.public_instance_methods - Object.public_instance_methods
      end

      it "should answer the same questions for a character and a creature" do
        expect(answers(CharacterActor).sort).to eq answers(CreatureActor).sort
      end

      it "should choose the creature's for a creature and the character's for anyone else" do
        expect(Actors.of(Pf2eNpc.new)).to be_a(CreatureActor)
        expect(Actors.of(double('character'))).to be_a(CharacterActor)
      end

      # The one place the engine asks which kind of actor it has.
      it "should be the only place that asks" do
        root = File.expand_path('../..', __dir__)
        asking = Dir[File.join(root, '**', '*.rb')].reject { |path| path.include?('/specs/') }
                                                   .select { |path| File.read(path).match?(/is_a\?\((Pf2eNpc|Pf2eCombatantState)\)|Pf2e\.npc\?/) }

        expect(asking.map { |path| File.basename(path) }).to eq [ 'actors.rb' ]
      end
    end
  end
end
