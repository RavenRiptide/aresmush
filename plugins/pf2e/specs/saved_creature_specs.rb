require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Saved creatures in the database: revisions that are never rewritten, names that resolve, approval
    # that publishes one revision, and the house bestiary file it writes.
    describe "saved creatures", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        tag = rand(1000000)
        @pm = Character.create(:name => "Maren#{tag}")
        @other_pm = Character.create(:name => "Oskar#{tag}")
        @player = Character.create(:name => "Pell#{tag}")
        @admin = Character.create(:name => "Ada#{tag}")
        pms = [ @pm.id, @other_pm.id ]
        allow_any_instance_of(Character).to receive(:is_admin?) { |char| char.id == @admin.id }
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow_any_instance_of(Character).to receive(:has_permission?) { |char, permission| permission == 'kill_pc' && pms.include?(char.id) }
        @house = File.join(Dir.tmpdir, "house-#{tag}.yml")
        allow(HouseBestiary).to receive(:path).and_return(@house)
        @made = []
      end

      after(:each) do
        @made.each { |creature| Pf2eCreature[creature.id]&.delete }
        [ @pm, @other_pm, @player, @admin ].each(&:delete)
        File.delete(@house) if File.exist?(@house)
      end

      def hound(by = @pm, name = 'Barrow Hound', words = 'ac 18 hp 40 level 3; strike jaws +11 1d10+5 piercing')
        made = CreatureStore.create!(by, name, Described.read(name, words).state)
        @made << made
        made
      end

      def found(char, term, action = 'view')
        Creatures.find(char, term, action)
      end

      describe "revisions" do
        it "should keep each edit as a new revision and never rewrite one" do
          creature = hound
          first = creature.head.block

          CreatureStore.revise!(creature, first.merge('ac' => 19), @pm)
          creature = Pf2eCreature[creature.id]

          expect(creature.revisions.to_a.map { |one| [ one.number, one.block['ac'] ] }.sort).to eq [ [ 1, 18 ], [ 2, 19 ] ]
          expect(creature.head.summary).to eq 'AC 18 to 19'
          expect(creature.head.block['source']).to eq "Custom: #{@pm.name}"
        end

        it "should make no revision of a block that has not changed" do
          creature = hound

          expect(CreatureStore.revise!(creature, creature.head.block, @pm)).to be_nil
          expect(Pf2eCreature[creature.id].revisions.to_a.size).to eq 1
        end

        it "should carry a new name in a revision of its own" do
          creature = hound
          CreatureStore.rename!(creature, 'Grave Hound', @pm)

          expect(Pf2eCreature[creature.id].head.block['name']).to eq 'Grave Hound'
          expect(Pf2eCreature[creature.id].events.to_a.map(&:kind)).to eq %w{created renamed}
        end
      end

      it "should keep a history of each thing done to it, with what each revision changed" do
        creature = hound
        CreatureStore.revise!(creature, Described.read('x', 'ac 19 hp 40 level 3; strike jaws +11 1d10+5 piercing').state, @pm)
        CreatureStore.rename!(Pf2eCreature[creature.id], 'Grave Hound', @pm)
        CreatureStore.share!(creature, 'plotmasters', [], @pm)

        rows = Creatures.history(Pf2eCreature[creature.id]).map { |one| [ one['kind'], one['revision'], one['summary'] ] }

        expect(rows).to eq [ [ 'created', 1, 'created' ], [ 'revised', 2, 'AC 18 to 19' ], [ 'renamed', 3, 'renamed from Barrow Hound' ], [ 'shared', nil, nil ] ]
      end

      describe "finding one by name" do
        it "should leave a bestiary name meaning the bestiary's creature" do
          expect(found(@pm, 'goblin warrior').state).to eq('source' => 'bestiary', 'name' => 'Goblin Warrior')
        end

        it "should find the author's own by name, and its latest revision" do
          creature = hound
          CreatureStore.revise!(creature, creature.head.block.merge('ac' => 20), @pm)

          ref = found(@pm, 'barrow hound').state
          expect([ ref['source'], ref['revision'].block['ac'] ]).to eq [ 'saved', 20 ]
        end

        it "should find one by c: and its id, or by c: and its name" do
          creature = hound

          expect(found(@pm, "c:#{creature.id}").state['creature'].id).to eq creature.id
          expect(found(@pm, 'c:barrow hound').state['creature'].id).to eq creature.id
        end

        it "should not find for anyone else a creature they may not see" do
          hound

          expect(found(@other_pm, 'barrow hound').code).to eq :not_found
          expect(found(@player, 'barrow hound').code).to eq :not_found
        end

        it "should list two others' creatures of one name for the one asking to choose" do
          hound(@pm)
          hound(@other_pm)
          @made.each { |creature| CreatureStore.share!(creature, 'plotmasters', [], creature.owner) }

          expect(found(@admin, 'barrow hound').code).to eq :ambiguous
          expect(found(@pm, 'barrow hound').state['creature'].owner_id).to eq @pm.id
        end

        it "should give everyone else the published revision, the author the latest" do
          creature = hound(@player)
          CreatureReview.submit!(creature, @player, '')
          CreatureReview.approve!(creature, @admin)
          CreatureStore.revise!(creature, Pf2eCreature[creature.id].head.block.merge('ac' => 25), @player)

          expect(found(@other_pm, 'barrow hound', 'use').state['revision'].block['ac']).to eq 18
          expect(found(@player, 'barrow hound', 'use').state['revision'].block['ac']).to eq 18
          expect(found(@admin, 'barrow hound', 'use').state['revision'].block['ac']).to eq 25
        end
      end

      describe "approval" do
        it "should publish the submitted revision, and write it to the house bestiary" do
          creature = hound(@player)

          expect(Creatures.usable?(@player, found(@player, 'barrow hound').state)).to be false

          CreatureReview.submit!(creature, @player, 'for my plot')
          CreatureReview.approve!(creature, @admin)

          expect(Pf2eCreature[creature.id].status).to eq 'published'
          expect(Creatures.usable?(@player, found(@player, 'barrow hound', 'use').state)).to be true
          expect(YAML.load_file(@house).keys).to eq [ 'Barrow Hound' ]
          expect(YAML.load_file(@house)['Barrow Hound']).to include('ac' => 18, 'approved' => 1)
        end

        it "should be refused for what is not submitted, or has nothing new, or is retired" do
          creature = hound(@player)

          expect(CreatureReview.approve!(creature, @admin).code).to eq :creature_not_submitted

          CreatureReview.submit!(creature, @player, '')
          expect(CreatureReview.submit!(creature, @player, '').code).to eq :creature_submitted
          CreatureReview.approve!(creature, @admin)
          expect(CreatureReview.submit!(creature, @player, '').code).to eq :creature_nothing_new

          CreatureStore.retire!(Pf2eCreature[creature.id], @admin, true)
          expect(CreatureReview.submit!(creature, @player, '').code).to eq :creature_retired
        end

        it "should send one back with a reason, which the author can read" do
          creature = hound(@player)
          CreatureReview.submit!(creature, @player, '')

          expect(CreatureReview.reject!(creature, @admin, '').code).to eq :creature_reason

          CreatureReview.reject!(creature, @admin, 'Its damage is above extreme for level 3.')
          creature = Pf2eCreature[creature.id]
          expect([ creature.status, creature.review_note ]).to eq [ 'draft', 'Its damage is above extreme for level 3.' ]
        end

        it "should refuse a second published creature of one name" do
          one = hound(@player)
          two = hound(@other_pm)
          [ [ one, @player ], [ two, @other_pm ] ].each { |creature, by| CreatureReview.submit!(creature, by, '') }
          CreatureReview.approve!(one, @admin)

          expect(CreatureReview.approve!(two, @admin).code).to eq :creature_published_name
        end

        it "should not take a creature with errors for approval, and say every one" do
          creature = CreatureStore.create!(@player, 'Broken Hound', { 'level' => 3, 'ac' => 18, 'hp' => 0 })
          @made << creature

          refused = CreatureReview.submit!(creature, @player, '')

          expect([ refused.code, refused.args['errors'].map { |one| one['code'] } ]).to eq [ :creature_invalid, [ :creature_needs ] ]
        end

        it "should take any of an admin's three decisions by name, and nothing else" do
          creature = hound(@player)
          CreatureReview.submit!(creature, @player, '')

          expect(CreatureReview.decide!(creature, @admin, 'shelve', '').code).to eq :creature_decision
          expect(CreatureReview.decide!(creature, @admin, 'reject', 'Too strong.').ok?).to be true
          CreatureReview.submit!(creature, @player, '')
          expect(CreatureReview.decide!(creature, @admin, 'approve', '').ok?).to be true
          expect(CreatureReview.decide!(creature, @admin, 'unpublish', '').ok?).to be true
          expect(Pf2eCreature[creature.id].status).to eq 'draft'
        end

        it "should tell the admins of a submission, and the author of a decision not their own" do
          creature = hound(@player)
          notifier = double(:notify_ooc => nil)
          allow(Global).to receive(:notifier).and_return(notifier)
          allow(Login).to receive(:notify)

          CreatureNotices.submitted(creature, @player)
          said = CreatureNotices.decided(creature, @admin, 'reject', 'Too strong.')
          CreatureNotices.decided(creature, @player, 'approve', '')

          expect(notifier).to have_received(:notify_ooc).with(:pf2_creature, t('pf2e.creature_awaits', :name => 'Barrow Hound', :id => creature.id, :author => @player.name))
          expect(said).to eq t('pf2e.creature_rejected', :name => 'Barrow Hound', :by => @admin.name, :reason => 'Too strong.')
          expect(Login).to have_received(:notify).once.with(@player, :pf2_creature, said, creature.id)
        end

        it "should take it out of the house bestiary when it is unpublished" do
          creature = hound(@player)
          CreatureReview.submit!(creature, @player, '')
          CreatureReview.approve!(creature, @admin)

          CreatureReview.unpublish!(creature, @admin)

          expect(YAML.load_file(@house)).to eq({})
          expect(Creatures.usable?(@player, found(@player, 'barrow hound').state)).to be false
        end
      end

      describe "names" do
        it "should refuse a name the author already has, in a rename" do
          hound(@pm, 'Barrow Hound')
          bog = hound(@pm, 'Bog Hound')

          expect(CreatureStore.name_free(@pm, 'barrow hound', bog).code).to eq :creature_name_yours
          expect(CreatureStore.name_free(@pm, 'Bog Hound', bog).ok?).to be true
        end

        it "should refuse a published creature's name to anyone else" do
          one = hound(@player)
          CreatureReview.submit!(one, @player, '')
          CreatureReview.approve!(one, @admin)

          expect(CreatureStore.name_free(@pm, 'Barrow Hound').code).to eq :creature_published_name
        end

        it "should keep the house bestiary under the name each was approved with" do
          one = hound(@player)
          CreatureReview.submit!(one, @player, '')
          CreatureReview.approve!(one, @admin)
          CreatureStore.rename!(one, 'Grave Hound', @player)

          expect(YAML.load_file(@house).keys).to eq [ 'Barrow Hound' ]
          expect(Pf2eCreature[one.id].head.summary).to eq 'renamed from Barrow Hound'
        end
      end

      it "should show its author the latest revision, once published and after they stop being a Plotmaster" do
        creature = hound(@player)
        CreatureReview.submit!(creature, @player, '')
        CreatureReview.approve!(creature, @admin)
        CreatureStore.revise!(creature, Pf2eCreature[creature.id].head.block.merge('ac' => 25), @player)

        ref = found(@player, 'barrow hound').state
        expect(Creatures.shown(@player, ref).block['ac']).to eq 25
        expect(Creatures.shown(@other_pm, found(@other_pm, 'barrow hound').state).block['ac']).to eq 18
      end

      describe "retired" do
        it "should take back its request for approval, and not be approved" do
          creature = hound(@player)
          CreatureReview.submit!(creature, @player, '')
          CreatureStore.retire!(creature, @player, true)

          expect(Pf2eCreature[creature.id].submitted_id).to be_nil
          expect(CreatureReview.approve!(creature, @admin).code).to eq :creature_not_submitted
        end

        it "should leave the house bestiary, and leave its name free" do
          creature = hound(@player)
          CreatureReview.submit!(creature, @player, '')
          CreatureReview.approve!(creature, @admin)

          CreatureStore.retire!(creature, @admin, true)

          expect(YAML.load_file(@house)).to eq({})
          expect(CreatureStore.name_free(@pm, 'Barrow Hound').ok?).to be true
        end
      end

      it "should say where the house bestiary could not be written, and keep the approval" do
        allow(HouseBestiary).to receive(:path).and_return('/nonexistent/dir/house.yml')
        creature = hound(@player)
        CreatureReview.submit!(creature, @player, '')

        done = CreatureReview.approve!(creature, @admin)

        expect(done.ok?).to be true
        expect(done.messages.map { |one| one['key'] }).to eq [ 'pf2e.creature_house_unwritten' ]
        expect(Pf2eCreature[creature.id].status).to eq 'published'
      end

      it "should keep a deleted author's published creatures, and retire the rest" do
        author = Character.create(:name => "Gone#{rand(1000000)}")
        kept = hound(author, 'Barrow Hound')
        dropped = hound(author, 'Bog Hound')
        CreatureReview.submit!(kept, author, '')
        CreatureReview.approve!(kept, @admin)

        author.delete

        expect([ Pf2eCreature[kept.id].status, Pf2eCreature[kept.id].owner_id, Pf2eCreature[kept.id].owner_name ]).to eq [ 'published', nil, author.name ]
        expect(Pf2eCreature[dropped.id].status).to eq 'retired'
      end

      describe "in an encounter" do
        before(:each) { @encounter = PF2Encounter.create(:organizer => @pm.name, :round => 1, :is_active => true) }
        after(:each) { PF2Encounter[@encounter.id]&.delete }

        it "should fight as the revision it was added with, whatever is edited after" do
          creature = hound
          added = Combatants.add_npc(PF2Encounter[@encounter.id], :revision => creature.head).state['npc']

          CreatureStore.revise!(creature, creature.head.block.merge('ac' => 30), @pm)

          expect(Pf2eNpc[added.id].stat_block['ac']).to eq 18
          expect(Pf2eNpc[added.id].name).to eq 'Barrow Hound #1'
        end
      end
    end
  end
end
