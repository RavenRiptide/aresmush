require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Ten minutes spent changing a prepared spell after daily preparations (PreparedSwaps): Call of the Wild,
    # Elemental Summons, Rites of Convocation, the Spell Substitution thesis and Reprepare Spell.
    describe "changing a prepared spell after daily preparations" do

      describe "the record of the day's changes" do
        today = { 'Wizard' => { '1' => [ 'Fear', 'Fear' ] } }

        it "should replace one copy and record the swap" do
          out = PreparedSwaps.changed(today, 'Wizard', '1', 'Fear', 'Force Barrage', false)

          expect(out['Wizard']['1']).to eq [ 'Fear', 'Force Barrage' ]
          expect(out[PreparedSwaps::TODAY]['Wizard']).to eq [ { 'rank' => '1', 'from' => 'Fear', 'to' => 'Force Barrage', 'no_duration' => false } ]
          expect(today['Wizard']['1']).to eq [ 'Fear', 'Fear' ]
        end

        it "should add a spell to a spent slot without taking another out" do
          out = PreparedSwaps.changed(today, 'Wizard', '1', 'Charm', 'Charm', false, spent: true)

          expect(out['Wizard']['1']).to eq [ 'Fear', 'Fear', 'Charm' ]
          expect(out[PreparedSwaps::TODAY]).to be_nil
        end

        it "should count a spell swapped away as not cast, and one swapped in as prepared" do
          out = PreparedSwaps.changed(today, 'Wizard', '1', 'Fear', 'Force Barrage', false)

          expect(PreparedSwaps.expected([ 'Fear', 'Fear' ], out, 'Wizard', '1', 'Fear')).to eq 1
          expect(PreparedSwaps.expected([ 'Fear', 'Fear' ], out, 'Wizard', '1', 'Force Barrage')).to eq 1
          expect(Pf2e::BondedItem.cast_today({ 'Wizard' => { '1' => [ 'Fear', 'Fear' ] } }, out, 'Fear')).to be_nil
        end

        it "should hold a slot to spells without a duration only while every copy left is in such a slot" do
          held = PreparedSwaps.changed({ 'Wizard' => { '1' => [ 'Force Barrage' ] } }, 'Wizard', '1', 'Fear', 'Force Barrage', true, spent: true)

          expect(PreparedSwaps.restricted?(held, 'Wizard', '1', 'Force Barrage')).to eq false

          one = PreparedSwaps.changed({ 'Wizard' => { '1' => [] } }, 'Wizard', '1', 'Fear', 'Force Barrage', true, spent: true)

          expect(PreparedSwaps.restricted?(one, 'Wizard', '1', 'Force Barrage')).to eq true

          moved = PreparedSwaps.changed(one, 'Wizard', '1', 'Force Barrage', 'Breathe Fire', true)

          expect(PreparedSwaps.restricted?(moved, 'Wizard', '1', 'Breathe Fire')).to eq true
          expect(PreparedSwaps.restricted?(moved, 'Wizard', '1', 'Force Barrage')).to eq false
        end
      end

      describe "on a character", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Swap#{rand(1000000)}")
        end

        after(:each) do
          live = Character[@char.id]

          live.spellcasting_entries.each(&:delete) if live.respond_to?(:spellcasting_entries)
          live.magic.delete if live.magic
          live.delete
        end

        def char
          Character[@char.id]
        end

        # A prepared caster with 2 slots at each rank to `top`, the spells prepared, rested.
        def caster(charclass, tradition, feats, prepared, top: 5, book: nil, thesis: nil, choices: nil)
          per_day = (1..top).each_with_object({}) { |rank, out| out[rank.to_s] = 2 }
          magic = PF2Magic.create({ :character => @char,
                                    :tradition => { charclass => [ tradition, 'trained' ] },
                                    :spell_abil => { charclass => 'Intelligence' },
                                    :spells_per_day => { charclass => per_day },
                                    :spells_prepared => { charclass => prepared } }.merge(book ? { :spellbook => { charclass => book } } : {}))

          @char.update(:magic => magic, :pf2_level => top * 2, :pf2_feats => { 'charclass' => feats },
                       :pf2_base_info => { 'charclass' => charclass, 'specialize_info' => thesis.to_s },
                       :pf2_level_tracker => choices ? { '4' => { 'feat_choices' => choices } } : {})

          Pf2emagic.generate_spells_today(char)
        end

        def today(charclass, rank)
          Array((char.magic.spells_today[charclass] || {})[rank.to_s])
        end

        def swap(from, to, rank = nil)
          PreparedSwaps.swap(char, from, to, rank)
        end

        def cast(charclass, spell, rank = nil)
          Pf2emagic.cast_spell(char, charclass, spell, [], rank)
        end

        describe "Call of the Wild" do
          before(:each) { caster('Druid', 'primal', [ 'Call of the Wild' ], { '1' => [ 'Heal', 'Heal' ] }) }

          it "should replace a prepared spell with a summon at the same rank" do
            outcome = swap('Heal', 'Summon Animal')

            expect(outcome.state).to include('source' => 'Call of the Wild', 'rank' => '1', 'to' => 'Summon Animal')
            expect(today('Druid', 1)).to eq [ 'Heal', 'Summon Animal' ]
          end

          it "should cast the summon it put in the slot" do
            swap('Heal', 'Summon Plant or Fungus')

            expect(cast('Druid', 'Summon Plant or Fungus')).to be_a Hash
          end

          it "should refuse a spell the feat does not name" do
            expect(swap('Heal', 'Fear').code).to eq :swap_not_offered
          end

          it "should refuse a spell not prepared today" do
            expect(swap('Fear', 'Summon Animal').code).to eq :swap_not_prepared
          end
        end

        it "should refuse a character with nothing that swaps" do
          caster('Druid', 'primal', [], { '1' => [ 'Heal' ] })

          expect(swap('Heal', 'Summon Animal').code).to eq :swap_no_source
        end

        it "should swap a druid's spell for a summon elemental of the same rank (Elemental Summons)" do
          caster('Druid', 'primal', [ 'Elemental Summons' ], { '2' => [ 'Dispel Magic' ] })

          expect(swap('Dispel Magic', 'Summon Elemental')).to be_ok
          expect(today('Druid', 2)).to eq [ 'Summon Elemental' ]
        end

        describe "Rites of Convocation" do
          before(:each) do
            caster('Witch', 'occult', [ 'Rites of Convocation' ], { '1' => [ 'Command' ] },
                   :choices => { 'Rites of Convocation' => [ 'Summon Undead' ] })
          end

          it "should swap for the summon spell chosen with the feat" do
            expect(swap('Command', 'Summon Undead')).to be_ok
            expect(today('Witch', 1)).to eq [ 'Summon Undead' ]
          end

          # The familiar need not know it: the feat puts the chosen spell in the slot.
          it "should swap for it though their familiar does not know it" do
            char.magic.update(:spellbook => { 'Witch' => { '1' => [ 'Command' ] } })

            expect(swap('Command', 'Summon Undead')).to be_ok
          end

          it "should refuse a summon spell not chosen" do
            expect(swap('Command', 'Summon Fey').code).to eq :swap_not_offered
          end

          it "should offer the summon spells of their tradition" do
            pool = Pf2e.choice_spell_pool(char, { 'traits' => [ 'summon' ], 'tradition' => 'own' })

            expect(pool).to include('Summon Undead', 'Summon Fey', 'Phantasmal Minion')
            expect(pool).to_not include('Summon Animal', 'Summon Celestial')
          end
        end

        describe "Spell Substitution" do
          book = { '1' => [ 'Fear', 'Force Barrage', 'Breathe Fire' ], '3' => [ 'Fireball', 'Haste' ] }

          before(:each) do
            caster('Wizard', 'arcane', [], { '1' => [ 'Fear' ], '3' => [ 'Fireball' ] }, :book => book,
                   :thesis => 'Spell Substitution')
          end

          it "should swap a prepared spell for any spellbook spell of that rank" do
            expect(swap('Fireball', 'Haste').state).to include('source' => 'Spell Substitution', 'rank' => '3')
            expect(today('Wizard', 3)).to eq [ 'Haste' ]
          end

          it "should refuse a spell not in the spellbook" do
            expect(swap('Fear', 'Charm').code).to eq :not_preparable
          end

          it "should swap at the rank asked for" do
            magic = char.magic
            magic.update(:spells_today => magic.spells_today.merge('Wizard' => { '1' => [ 'Fear' ], '3' => [ 'Fear', 'Fireball' ] }))

            expect(swap('Fear', 'Haste', '3')).to be_ok
            expect(today('Wizard', 1)).to eq [ 'Fear' ]
          end
        end

        describe "in an encounter" do
          before(:each) do
            caster('Druid', 'primal', [ 'Call of the Wild' ], { '1' => [ 'Heal' ] })
            @encounter = PF2Encounter.create(:organizer => 'Gm', :round => 1, :is_active => true)
            @state = Pf2eCombatantState.create(:character => char, :encounter => @encounter,
                                               :spells_today => char.magic.spells_today)
            char.encounters.add @encounter
          end

          after(:each) do
            @state.delete
            PF2Encounter[@encounter.id]&.delete
          end

          def standing
            Pf2e::CombatantStates.of(PF2Encounter[@encounter.id], char)
          end

          it "should refuse in a fight" do
            expect(swap('Heal', 'Summon Animal').code).to eq :swap_in_fight
          end

          it "should swap the encounter's spells while exploring, and leave their own alone" do
            PF2Encounter[@encounter.id].update(:mode => Pf2e::Exploration::MODE)

            expect(swap('Heal', 'Summon Animal')).to be_ok
            expect(standing.magic.spells_today['Druid']['1']).to eq [ 'Summon Animal' ]
            expect(today('Druid', 1)).to eq [ 'Heal' ]
          end
        end

        describe "Reprepare Spell" do
          def wizard(thesis = nil)
            book = { '1' => [ 'Fear', 'Force Barrage', 'Breathe Fire' ], '3' => [ 'Fireball', 'Haste' ], '5' => [ 'Howling Blizzard' ] }
            caster('Wizard', 'arcane', [ 'Reprepare Spell' ],
                   { '1' => [ 'Fear', 'Force Barrage' ], '3' => [ 'Fireball' ], '5' => [ 'Howling Blizzard' ] },
                   :book => book, :thesis => thesis)
          end

          def reprepare(spell, to = nil)
            PreparedSwaps.reprepare(char, spell, to)
          end

          it "should prepare again a spell cast today, again and again" do
            wizard

            2.times do
              cast('Wizard', 'Force Barrage', 1)
              expect(reprepare('Force Barrage')).to be_ok
              expect(today('Wizard', 1)).to include('Force Barrage')
            end
          end

          it "should refuse a spell not cast today" do
            wizard

            expect(reprepare('Force Barrage').code).to eq :reprepare_not_cast
          end

          it "should refuse a spell with a duration" do
            wizard
            cast('Wizard', 'Fear', 1)

            expect(reprepare('Fear').code).to eq :reprepare_has_duration
          end

          it "should refuse a spell above 4th rank" do
            wizard
            cast('Wizard', 'Howling Blizzard', 5)

            expect(reprepare('Howling Blizzard').code).to eq :reprepare_rank_too_high
          end

          it "should refuse a different spell without Spell Substitution" do
            wizard
            cast('Wizard', 'Force Barrage', 1)

            expect(reprepare('Force Barrage', 'Breathe Fire').code).to eq :reprepare_needs_thesis
          end

          # A spell swapped away was never cast, so it is not there to prepare again.
          it "should not prepare again a spell that was swapped away rather than cast" do
            wizard('Spell Substitution')
            swap('Fear', 'Breathe Fire')

            expect(reprepare('Fear').code).to eq :reprepare_not_cast
          end

          describe "with Spell Substitution" do
            before(:each) do
              wizard('Spell Substitution')
              cast('Wizard', 'Fear', 1)
            end

            it "should put a different spell without a duration in the expended slot" do
              expect(reprepare('Fear', 'Breathe Fire').state).to include('from' => 'Fear', 'to' => 'Breathe Fire', 'rank' => '1')
              expect(today('Wizard', 1)).to eq [ 'Force Barrage', 'Breathe Fire' ]
            end

            it "should refuse a different spell with a duration" do
              expect(reprepare('Fear', 'Fear').code).to eq :reprepare_has_duration
            end

            it "should hold that slot to spells without a duration through a later swap" do
              reprepare('Fear', 'Breathe Fire')

              # Their other rank-1 slot is not held to spells without a duration.
              swap('Force Barrage', 'Fear')

              expect(swap('Breathe Fire', 'Fear').code).to eq :swap_no_duration_slot
              expect(swap('Breathe Fire', 'Force Barrage')).to be_ok
            end
          end
        end
      end
    end
  end
end
