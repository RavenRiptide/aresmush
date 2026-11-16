require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Spellcasting rides the level ladder: what a source casts at, innate spells and slot counts are
    # grants, so a rollback takes back what a level added and a redo gives it back. Anything the ledger
    # never recorded is left alone, as focus spells are.
    describe "spellcasting in the ledger" do

      def grant(seq, kind, payload, level: 2, reverted: nil)
        { 'seq' => seq, 'txn' => "t#{seq}", 'kind' => kind, 'payload' => payload,
          'source_type' => 'level_up', 'effective_level' => level, 'reverted_by' => reverted }
      end

      def casting(source, tradition: 'occult', proficiency: 'trained', ability: 'Wisdom')
        { 'source' => source, 'tradition' => tradition, 'proficiency' => proficiency, 'ability' => ability }
      end

      def innate(name, level: 'cantrip', tradition: 'arcane', cast_stat: 'Charisma')
        { 'name' => name, 'level' => level, 'tradition' => tradition, 'cast_stat' => cast_stat }
      end

      def slots(source, rank, to, restriction: nil)
        payload = { 'source' => source, 'rank' => rank, 'to' => to }
        payload['restriction'] = restriction if restriction
        payload
      end

      def spell_ops(sheet_parts, current)
        Ledger.plan(Ledger.empty_sheet(4).merge(sheet_parts), current)
          .select { |op| %w{set_casting set_innate set_slots}.include?(op['op']) }
      end

      describe :fold do
        it "should keep the latest casting record per source" do
          sheet = Ledger.fold([ grant(1, 'casting', casting('Wizard', tradition: 'arcane', ability: 'Intelligence'), level: 1),
                                grant(2, 'casting', casting('Wizard', tradition: 'arcane', proficiency: 'expert', ability: 'Intelligence'), level: 7) ],
                              at_level: 7)

          expect(sheet['casting']).to eq('Wizard' => casting('Wizard', tradition: 'arcane', proficiency: 'expert', ability: 'Intelligence'))
        end

        it "should bring back the earlier proficiency below the raise" do
          sheet = Ledger.fold([ grant(1, 'casting', casting('Wizard'), level: 1),
                                grant(2, 'casting', casting('Wizard', proficiency: 'expert'), level: 7) ], at_level: 6)

          expect(sheet['casting']['Wizard']['proficiency']).to eq 'trained'
        end

        it "should hold one innate record per grant, a rank as a number" do
          sheet = Ledger.fold([ grant(1, 'innate_spell', innate('open')), grant(2, 'innate_spell', innate('open')),
                                grant(3, 'innate_spell', innate('Charm', level: '1')) ], at_level: 4)

          expect(sheet['innate']).to eq [ innate('open'), innate('open'), innate('Charm', level: 1) ]
        end

        it "should set slot counts, the latest per rank winning, restricted ones apart" do
          sheet = Ledger.fold([ grant(1, 'spell_slots', slots('Wizard', '1', 2), level: 1),
                                grant(2, 'spell_slots', slots('Wizard', '1', 3), level: 3),
                                grant(3, 'spell_slots', slots('Wizard', '1', 1, restriction: 'curriculum'), level: 1) ],
                              at_level: 3)

          expect(sheet['slots']).to eq('Wizard' => { '1' => 3 })
          expect(sheet['restricted_slots']).to eq('Wizard' => { 'curriculum' => { '1' => 1 } })
        end
      end

      describe "planning a materialise" do
        it "should take off a recorded source the fold no longer has" do
          planned = spell_ops({}, 'casting' => { 'Monk' => casting('Monk') }, 'casting_recorded' => [ 'Monk' ])

          expect(planned).to eq [ { 'op' => 'set_casting', 'set' => [], 'remove' => [ 'Monk' ] } ]
        end

        it "should leave alone a source the ledger never recorded" do
          expect(spell_ops({}, 'casting' => { 'Monk' => casting('Monk') }, 'casting_recorded' => [])).to eq []
        end

        it "should write back a source whose record differs" do
          planned = spell_ops({ 'casting' => { 'Wizard' => casting('Wizard') } },
                              'casting' => { 'Wizard' => casting('Wizard', proficiency: 'expert') }, 'casting_recorded' => [ 'Wizard' ])

          expect(planned).to eq [ { 'op' => 'set_casting', 'set' => [ casting('Wizard') ], 'remove' => [] } ]
        end

        it "should take off one copy of a recorded innate spell, and leave an unrecorded one" do
          planned = spell_ops({ 'innate' => [ innate('Charm') ] },
                              'innate' => [ innate('Charm'), innate('Charm'), innate('Light') ],
                              'innate_recorded' => [ innate('Charm') ])

          expect(planned).to eq [ { 'op' => 'set_innate', 'add' => [], 'remove' => [ innate('Charm') ] } ]
        end

        it "should put back an innate spell the character lacks" do
          planned = spell_ops({ 'innate' => [ innate('Charm', level: 1) ] }, 'innate' => [], 'innate_recorded' => [])

          expect(planned).to eq [ { 'op' => 'set_innate', 'add' => [ innate('Charm', level: 1) ], 'remove' => [] } ]
        end

        it "should set slots to the fold's counts and drop recorded ranks it no longer has" do
          planned = spell_ops({ 'slots' => { 'Wizard' => { '1' => 3 } } },
                              'slots' => { 'Wizard' => { '1' => 3, '2' => 2 } },
                              'slots_recorded' => [ [ 'Wizard', '', '1' ], [ 'Wizard', '', '2' ] ])

          expect(planned).to eq [ { 'op' => 'set_slots', 'per_day' => { 'Wizard' => { '1' => 3 } }, 'restricted' => {} } ]
        end

        it "should keep slots the ledger never recorded" do
          planned = spell_ops({ 'slots' => { 'Wizard' => { '1' => 2 } } },
                              'slots' => { 'Wizard' => { '1' => 3 }, 'Old' => { '1' => 1 } },
                              'slots_recorded' => [ [ 'Wizard', '', '1' ] ])

          expect(planned.first['per_day']).to eq('Wizard' => { '1' => 2 }, 'Old' => { '1' => 1 })
        end

        it "should plan nothing when the character matches the fold, whatever the key types" do
          planned = spell_ops({ 'casting' => { 'Wizard' => casting('Wizard') }, 'slots' => { 'Wizard' => { '1' => 2 } },
                                'innate' => [ innate('Charm', level: 1) ] },
                              'casting' => { 'Wizard' => casting('Wizard') }, 'casting_recorded' => [ 'Wizard' ],
                              'slots' => { 'Wizard' => { 1 => 2 } }, 'slots_recorded' => [ [ 'Wizard', '', '1' ] ],
                              'innate' => [ innate('Charm', level: '1') ], 'innate_recorded' => [ innate('Charm', level: 1) ])

          expect(planned).to eq []
        end

        it "should plan nothing while a draft is open" do
          sheet = Ledger.empty_sheet(4).merge('casting' => { 'Wizard' => casting('Wizard') })

          expect(Ledger.plan(sheet, { 'casting' => {}, 'casting_recorded' => [ 'Wizard' ] }, :draft => true)).to eq []
        end
      end

      # What a level-up commit records: the difference between the character and the fold.
      describe :sync_plan do
        it "should record a new casting source and a changed one" do
          sheet = Ledger.empty_sheet(1).merge('casting' => { 'Wizard' => casting('Wizard') })
          plan = Ledger.sync_plan(sheet, 'casting' => { 'Wizard' => casting('Wizard', proficiency: 'expert'), 'Monk' => casting('Monk') })

          expect(plan['grants']).to eq [ { 'kind' => 'casting', 'payload' => casting('Wizard', proficiency: 'expert') },
                                         { 'kind' => 'casting', 'payload' => casting('Monk') } ]
        end

        it "should revoke every grant of a source gone" do
          sheet = Ledger.empty_sheet(1).merge('casting' => { 'Monk' => casting('Monk') })

          expect(Ledger.sync_plan(sheet, 'casting' => {})['revocations']).to eq [ { 'kind' => 'casting', 'match' => { 'source' => 'Monk' } } ]
        end

        it "should record each innate grant added, counting copies" do
          sheet = Ledger.empty_sheet(1).merge('innate' => [ innate('open') ])
          plan = Ledger.sync_plan(sheet, 'innate' => [ innate('open'), innate('open') ])

          expect(plan['grants']).to eq [ { 'kind' => 'innate_spell', 'payload' => innate('open') } ]
        end

        it "should record a slot count as the total a delta produced" do
          sheet = Ledger.empty_sheet(1).merge('slots' => { 'Cleric' => { '1' => 2 } })
          plan = Ledger.sync_plan(sheet, 'slots' => { 'per_day' => { 'Cleric' => { '1' => 3, 'cantrip' => 5 } },
                                                      'restricted' => { 'Cleric' => { 'curriculum' => { '1' => 1 } } } })

          expect(plan['grants']).to eq [ { 'kind' => 'spell_slots', 'payload' => slots('Cleric', '1', 3) },
                                         { 'kind' => 'spell_slots', 'payload' => slots('Cleric', 'cantrip', 5) },
                                         { 'kind' => 'spell_slots', 'payload' => slots('Cleric', '1', 1, restriction: 'curriculum') } ]
        end

        it "should revoke a rank gone, matching only its own kind of slot" do
          sheet = Ledger.empty_sheet(1).merge('slots' => { 'Cleric' => { '1' => 2 } })
          plan = Ledger.sync_plan(sheet, 'slots' => { 'per_day' => {}, 'restricted' => {} })

          expect(plan['revocations']).to eq [ { 'kind' => 'spell_slots', 'match' => { 'source' => 'Cleric', 'rank' => '1', 'restriction' => nil } } ]
        end
      end

      it "should match an ordinary slot revocation to ordinary slots only" do
        grants = [ grant(1, 'spell_slots', slots('Wizard', '1', 2)), grant(2, 'spell_slots', slots('Wizard', '1', 1, restriction: 'curriculum')) ]

        found = Ledger.matching_grants(grants, 'spell_slots', 'source' => 'Wizard', 'rank' => '1', 'restriction' => nil)

        expect(found.map { |g| g['seq'] }).to eq [ 1 ]
      end
    end
  end
end
