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
        [ @draft, @published ].each { |creature| Pf2eCreature[creature.id]&.delete }
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
      end

      describe "one creature" do
        it "should give its author the stat block, how to add it, and its history" do
          answer = asked(PF2CreatureHandler, @pm, { 'ref' => "saved:#{@draft.id}" })

          expect(answer[:lines].join("\n")).to include('Barrow Hound', 'AC 18')
          expect([ answer[:add], answer[:addable] ]).to eq [ "+e/add c:#{@draft.id}", true ]
          expect(answer[:history].map { |one| one[:kind] }).to eq [ 'created' ]
        end

        it "should refuse a player a draft that is not theirs, saying only that it is not there" do
          expect(asked(PF2CreatureHandler, @player, { 'ref' => "saved:#{@draft.id}" })[:error]).to include('No creature you may use')
        end

        it "should show a player a published one, with no history or notes" do
          answer = asked(PF2CreatureHandler, @player, { 'ref' => "saved:#{@published.id}" })

          expect([ answer[:addable], answer[:history], answer[:notes] ]).to eq [ true, [], nil ]
        end

        it "should show a bestiary creature, and say a player may not add one outside the open books" do
          open = asked(PF2CreatureHandler, @player, { 'ref' => 'bestiary:Goblin Warrior' })
          shut = Bestiary.index.find { |_name, one| !Gm.open_bestiaries.include?(one['pack']) }.first

          expect([ open[:addable], open[:add] ]).to eq [ true, '+e/add Goblin Warrior' ]
          expect(asked(PF2CreatureHandler, @player, { 'ref' => "bestiary:#{shut}" })[:addable]).to be false
        end
      end
    end
  end
end
