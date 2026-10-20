require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What the portal is given of the creatures: each viewer sees what the `creature` commands would show
    # them, and nothing more.
    describe "the creature pages' requests", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        tag = rand(1000000)
        @pm = Character.create(:name => "Maren#{tag}")
        @player = Character.create(:name => "Pell#{tag}")
        @admin = Character.create(:name => "Ada#{tag}")
        allow_any_instance_of(Character).to receive(:is_admin?) { |char| char.id == @admin.id }
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow_any_instance_of(Character).to receive(:has_permission?) { |char, permission| permission == 'kill_pc' && char.id == @pm.id }
        allow(Website).to receive(:check_login).and_return(nil)
        allow(HouseBestiary).to receive(:path).and_return(File.join(Dir.tmpdir, "house-#{tag}.yml"))

        @draft = CreatureStore.create!(@pm, 'Barrow Hound', Described.read('x', 'ac 18 hp 40 level 3').state)
        @published = CreatureStore.create!(@pm, 'Bog Hound', Described.read('x', 'ac 16 hp 30 level 2').state)
        CreatureReview.submit!(@published, @pm, '')
        CreatureReview.approve!(@published, @admin)
      end

      after(:each) do
        owners = [ @pm, @player, @admin ].map(&:id)
        Pf2eCreature.all.to_a.select { |creature| owners.include?(creature.owner_id) }.each(&:delete)
        [ @pm, @player, @admin ].each(&:delete)
      end

      def asked(handler, who, args)
        handler.new.handle(double(:args => args, :enactor => Character[who.id]))
      end

      def names(answer)
        answer[:creatures].map { |one| one[:name] }
      end

      it "should need a login" do
        allow(Website).to receive(:check_login).and_return({ error: 'login' })

        expect(asked(PF2CreaturesHandler, @player, {})).to eq({ error: 'login' })
      end

      describe "the library" do
        it "should list an author's own" do
          expect(names(asked(PF2CreaturesHandler, @pm, { 'scope' => 'mine' }))).to eq [ 'Bog Hound', 'Barrow Hound' ]
        end

        it "should show a player only what is published" do
          expect(names(asked(PF2CreaturesHandler, @player, { 'scope' => 'published' }))).to eq [ 'Bog Hound' ]
          expect(names(asked(PF2CreaturesHandler, @player, { 'scope' => 'mine' }))).to eq []
        end

        it "should mark which bestiary creatures a player may add, and which are there to build from" do
          answer = asked(PF2CreaturesHandler, @player, { 'scope' => 'bestiary', 'words' => 'goblin warrior' })
          goblin = answer[:creatures].find { |one| one[:name] == 'Goblin Warrior' }

          expect([ goblin[:addable], answer[:open_bestiaries] ]).to eq [ true, [ 'pathfinder-monster-core', 'pathfinder-monster-core-2' ] ]
          expect(asked(PF2CreaturesHandler, @player, { 'scope' => 'bestiary' })[:creatures].map { |one| one[:addable] }.uniq).to contain_exactly(false, true)
        end

        it "should give everything to an admin, and the all scope to no one else" do
          expect(names(asked(PF2CreaturesHandler, @admin, { 'scope' => 'all' }))).to include('Barrow Hound', 'Bog Hound')
          expect(asked(PF2CreaturesHandler, @player, { 'scope' => 'all' })[:scope]).to eq 'mine'
        end

        it "should filter by level and by words, and page" do
          answer = asked(PF2CreaturesHandler, @pm, { 'scope' => 'mine', 'level_from' => '3', 'words' => 'hound' })

          expect([ names(answer), answer[:total], answer[:pages] ]).to eq [ [ 'Barrow Hound' ], 1, 1 ]
        end

        it "should list and filter a creature at the level of the revision each viewer is shown" do
          CreatureStore.revise!(@published, Described.read('x', 'ac 16 hp 30 level 5').state, @pm)

          expect(asked(PF2CreaturesHandler, @player, { 'scope' => 'published', 'level_to' => '2' })[:creatures].map { |one| one[:level] }).to eq [ 2 ]
          expect(names(asked(PF2CreaturesHandler, @player, { 'scope' => 'published', 'level_from' => '5' }))).to eq []
          expect(names(asked(PF2CreaturesHandler, @pm, { 'scope' => 'mine', 'level_from' => '5' }))).to eq [ 'Bog Hound' ]
        end

        it "should make up only the page it gives" do
          stub_const('AresMUSH::Pf2e::CreatureWeb::PAGE', 1)
          allow(CreatureWeb).to receive(:saved_summary).and_call_original
          allow(Gm).to receive(:open?).and_call_original

          asked(PF2CreaturesHandler, @pm, { 'scope' => 'mine' })
          asked(PF2CreaturesHandler, @pm, { 'scope' => 'bestiary' })

          expect(CreatureWeb).to have_received(:saved_summary).once
          expect(Gm).to have_received(:open?).once
        end
      end

      describe "one creature" do
        it "should give its author the stat block, how to add it, and its history" do
          answer = asked(PF2CreatureHandler, @pm, { 'ref' => "saved:#{@draft.id}" })

          expect(answer[:lines].join("\n")).to include('Barrow Hound', 'AC 18')
          expect([ answer[:add], answer[:addable] ]).to eq [ "+e/add c:#{@draft.id}", true ]
          expect(answer[:history].map { |one| one[:kind] }).to eq [ 'created' ]
          expect([ answer[:block]['ac'], answer[:editing_revision] ]).to eq [ 18, 1 ]
        end

        it "should find only a saved creature by its id, whatever else the id says" do
          expect(asked(PF2CreatureHandler, @pm, { 'ref' => "saved:#{@draft.id}\nGoblin Warrior" })[:error]).to eq t('pf2e.creature_web_not_found')
          expect(asked(PF2CreatureHandler, @pm, { 'ref' => 'saved:Goblin Warrior' })[:error]).to eq t('pf2e.creature_web_not_found')
          expect(asked(PF2CreatureActHandler, @pm, { 'id' => 'Goblin Warrior', 'act' => 'retire' })[:error]).to eq t('pf2e.creature_web_not_found')
        end

        it "should refuse a player a draft that is not theirs, saying only that it is not there" do
          expect(asked(PF2CreatureHandler, @player, { 'ref' => "saved:#{@draft.id}" })[:error]).to eq t('pf2e.creature_web_not_found')
        end

        it "should show a player a published one, with no history or notes" do
          answer = asked(PF2CreatureHandler, @player, { 'ref' => "saved:#{@published.id}" })

          expect([ answer[:addable], answer[:history], answer[:notes], answer[:block] ]).to eq [ true, [], nil, nil ]
        end

        it "should show a bestiary creature, and say a player may not add one outside the open books" do
          open = asked(PF2CreatureHandler, @player, { 'ref' => 'bestiary:Goblin Warrior' })
          shut = Bestiary.index.find { |_name, one| !Gm.open_bestiaries.include?(one['pack']) }.first

          expect([ open[:addable], open[:add] ]).to eq [ true, '+e/add Goblin Warrior' ]
          expect(asked(PF2CreatureHandler, @player, { 'ref' => "bestiary:#{shut}" })[:addable]).to be false
        end
      end

      describe "the editor" do
        def block(**more)
          Described.read('x', 'ac 18 hp 40 level 3; strike jaws +11 1d10+5 piercing').state.merge(more.transform_keys(&:to_s))
        end

        it "should check a block as it is built: errors, warnings, what the game runs, and its stat block" do
          answer = asked(PF2CreatureCheckHandler, @pm, { 'name' => 'Grave Hound', 'block' => block('traits' => [ 'undead', 'glorp' ]) })

          expect(answer[:errors]).to eq []
          expect(answer[:warnings].map { |one| one[:code] }).to eq [ 'creature_trait_unknown' ]
          expect(answer[:mechanised].map { |one| one['part'] }).to eq [ 'Strike Jaws' ]
          expect(answer[:lines].first).to start_with('Grave Hound')
          expect(answer[:bands].find { |one| one['figure'] == 'AC' }['band']).to eq 'moderate'
        end

        it "should not check against another's creature" do
          expect(asked(PF2CreatureCheckHandler, @player, { 'id' => @draft.id, 'name' => 'x', 'block' => block })[:error]).to eq t('pf2e.creature_web_not_found')
        end

        it "should say what is wrong with a name, and an error in a figure" do
          answer = asked(PF2CreatureCheckHandler, @pm, { 'name' => 'Goblin Warrior', 'block' => block('hp' => 0) })

          expect(answer[:errors].map { |one| one[:code] }).to eq %w{creature_name_bestiary creature_needs}
        end

        it "should save a new creature, and a new revision of it against the revision it was editing" do
          made = asked(PF2CreatureSaveHandler, @pm, { 'name' => 'Grave Hound', 'block' => block })
          creature = Pf2eCreature[made[:id]]

          again = asked(PF2CreatureSaveHandler, @pm, { 'id' => creature.id, 'base_revision' => 1, 'name' => 'Grave Hound', 'block' => block('ac' => 19) })

          expect([ made[:revision], again[:revision], again[:summary] ]).to eq [ 1, 2, 'AC 18 to 19' ]
        end

        it "should refuse a save against a revision someone has since changed" do
          made = asked(PF2CreatureSaveHandler, @pm, { 'name' => 'Grave Hound', 'block' => block })
          asked(PF2CreatureSaveHandler, @pm, { 'id' => made[:id], 'base_revision' => 1, 'name' => 'Grave Hound', 'block' => block('ac' => 19) })

          stale = asked(PF2CreatureSaveHandler, @pm, { 'id' => made[:id], 'base_revision' => 1, 'name' => 'Grave Hound', 'block' => block('ac' => 20) })

          expect([ stale[:error], stale[:head] ]).to eq [ t('pf2e.creature_stale'), 2 ]
        end

        it "should not save what has errors, or another's creature" do
          expect(asked(PF2CreatureSaveHandler, @pm, { 'name' => 'Grave Hound', 'block' => block('hp' => 0) })[:errors]).to_not be_empty
          expect(asked(PF2CreatureSaveHandler, @player, { 'id' => @draft.id, 'base_revision' => 1, 'name' => 'Barrow Hound', 'block' => block })[:error])
            .to eq t('pf2e.creature_web_not_found')
        end

        it "should keep engine rules only where the creature it came from had them" do
          ruled = block.merge('strikes' => [ { 'name' => 'Jaws', 'bonus' => 11, 'damage' => [ [ '1d10+5', 'piercing', nil ] ], 'rules' => [ { 'key' => 'FlatModifier' } ] } ])
          made = asked(PF2CreatureSaveHandler, @pm, { 'name' => 'Grave Hound', 'block' => ruled })

          expect(Pf2eCreature[made[:id]].head.block['strikes'].first['rules']).to be_nil
        end

        it "should start one from a bestiary creature, rules and all, or blank at a level" do
          goblin = asked(PF2CreatureStartHandler, @pm, { 'from' => 'bestiary:Goblin Warrior' })
          blank = asked(PF2CreatureStartHandler, @pm, { 'from' => 'blank', 'level' => '4' })

          expect([ goblin[:block]['ac'], goblin[:cloned_from], blank[:block]['level'] ]).to eq [ 16, 'bestiary:Goblin Warrior', 4 ]
          expect(asked(PF2CreatureStartHandler, @pm, { 'from' => 'described', 'words' => 'ac 15 hp 20 level 1' })[:block]['ac']).to eq 15
          expect(asked(PF2CreatureStartHandler, @pm, { 'from' => 'described', 'words' => 'a goblin' })[:error]).to eq t('pf2e.creature_save_words')
        end

        it "should start from a bestiary creature in the shape the editor saves" do
          goblin = asked(PF2CreatureStartHandler, @pm, { 'from' => 'bestiary:Goblin Warrior' })[:block]

          expect(goblin).to eq CreatureBlock.cleaned(goblin, Bestiary.entry('Goblin Warrior'))
          expect(goblin['strikes'].map { |one| one['rules'] }).to eq(Bestiary.entry('Goblin Warrior')['strikes'].map { |one| one['rules'] })
        end

        it "should offer the words a block may use" do
          answer = asked(PF2CreatureOptionsHandler, @pm, {})

          expect(answer[:traits]).to include('undead', 'arvek')
          expect(answer[:damage_types]).to include('fire', 'piercing')
          expect(answer[:sizes]).to eq %w{tiny small medium large huge gargantuan}
        end
      end

      describe "approval and the queue" do
        before(:each) do
          allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
          allow(Login).to receive(:notify)
        end

        def acted(who, creature, act, more = {})
          asked(PF2CreatureActHandler, who, { 'id' => creature.id, 'act' => act }.merge(more))
        end

        it "should let its author submit it, and an admin see it in the queue and approve it" do
          acted(@pm, @draft, 'submit', 'note' => 'for the barrow')
          history = asked(PF2CreatureHandler, @pm, { 'ref' => "saved:#{@draft.id}" })[:history]
          expect(history.map { |one| [ one[:kind], one[:summary] ] }).to eq [ [ 'created', 'created' ], [ 'submitted', nil ] ]

          queue = asked(PF2CreatureQueueHandler, @admin, {})[:submissions].select { |one| one[:creature][:id] == @draft.id }
          expect(queue.map { |one| [ one[:creature][:name], one[:note], one[:changes] ] }).to eq [ [ 'Barrow Hound', 'for the barrow', 'new' ] ]

          answer = asked(PF2CreatureReviewHandler, @admin, { 'id' => @draft.id, 'decision' => 'approve' })
          expect([ answer[:creature][:status], Pf2eCreature[@draft.id].status ]).to eq [ 'published', 'published' ]
        end

        it "should say what keeps a creature from approval, and what decisions there are" do
          broken = CreatureStore.create!(@pm, 'Broken Hound', { 'level' => 3, 'ac' => 18, 'hp' => 0 })

          expect(acted(@pm, broken, 'submit')[:error]).to eq t('pf2e.creature_invalid', :errors => t('pf2e.creature_needs', :figure => 'HP'))
          expect(asked(PF2CreatureReviewHandler, @admin, { 'id' => @draft.id, 'decision' => 'shelve' })[:error])
            .to eq t('pf2e.creature_decision', :decisions => 'approve, reject, unpublish')
        end

        it "should take a submission for its author's storylines only, show the queue so, and let its author make it public" do
          mine = CreatureStore.create!(@player, 'Pell Hound', Described.read('x', 'ac 16 hp 30 level 2').state)
          acted(@player, mine, 'submit', 'note' => 'my storyline', 'for' => 'author')

          queued = asked(PF2CreatureQueueHandler, @admin, {})[:submissions].find { |one| one[:creature][:id] == mine.id }
          expect(queued[:approved_for]).to eq 'author'

          answer = asked(PF2CreatureReviewHandler, @admin, { 'id' => mine.id, 'decision' => 'approve' })
          expect([ answer[:creature][:status], answer[:creature][:approved_for], answer[:creature][:can]['make_public'] ]).to eq [ 'approved', 'author', true ]

          expect(acted(@player, mine, 'make_public')[:creature][:status]).to eq 'published'
          expect(acted(@player, mine, 'make_public')[:error]).to eq t('pf2e.creature_may_not', :action => 'make_public')
        end

        it "should keep the queue and decisions from anyone but an admin" do
          acted(@pm, @draft, 'submit')

          expect(asked(PF2CreatureQueueHandler, @pm, {})[:error]).to eq t('pf2e.creature_may_not', :action => 'review')
          expect(asked(PF2CreatureReviewHandler, @pm, { 'id' => @draft.id, 'decision' => 'approve' })[:error]).to eq t('pf2e.creature_may_not', :action => 'review')
        end

        it "should send one back with a reason, and need one" do
          acted(@pm, @draft, 'submit')

          expect(asked(PF2CreatureReviewHandler, @admin, { 'id' => @draft.id, 'decision' => 'reject', 'note' => '' })[:error]).to eq t('pf2e.creature_reason')
          asked(PF2CreatureReviewHandler, @admin, { 'id' => @draft.id, 'decision' => 'reject', 'note' => 'Too strong.' })
          expect(Pf2eCreature[@draft.id].review_note).to eq 'Too strong.'
        end

        it "should let its author withdraw it, retire it and restore it, and nobody else" do
          acted(@pm, @draft, 'submit')
          expect(acted(@pm, @draft, 'withdraw')[:creature][:status]).to eq 'draft'
          expect(acted(@pm, @draft, 'retire')[:creature][:status]).to eq 'retired'
          expect(acted(@pm, @draft, 'restore')[:creature][:status]).to eq 'draft'

          expect(acted(@player, @published, 'retire')[:error]).to eq t('pf2e.creature_may_not', :action => 'retire')
        end

        it "should not restore one under a name its author has used since" do
          acted(@pm, @draft, 'retire')
          again = CreatureStore.create!(@pm, 'Barrow Hound', Described.read('x', 'ac 18 hp 40 level 3').state)

          expect(acted(@pm, @draft, 'restore')[:error]).to eq t('pf2e.creature_name_yours', :name => 'Barrow Hound')
          expect(Pf2eCreature[@draft.id].status).to eq 'retired'
        end

        it "should let an admin hand one on and purge it, and nobody else" do
          expect(acted(@pm, @draft, 'purge')[:error]).to eq t('pf2e.creature_may_not', :action => 'purge')

          expect(acted(@admin, @draft, 'hand', 'to' => @player.name)[:creature][:owner]).to eq @player.name
          expect(acted(@admin, @draft, 'hand', 'to' => 'Nobody At All')[:error]).to eq t('pf2e.char_not_found')
          expect(acted(@admin, @draft, 'purge')).to eq(purged: true)
          expect(Pf2eCreature[@draft.id]).to be_nil
        end

        it "should share with every Plotmaster, and with named characters" do
          expect(acted(@pm, @draft, 'share', 'plotmasters' => true, 'with' => [ @admin.name ])[:creature][:audience]).to eq 'plotmasters'
          expect(Pf2eCreature[@draft.id].shared_with).to eq [ @admin.id.to_s ]

          expect(acted(@pm, @draft, 'share', 'plotmasters' => false, 'with' => [ @player.name ])[:error])
            .to eq t('pf2e.creature_share_who', :name => @player.name)
        end
      end
    end
  end
end
