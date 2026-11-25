require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The pure parts of replacing a companion: which recorded choices a new type rewrites, and how the
    # replacement reads in sheet/history.
    describe "replacing an animal companion" do

      describe "the rewrite plan" do
        before(:each) do
          @recorded = [ [ 'Animal Companion', 'Wolf', 1 ], [ 'Incredible Companion (Druid)', 'Savage', 8 ],
                        [ 'Specialized Companion (Druid)', 'Racer (land)', 14 ], [ 'Specialized Companion (Druid)', 'Tracker', 16 ],
                        [ 'Additional Lore', 'Farming Lore', 2 ] ]
        end

        it "should rewrite nothing for the same build" do
          expect(Companion.rewrite_plan(@recorded, 'Animal Companion', { 'type' => nil, 'choices' => {} })).to eq []
        end

        it "should rewrite the type, the path and each specialization at the level each was made" do
          plan = Companion.rewrite_plan(@recorded, 'Animal Companion',
                                        { 'type' => 'Bird', 'choices' => { 'Incredible Companion (Druid)' => [ 'Nimble' ],
                                                                           'Specialized Companion (Druid)' => [ 'Racer (fly)', 'Ambusher' ] } })

          expect(plan).to eq [
            { 'choice' => 'Animal Companion', 'from' => 'Wolf', 'level' => 1, 'to' => 'Bird' },
            { 'choice' => 'Incredible Companion (Druid)', 'from' => 'Savage', 'level' => 8, 'to' => 'Nimble' },
            { 'choice' => 'Specialized Companion (Druid)', 'from' => 'Racer (land)', 'level' => 14, 'to' => 'Racer (fly)' },
            { 'choice' => 'Specialized Companion (Druid)', 'from' => 'Tracker', 'level' => 16, 'to' => 'Ambusher' }
          ]
        end

        it "should leave alone a choice that comes out the same" do
          plan = Companion.rewrite_plan(@recorded, 'Animal Companion',
                                        { 'type' => 'Bear', 'choices' => { 'Incredible Companion (Druid)' => [ 'Savage' ] } })

          expect(plan.map { |row| row['choice'] }).to eq [ 'Animal Companion' ]
        end
      end

      describe "in sheet/history" do
        def item(payload)
          LevelHistory::KINDS['companion_replaced']['item'].call(payload)
        end

        it "should name the old companion and its replacement" do
          expect(item('old_name' => 'Fang', 'old_type' => 'Wolf', 'new_name' => 'Ash', 'new_type' => 'Wolf'))
            .to eq 'Fang, wolf companion, replaced by Ash'
        end

        it "should name the new type when it differs" do
          expect(item('old_name' => 'Ash', 'old_type' => 'Wolf', 'new_name' => 'Bruin', 'new_type' => 'Bear'))
            .to eq 'Ash, wolf companion, replaced by Bruin, bear companion'
        end

        it "should be a ledger kind that changes nothing but its own list" do
          sheet = Ledger.empty_sheet(9)
          Ledger::KIND_SPECS['companion_replaced']['apply'].call(sheet, 'old_name' => 'Ash', 'old_type' => 'Wolf',
                                                                          'new_name' => 'Bruin', 'new_type' => 'Bear')

          expect(sheet['companion_replacements']).to eq [ { 'old_name' => 'Ash', 'old_type' => 'Wolf', 'new_name' => 'Bruin', 'new_type' => 'Bear' } ]
          expect(sheet['feats']).to eq({})
        end
      end
    end
  end
end
