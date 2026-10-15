require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # The `creature` commands and the `+e` commands that reach saved creatures, typed by a Plotmaster
    # (the bench's GM), a player (its hero) and an admin.
    describe "the creature commands", :dbtest => true do
      include FightBench

      before(:each) do
        bench!
        @admin = Character.create(:name => "Ada#{rand(1000000)}")
        allow_any_instance_of(Character).to receive(:is_admin?) { |char| char.id == @admin.id }
        @house = File.join(Dir.tmpdir, "house-#{rand(1000000)}.yml")
        allow(HouseBestiary).to receive(:path).and_return(@house)
      end

      after(:each) do
        Pf2eCreature.all.to_a.select { |creature| [ @gm.id, @hero.id, @admin.id ].include?(creature.owner_id) }.each(&:delete)
        @admin.delete
        File.delete(@house) if File.exist?(@house)
        clear_bench!
      end

      def gm_types(text)
        typed_by(@gm, text)
      end

      def admin_types(text)
        typed_by(@admin, text)
      end

      def typed_by(who, text)
        @client.said.clear
        @client.failures.clear
        run(Pf2e.get_cmd_handler(@client, Command.new(text), Character[who.id]), text, who)
      end

      HOUND = 'creature/save Barrow Hound=ac 18 hp 40 level 3 perception 9; strike jaws +11 1d10+5 piercing; ' \
              'ability Grave Howl [2]: Each creature within 30 feet must attempt a DC 20 Will save.'.freeze

      def hound
        Pf2eCreature.find(:name_slug => 'barrow-hound').to_a.first
      end

      describe "saving and changing" do
        it "should save a creature from a description, and show it" do
          gm_types(HOUND)

          expect(refused).to eq []
          expect(heard).to include('Saved Barrow Hound as c:')

          gm_types("creature c:#{hound.id}")
          expect(heard).to include('Barrow Hound', 'AC 18', 'Melee Jaws +11', 'Grave Howl', 'draft')
        end

        it "should change one part at a time, each a revision that says what changed" do
          gm_types(HOUND)
          gm_types('creature/set barrow hound=ac 19')
          gm_types('creature/set barrow hound=strike jaws +12 2d8+5 piercing')

          expect(heard).to include('revision 3', 'Strike Jaws changed')
          expect(hound.head.block['ac']).to eq 19

          gm_types('creature/unset barrow hound=ability grave howl')
          expect(hound.head.block['actions']).to eq []
        end

        it "should refuse what the engine could not fight with, and save nothing" do
          gm_types('creature/save Barrow Hound=ac 18 hp 40 level 30')

          expect(hound).to be_nil
          expect(refused.join).to include('Not saved', t('pf2e.creature_level', :level => 30, :from => -1, :to => 25))
        end

        it "should refuse a bestiary creature's name" do
          gm_types('creature/save Goblin Warrior=ac 15 hp 20')

          expect(refused).to eq [ t('pf2e.creature_name_bestiary', :name => 'Goblin Warrior') ]
        end

        it "should clone a bestiary creature to make one's own" do
          gm_types('creature/clone goblin warrior=Goblin Skulker')

          made = Pf2eCreature.find(:name_slug => 'goblin-skulker').to_a.first
          expect([ made.head.block['name'], made.head.block['ac'], made.cloned_from ]).to eq [ 'Goblin Skulker', 16, 'bestiary:Goblin Warrior' ]
        end

        it "should print the line that makes it again" do
          gm_types(HOUND)
          gm_types('creature/describe barrow hound')

          expect(heard).to include('creature/save Barrow Hound=ac 18 hp 40 level 3 perception 9; strike Jaws +11 1d10+5 piercing')
        end

        it "should not clone over a creature of one's own" do
          gm_types(HOUND)
          gm_types('creature/clone goblin warrior=Barrow Hound')

          expect(refused).to eq [ t('pf2e.creature_name_yours', :name => 'Barrow Hound') ]
          expect(hound.head.block['ac']).to eq 18
        end

        it "should not rename onto a creature of one's own" do
          gm_types(HOUND)
          gm_types('creature/save Bog Hound=ac 15 hp 20')
          gm_types('creature/rename bog hound=Barrow Hound')

          expect(refused).to eq [ t('pf2e.creature_name_yours', :name => 'Barrow Hound') ]
        end

        it "should save a creature from the encounter it runs" do
          add('giant rat')
          gm_types('creature/save Sewer Rat=#2')

          made = Pf2eCreature.find(:name_slug => 'sewer-rat').to_a.first
          expect([ made.head.block['name'], made.cloned_from ]).to eq [ 'Sewer Rat', 'encounter' ]
        end

        it "should let nobody else change it" do
          gm_types(HOUND)
          hero_types("creature/set c:#{hound.id}=ac 30")

          expect(refused).to eq [ t('pf2e.creature_not_found', :creature => "c:#{hound.id}") ]
        end
      end

      describe "in an encounter" do
        it "should be added by name, as the revision it was then" do
          gm_types(HOUND)
          gm_types('+e/add barrow hound')

          expect(npc.name).to eq 'Barrow Hound #2'
          gm_types('creature/set barrow hound=ac 25')
          expect(npc.stat_block['ac']).to eq 18
        end

        it "should be taken back and put back by the GM, as the same revision" do
          gm_types(HOUND)
          gm_types('+e/add barrow hound')
          revision = npc.revision_id

          run(PF2EncounterUndoCmd, 'e/undo')
          expect(npc).to be_nil

          run(PF2EncounterUndoCmd, 'e/redo')
          expect([ npc.revision_id, npc.stat_block['ac'] ]).to eq [ revision, 18 ]
        end

        it "should be added elite, as any creature is" do
          gm_types(HOUND)
          gm_types('+e/add elite barrow hound')

          expect(npc.stat_block['ac']).to eq 20
        end

        it "should be listed by +e/bestiary as the GM's own" do
          gm_types(HOUND)
          gm_types('+e/bestiary hound')

          expect(heard).to include("c:#{hound.id} Barrow Hound", '[yours]')
        end

        it "should be shown by +e/creature" do
          gm_types(HOUND)
          gm_types('+e/creature barrow hound')

          expect(heard).to include('AC 18')
        end
      end

      describe "a player's own" do
        before(:each) { hero_types(HOUND) }

        it "should not be shared, since its author may not use it unapproved" do
          hero_types('creature/share barrow hound=plotmasters')

          expect(refused).to eq [ t('pf2e.creature_may_not', :action => 'share') ]
        end

        it "should be saved, and not added until an admin approves it" do
          expect(hound.owner_id).to eq @hero.id
          expect(Creatures.usable?(Character[@hero.id], Creatures.find(Character[@hero.id], 'barrow hound').state)).to be false
        end

        it "should go to an admin's queue when submitted, and be anyone's to add once approved" do
          hero_types('creature/submit barrow hound=for the barrow plot')
          admin_types('creature/queue')
          expect(heard).to include('Barrow Hound', 'for the barrow plot', 'new')

          admin_types('creature/approve barrow hound')
          expect(heard).to include('is approved by')

          gm_types('+e/add barrow hound')
          expect(npc.name).to eq 'Barrow Hound #2'
          expect(YAML.load_file(@house).keys).to eq [ 'Barrow Hound' ]
        end

        it "should go back to its author with a reason" do
          hero_types('creature/submit barrow hound')
          admin_types('creature/reject barrow hound=Its howl is above extreme.')

          hero_types('creature barrow hound')
          expect(heard).to include('Sent back: Its howl is above extreme.')
        end

        it "should not be the approver's work for a player" do
          hero_types('creature/submit barrow hound')
          hero_types('creature/approve barrow hound')

          expect(refused).to eq [ t('pf2e.creature_may_not', :action => 'review') ]
        end
      end

      describe "sharing" do
        before(:each) { gm_types(HOUND) }

        it "should be with a Plotmaster or an admin, and not a player" do
          gm_types("creature/share barrow hound=#{@hero.name}")
          expect(refused).to eq [ t('pf2e.creature_share_who', :name => @hero.name) ]

          gm_types("creature/share barrow hound=#{@admin.name}")
          expect(heard).to include("Barrow Hound is now for: #{@admin.name}")
        end

        it "should keep a share with every Plotmaster beside shares with named ones, and take each back alone" do
          gm_types('creature/share barrow hound=plotmasters')
          gm_types("creature/share barrow hound=#{@admin.name}")
          expect([ hound.audience, hound.shared_with ]).to eq [ 'plotmasters', [ @admin.id.to_s ] ]

          gm_types("creature/unshare barrow hound=#{@admin.name}")
          expect([ hound.audience, hound.shared_with ]).to eq [ 'plotmasters', [] ]

          gm_types('creature/unshare barrow hound=plotmasters')
          expect(hound.audience).to eq 'private'
        end

        it "should not take a word and names together" do
          gm_types("creature/share barrow hound=private,#{@admin.name}")

          expect(refused).to eq [ t('pf2e.creature_share_mixed') ]
        end

        it "should let an admin it is shared with use it unapproved, and then nobody once unshared" do
          gm_types("creature/share barrow hound=#{@admin.name}")
          expect(Creatures.find(Character[@admin.id], 'barrow hound', 'use').ok?).to be true

          gm_types("creature/unshare barrow hound=#{@admin.name}")
          expect(hound.audience).to eq 'private'
        end
      end

      it "should keep a history of who did what" do
        gm_types(HOUND)
        gm_types('creature/set barrow hound=ac 19')
        gm_types('creature/history barrow hound')

        expect(heard).to include('created', 'revised r2 - AC 18 to 19')
      end

      it "should be retired off the lists, and restored" do
        gm_types(HOUND)
        gm_types('creature/retire barrow hound')
        gm_types('+e/add barrow hound')
        expect(refused.join).to include('No creature you may use')

        gm_types('creature/restore barrow hound')
        expect(hound.status).to eq 'draft'
      end
    end
  end
end
