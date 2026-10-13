require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # What the portal is given of an encounter.
    describe EncounterWeb, :dbtest => true do
      include FightBench

      before(:each) do
        bench!
        add('giant rat')
        @stranger = Character.create(:name => "Odd#{rand(1000000)}")
      end

      after(:each) do
        @stranger.delete
        clear_bench!
      end

      def shown(viewer, gm)
        Combatants.all(encounter).map { |one| EncounterWeb.combatant(encounter, one, viewer, gm) }
      end

      def of(rows, name)
        rows.find { |row| row[:name].start_with?(name) }
      end

      describe "Hero Points" do
        it "should be shown to the GM for each character, and for no creature" do
          rows = shown(Character[@gm.id], true)

          expect(of(rows, @hero.name)[:hero_points]).to eq 1
          expect(of(rows, 'Giant Rat')[:hero_points]).to be_nil
        end

        it "should be shown to the character whose they are" do
          expect(of(shown(Character[@hero.id], false), @hero.name)[:hero_points]).to eq 1
        end

        it "should be shown to nobody who may not see that character's combat sheet" do
          allow(Sheet).to receive(:viewable?).and_return(Err.new(:not_yours, 'pf2e.not_found'))

          expect(of(shown(Character[@stranger.id], false), @hero.name)[:hero_points]).to be_nil
        end

        it "should say in the history who spent one in a change" do
          History.append(encounter, "#{@hero.name}: e/strike #2=fist", {}, { 'x' => 1 })
          History.latest(encounter).update(:hero_spent => { @hero.name => 1 })

          expect(EncounterWeb.history(encounter).last).to include(:heroes => [ @hero.name ])
        end
      end
    end
  end
end
