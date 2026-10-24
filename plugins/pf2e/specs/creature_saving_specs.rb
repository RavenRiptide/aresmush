require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Saving a stat block, as the commands and the web editor both do: a new creature, a new revision of
    # one, or either by name.
    describe CreatureSaving, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @author = Character.create(:name => "Saver#{rand(1000000)}")
        allow(HouseBestiary).to receive(:write!).and_return(nil)
      end

      after(:each) do
        Pf2eCreature.all.to_a.select { |creature| creature.owner_id == @author.id }.each(&:delete)
        @author.delete
      end

      def block(more = {})
        Described.read('x', 'ac 18 hp 40 level 3 perception 9; strike jaws +11 1d10+5 piercing').state.merge(more)
      end

      describe "a new creature" do
        it "should be saved under its name, with its notes" do
          made = CreatureSaving.create(@author, 'Barrow Hound', block, :cloned_from => 'described', :notes => 'for the barrow')

          creature = made.state['creature']
          expect([ creature.name, creature.head.block['name'], creature.notes, creature.cloned_from ]).to eq [ 'Barrow Hound', 'Barrow Hound', 'for the barrow', 'described' ]
          expect([ made.state['created'], made.state['revision'].number ]).to eq [ true, 1 ]
        end

        it "should be refused with every finding when the block has errors" do
          refused = CreatureSaving.create(@author, 'Barrow Hound', block('hp' => 0))

          expect(refused.code).to eq :creature_invalid
          expect(refused.args['errors'].map { |one| one['code'] }).to include(:creature_needs)
          expect(Pf2eCreature.find(:name_slug => 'barrow-hound').to_a).to eq []
        end

        it "should be refused a name the author already has" do
          CreatureSaving.create(@author, 'Barrow Hound', block)

          expect(CreatureSaving.create(@author, 'barrow hound', block).code).to eq :creature_name_yours
        end
      end

      describe "a new revision" do
        before(:each) { @hound = CreatureSaving.create(@author, 'Barrow Hound', block).state['creature'] }

        it "should be refused against a revision since changed, with the head" do
          CreatureSaving.revise(@author, @hound, block('ac' => 19), :base_revision => 1)
          stale = CreatureSaving.revise(@author, @hound, block('ac' => 20), :base_revision => 1)

          expect([ stale.code, stale.args['head'] ]).to eq [ :creature_stale, 2 ]
        end

        it "should rename it where its name changed, and keep its notes unless given new ones" do
          CreatureStore.notes!(@hound, 'kept', @author)
          done = CreatureSaving.revise(@author, @hound, block('ac' => 19), :name => 'Grave Hound')

          expect([ done.state['creature'].name, done.state['creature'].notes, done.state['revision'].summary ]).to eq [ 'Grave Hound', 'kept', 'AC 18 to 19' ]
        end

        it "should save nothing where nothing changed" do
          expect(CreatureSaving.revise(@author, @hound, block).state['revision']).to be_nil
        end
      end

      describe "by name" do
        it "should revise the author's own of that name, and refuse it to a copy" do
          CreatureSaving.create(@author, 'Barrow Hound', block)

          expect(CreatureSaving.save(@author, 'Barrow Hound', block('ac' => 19)).state['created']).to be false
          expect(CreatureSaving.save(@author, 'Barrow Hound', block, :fresh => true).code).to eq :creature_name_yours
        end

        it "should make a new one under the name of the author's retired one" do
          first = CreatureSaving.create(@author, 'Barrow Hound', block).state['creature']
          CreatureStore.retire!(first, @author, true)

          again = CreatureSaving.save(@author, 'Barrow Hound', block)

          expect(again.state['created']).to be true
          expect(again.state['creature'].id).to_not eq first.id
        end
      end
    end
  end
end
