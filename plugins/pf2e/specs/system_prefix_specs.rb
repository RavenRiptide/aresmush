require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The prefix that marks what the game tells, at the level each player sets with `rollprefix`.
    describe SystemPrefix do

      def told
        'Aria strikes Goblin: hit.%r  Damage to Goblin: 6.%RAria strikes Goblin: miss.'
      end

      before(:each) do
        allow(Global).to receive(:read_config).with('pf2e', 'system_prefix').and_return('[PF]')
        allow(Global).to receive(:read_config).with('pf2e', 'system_prefix_level').and_return('actions')
      end

      def player(level)
        double(:pf2_roll_prefix => level)
      end

      describe "marking" do
        it "should mark each line of an action at `actions`, but not one indented under another" do
          expect(SystemPrefix.marked(told, 'action', 'actions'))
            .to eq '[PF] Aria strikes Goblin: hit.%r  Damage to Goblin: 6.%R[PF] Aria strikes Goblin: miss.'
        end

        it "should leave the bookkeeping alone at `actions`" do
          expect(SystemPrefix.marked('Aria joins encounter 3.', 'system', 'actions')).to eq 'Aria joins encounter 3.'
        end

        it "should mark every line at `all`, the indented ones and the bookkeeping too" do
          expect(SystemPrefix.marked(told, 'action', 'all'))
            .to eq '[PF] Aria strikes Goblin: hit.%r[PF]   Damage to Goblin: 6.%R[PF] Aria strikes Goblin: miss.'
          expect(SystemPrefix.marked('Aria joins encounter 3.', 'system', 'all')).to eq '[PF] Aria joins encounter 3.'
        end

        it "should mark nothing at `off`, for an encounter notice, or when the game has no prefix" do
          expect(SystemPrefix.marked(told, 'action', 'off')).to eq told
          expect(SystemPrefix.marked(told, nil, 'all')).to eq told
          expect(SystemPrefix.marked(told, 'action', 'all', '')).to eq told
        end
      end

      describe "a player's level" do
        it "should be their own, or the game's when they have none or name one there is not" do
          expect(SystemPrefix.level_of(player('all'))).to eq 'all'
          expect(SystemPrefix.level_of(player(nil))).to eq 'actions'
          expect(SystemPrefix.level_of(player('loud'))).to eq 'actions'
          expect(SystemPrefix.level_of(nil)).to eq 'actions'
        end
      end

      describe "telling a room" do
        def client(level)
          double(:char => player(level))
        end

        it "should tell the room once when everyone in it would hear the same" do
          room = double(:clients => [ client(nil), client('actions') ])
          expect(room).to receive(:emit).with('[PF] Aria joins.').never
          expect(room).to receive(:emit).with('Aria joins.')

          SystemPrefix.emit(room, 'Aria joins.', 'system')
        end

        it "should tell each player the line marked at their own level when they differ" do
          loud = client('all')
          quiet = client('off')
          room = double(:clients => [ loud, quiet ])
          allow(Game).to receive(:master).and_return(double(:quiet_room => nil))

          expect(loud).to receive(:emit).with('[PF] Aria joins.')
          expect(quiet).to receive(:emit).with('Aria joins.')

          SystemPrefix.emit(room, 'Aria joins.', 'system')
        end
      end

      describe "rollprefix" do
        def typed(text, enactor, client)
          handler = PF2RollPrefixCmd.new(client, Command.new(text), enactor)
          handler.parse_args
          handler.handle
        end

        it "should set the player's level" do
          enactor = player(nil)
          client = double

          expect(enactor).to receive(:update).with(:pf2_roll_prefix => 'all')
          expect(client).to receive(:emit_success).with(t('pf2e.rollprefix_set', :prefix => '[PF]', :level => 'all'))

          typed('rollprefix ALL', enactor, client)
        end

        it "should refuse a level there is not, and change nothing" do
          enactor = player(nil)
          client = double

          expect(enactor).to_not receive(:update)
          expect(client).to receive(:emit_failure)

          typed('rollprefix loud', enactor, client)
        end

        it "should say the level the player has now" do
          client = double

          expect(client).to receive(:emit_ooc).with(t('pf2e.rollprefix_now', :prefix => '[PF]', :level => 'actions', :options => 'all|actions|off'))

          typed('rollprefix', player(nil), client)
        end
      end

      describe "a scene pose" do
        def pose(told, line, now = nil)
          double(:system_text => told, :system_line => line, :pose => now || SystemPrefix.kept(told, line))
        end

        it "should be marked at the viewer's level" do
          expect(SystemPrefix.pose_text(pose('Aria joins.', 'system'), player('all'))).to eq '[PF] Aria joins.'
          expect(SystemPrefix.pose_text(pose('Aria strikes.', 'action'), player('off'))).to eq 'Aria strikes.'
        end

        it "should be shown as edited once someone has edited it" do
          expect(SystemPrefix.pose_text(pose('Aria strikes.', 'action', 'Aria strikes hard.'), player('all'))).to eq 'Aria strikes hard.'
        end
      end
    end
  end
end
