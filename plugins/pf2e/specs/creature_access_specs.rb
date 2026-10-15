require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Who may do what with a saved creature, as Raven set it out on 2026-10-14: anyone authors; a
    # Plotmaster or admin uses their own and what another shares with them; anyone else uses only what an
    # admin has approved, which is published for everyone; admins approve.
    describe CreatureAccess do

      def actor(kind, id = kind, approved: true)
        { 'id' => id, 'kind' => { 'player' => 'event runner', 'pm' => 'Plotmaster', 'admin' => 'staff' }[kind] || kind,
          'approved' => approved }
      end

      def row(owner: 'owner', audience: 'private', shared_with: [], published: false, retired: false, submitted: false, owner_runs_own: true)
        { 'id' => '7', 'owner_id' => owner, 'owner_runs_own' => owner_runs_own, 'audience' => audience, 'shared_with' => shared_with,
          'published' => published ? '3' : nil, 'retired' => retired, 'submitted' => submitted ? '4' : nil }
      end

      def may?(who, action, held = row)
        CreatureAccess.may(who, action, held).ok?
      end

      # Each action, by who asks, of a private creature owned by a Plotmaster and of one owned by a player.
      MATRIX = {
        #                    owner  other-pm  player  admin
        'view'    => [ true,  false,    false,  true ],
        'use'     => [ true,  false,    false,  true ],
        'clone'   => [ true,  false,    false,  true ],
        'edit'    => [ true,  false,    false,  true ],
        'share'   => [ true,  false,    false,  true ],
        'submit'  => [ true,  false,    false,  true ],
        'review'  => [ false, false,    false,  true ],
        'retire'  => [ true,  false,    false,  true ],
        'purge'   => [ false, false,    false,  true ]
      }.freeze

      MATRIX.each do |action, (owner, other, player, admin)|
        it "should let #{action} be done as the table says, for a Plotmaster's private creature" do
          held = row(:owner => 'pm1')

          expect([ may?(actor('pm', 'pm1'), action, held), may?(actor('pm', 'pm2'), action, held),
                   may?(actor('player', 'p1'), action, held), may?(actor('admin', 'a1'), action, held) ]).to eq [ owner, other, player, admin ]
        end
      end

      it "should let anyone approved create, and nobody unapproved" do
        expect(may?(actor('player', 'p1'), 'create', {})).to be true
        expect(may?(actor('player', 'p1', :approved => false), 'create', {})).to be false
      end

      describe "a player's own creature" do
        it "should be theirs to view, edit and submit, and not to use until it is published" do
          held = row(:owner => 'p1')

          expect(%w{view edit submit use}.map { |action| may?(actor('player', 'p1'), action, held) }).to eq [ true, true, true, false ]
          expect(may?(actor('player', 'p1'), 'use', row(:owner => 'p1', :published => true))).to be true
        end

        it "should be usable by its Plotmaster owner who has since stopped being one only once published" do
          held = row(:owner => 'x1')

          expect(may?(actor('player', 'x1'), 'use', held)).to be false
          expect(may?(actor('player', 'x1'), 'edit', held)).to be true
        end
      end

      describe "sharing" do
        it "should let a Plotmaster or admin it is shared with view and use it unapproved" do
          held = row(:owner => 'pm1', :audience => 'shared', :shared_with => [ 'pm2', 'a1' ])

          expect([ may?(actor('pm', 'pm2'), 'use', held), may?(actor('admin', 'a1'), 'use', held) ]).to eq [ true, true ]
          expect(may?(actor('pm', 'pm3'), 'use', held)).to be false
        end

        it "should let every Plotmaster use one shared with them all" do
          expect(may?(actor('pm', 'pm9'), 'use', row(:owner => 'pm1', :audience => 'plotmasters'))).to be true
        end

        it "should give a player named in a share nothing" do
          held = row(:owner => 'pm1', :audience => 'shared', :shared_with => [ 'p1' ])

          expect(may?(actor('player', 'p1'), 'use', held)).to be false
          expect(may?(actor('player', 'p1'), 'view', held)).to be false
        end

        it "should reach nobody from an author who may not use it unapproved themselves" do
          held = row(:owner => 'p1', :audience => 'plotmasters', :owner_runs_own => false)

          expect(may?(actor('pm', 'pm2'), 'use', held)).to be false
          expect(may?(actor('player', 'p1'), 'share', held)).to be false
          expect(may?(actor('admin', 'a1'), 'use', held)).to be true
        end

        it "should be with Plotmasters and admins only" do
          expect(CreatureAccess.shareable?(actor('pm', 'pm2'))).to be true
          expect(CreatureAccess.shareable?(actor('admin', 'a1'))).to be true
          expect(CreatureAccess.shareable?(actor('player', 'p1'))).to be false
        end
      end

      describe "a published creature" do
        it "should be viewed, used and cloned by anyone" do
          held = row(:owner => 'pm1', :published => true)

          expect(%w{view use clone}.map { |action| may?(actor('player', 'p2'), action, held) }).to eq [ true, true, true ]
          expect(may?(actor('player', 'p2'), 'edit', held)).to be false
        end

        it "should not be retired by its owner, only unpublished by an admin first" do
          held = row(:owner => 'pm1', :published => true)

          expect(may?(actor('pm', 'pm1'), 'retire', held)).to be false
          expect(may?(actor('admin', 'a1'), 'retire', held)).to be true
        end
      end

      it "should let nobody but an admin use a retired creature, or view one but its owner" do
        held = row(:owner => 'pm1', :published => true, :retired => true)

        expect(may?(actor('player', 'p2'), 'view', held)).to be false
        expect(may?(actor('pm', 'pm1'), 'use', held)).to be false
        expect(may?(actor('pm', 'pm1'), 'view', held)).to be true
      end

      describe "which revision someone gets" do
        it "should be the latest for the owner who may use it unapproved and for those it is shared with" do
          held = row(:owner => 'pm1', :audience => 'shared', :shared_with => [ 'pm2' ], :published => true)

          expect(CreatureAccess.latest?(actor('pm', 'pm1'), held)).to be true
          expect(CreatureAccess.latest?(actor('pm', 'pm2'), held)).to be true
          expect(CreatureAccess.latest?(actor('admin', 'a1'), held)).to be true
        end

        it "should be the published one for anyone else, the player who wrote it among them" do
          expect(CreatureAccess.latest?(actor('player', 'p2'), row(:owner => 'pm1', :published => true))).to be false
          expect(CreatureAccess.latest?(actor('player', 'p1'), row(:owner => 'p1', :published => true))).to be false
        end
      end

      it "should say what was refused, by its code" do
        refused = CreatureAccess.may(actor('player', 'p1'), 'edit', row(:owner => 'pm1'))

        expect([ refused.code, refused.key ]).to eq [ :creature_may_not, 'pf2e.creature_may_not' ]
        expect(refused.args['action']).to eq 'edit'
      end
    end
  end
end
