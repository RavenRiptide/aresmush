require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a pick keeps beside its name: a signature spell's swap, a lent focus spell, the scrolls to make.
    describe "daily choices that change spells" do
      describe "keeping a pick's details" do
        let(:block) { { 'source' => 'Versatile Signature', 'lasts' => 'until_changed' } }
        let(:swap) { { 'class' => 'Bard', 'rank' => '1', 'from' => 'Fear', 'to' => 'Command' } }

        it "should keep the swap through a rest" do
          picks = { 'versatile' => { 'pick' => 'Fear: Command', 'swap' => swap, 'locked' => true } }

          kept, dropped = DailyChoices.rest(picks, { 'versatile' => block }, ->(_switch, _pick) { true })

          expect(dropped).to eq []
          expect(kept['versatile']).to include('pick' => 'Fear: Command', 'swap' => swap, 'locked' => false)
        end

        it "should put back the swap a new pick replaced, when it is taken back" do
          picks = { 'versatile' => { 'pick' => 'Fear: Command', 'swap' => swap, 'locked' => false } }
          other = swap.merge('to' => 'Charm')

          chosen = DailyChoices.choose(picks, 'versatile', block, [ 'Fear: Charm' ], 'Fear: Charm', 'swap' => other)
          undone = DailyChoices.unchoose(chosen.state, 'versatile', block)

          expect(chosen.state['versatile']).to include('swap' => other, 'previous_swap' => swap)
          expect(undone.state['versatile']).to include('pick' => 'Fear: Command', 'swap' => swap)
        end
      end

      describe "laid over the entries" do
        it "should swap the signature spell in the class's entry only" do
          entry = { 'name' => 'Bard', 'category' => 'spontaneous', 'signature' => { '1' => [ 'Fear' ], '3' => [ 'Haste' ] } }
          swap = { 'class' => 'Bard', 'rank' => '1', 'from' => 'Fear', 'to' => 'Command' }

          expect(DailySpells.swapped(entry, [ swap ])['signature']).to eq('1' => [ 'Command' ], '3' => [ 'Haste' ])
          expect(DailySpells.swapped(entry.merge('name' => 'Sorcerer'), [ swap ])).to eq entry.merge('name' => 'Sorcerer')
        end

        it "should add a lent spell to the focus entry of its type" do
          entry = { 'name' => 'revelation', 'category' => 'focus', 'known' => { 'spell' => [ 'Ancestral Touch' ] } }
          lent = [ { 'type' => 'revelation', 'spell' => 'Pushing Gust' } ]

          expect(DailySpells.lent_to(entry, lent)['known']['spell']).to eq [ 'Ancestral Touch', 'Pushing Gust' ]
          expect(DailySpells.lent_to(entry.merge('name' => 'domain'), lent)['known']['spell']).to eq [ 'Ancestral Touch' ]
        end
      end

      describe "on a character", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Spells#{rand(1000000)}", :pf2_daily_choices => {}, :pf2_features => {})
          @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 16) }
          allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        end

        after(:each) do
          live = Character[@char.id]

          Pf2egear::Inventory.all(live, 'consumables').each(&:delete)
          live.spellcasting_entries.each(&:delete) if live.respond_to?(:spellcasting_entries)
          live.magic.delete if live.magic
          @abilities.each(&:delete)
          live.delete
        end

        def char
          Character[@char.id]
        end

        def caster(charclass, tradition, feats, top, extra = {}, proficiency: 'trained', specialize: nil)
          per_day = (1..top).each_with_object({ 'cantrip' => 5 }) { |rank, out| out[rank.to_s] = 2 }
          magic = PF2Magic.create({ :character => @char,
                                    :tradition => { charclass => [ tradition, proficiency ] },
                                    :spell_abil => { charclass => 'Charisma' },
                                    :spells_per_day => { charclass => per_day } }.merge(extra))

          @char.update(:magic => magic, :pf2_level => top * 2, :pf2_feats => { 'charclass' => feats },
                       :pf2_base_info => { 'charclass' => charclass, 'specialize' => specialize })

          Pf2emagic.generate_spells_today(char)
        end

        def pick(switch, typed)
          DailyChoices.pick!(char, switch, typed)
        end

        describe "Versatile Signature" do
          before(:each) do
            caster('Bard', 'occult', [ 'Versatile Signature' ], 5,
                   { :repertoire => { 'Bard' => { '1' => [ 'Fear', 'Command' ], '3' => [ 'Haste', 'Slow' ] } },
                     :signature_spells => { 'Bard' => { '1' => [ 'Fear' ], '3' => [ 'Haste' ] } } })
          end

          def signature(spell)
            Pf2emagic::Entries.signature_ranks(char.magic, 'Bard', spell)
          end

          it "should offer each signature spell swapped for another of its rank" do
            expect(DailyChoices.options(char, DailyChoices.for_switch(char, 'versatile'))).to eq [ 'Fear: Command', 'Haste: Slow' ]
          end

          it "should make the new spell a signature spell in place of the old" do
            expect(pick('versatile', 'fear: command')).to be_ok

            expect(signature('Command')).to eq [ '1' ]
            expect(signature('Fear')).to eq []
            expect(signature('Haste')).to eq [ '3' ]
          end

          it "should heighten the new signature spell when it is cast" do
            pick('versatile', 'Fear: Command')

            cast = Pf2emagic.cast_spell(char, 'Bard', 'Command', [], 3)

            expect(cast).to be_a Hash
            expect(cast['spell level']).to eq '3'
          end

          it "should refuse a spell of another rank" do
            expect(pick('versatile', 'Fear: Haste').code).to eq :not_offered
          end

          it "should hold through a rest" do
            pick('versatile', 'Fear: Command')
            DailyChoices.rested!(char)

            expect(signature('Command')).to eq [ '1' ]
          end

          it "should put the old signature spell back when it is taken back" do
            pick('versatile', 'Fear: Command')
            DailyChoices.unpick!(char, 'versatile')

            expect(signature('Fear')).to eq [ '1' ]
            expect(signature('Command')).to eq []
          end

          it "should not change what the sheet records" do
            pick('versatile', 'Fear: Command')

            expect(char.magic.signature_spells['Bard']['1']).to eq [ 'Fear' ]
          end
        end

        describe "Paradoxical Mystery" do
          before(:each) do
            caster('Oracle', 'divine', [ 'Paradoxical Mystery' ], 9, {}, :specialize => 'Ancestors')
            Pf2emagic::Entries.grant_focus!(char, 'revelation', [ 'Ancestral Touch' ], :kind => 'spell')
          end

          def offered
            DailyChoices.options(char, DailyChoices.for_switch(char, 'paradox'))
          end

          it "should offer domain spells and other mysteries' revelation spells, not their own" do
            expect(offered).to include('Pushing Gust', 'Disperse into Air', 'Weapon Trance', 'Battlefield Persistence')
            expect(offered).to_not include('Ancestral Touch', 'Ancestral Defense')
          end

          it "should offer Player Core's domains and their mystery's, but no other domain" do
            # Soul is one of the Ancestors mystery's domains; Time is from another book and not theirs.
            expect(offered).to include('Eject Soul', 'Ectoplasmic Interstice')
            expect(offered).to_not include('Delay Consequence', 'Stasis')
          end

          it "should offer another domain they have a spell of" do
            Pf2emagic::Entries.grant_focus!(char, 'domain', [ 'Share Burden' ], :kind => 'spell')

            expect(offered).to include('Font of Serenity')
          end

          it "should lend the spell as a revelation spell until the next rest" do
            expect(pick('paradox', 'Pushing Gust')).to be_ok

            expect(Pf2emagic::Entries.focus_spells(char.magic, 'revelation')).to include('Ancestral Touch', 'Pushing Gust')
            expect(Pf2emagic.focus_pool_max(char.magic)).to eq 2

            DailyChoices.rested!(char)

            expect(Pf2emagic::Entries.focus_spells(char.magic, 'revelation')).to eq [ 'Ancestral Touch' ]
          end

          it "should not write the spell to the sheet" do
            pick('paradox', 'Pushing Gust')

            expect(Pf2emagic::Entries.stored(char).flat_map { |row| Array((row['known'] || {})['spell']) }).to_not include('Pushing Gust')
          end
        end

        describe "Scroll Adept" do
          def wizard(proficiency = 'trained')
            caster('Wizard', 'arcane', [ 'Scroll Adept' ], 7,
                   { :spellbook => { 'Wizard' => { '1' => [ 'Fear' ], '3' => [ 'Fireball', 'Haste' ] } } }, :proficiency => proficiency)
          end

          def scrolls
            Pf2egear::Inventory.all(char, 'consumables').select { |item| item.granted_by == 'daily:scrolladept' }
          end

          it "should make the scrolls at a rest, worth nothing and gone at the next" do
            wizard
            expect(pick('scrolladept', 'Fear 1, fireball 5')).to be_ok

            DailyChoices.brew!(char)

            made = scrolls.map { |item| [ item.spell, item.spell_rank.to_i, item.price.to_i, item.expires ] }
            expect(made).to contain_exactly([ 'Fear', 1, 0, 'rest' ], [ 'Fireball', 5, 0, 'rest' ])
          end

          it "should make them again at each rest, not twice over" do
            wizard
            pick('scrolladept', 'Fear 1, Fireball 5')

            2.times { DailyChoices.brew!(char) }

            expect(scrolls.size).to eq 2
          end

          it "should make two at trained and three at master" do
            wizard
            expect(pick('scrolladept', 'Fear 1, Fireball 3, Haste 4').code).to eq :scroll_adept_how_many

            char.magic.update(:tradition => { 'Wizard' => [ 'arcane', 'master' ] })

            expect(pick('scrolladept', 'Fear 1, Fireball 3, Haste 4')).to be_ok
          end

          it "should refuse two of one rank, a rank too high, and a spell outside the spellbook" do
            wizard

            expect(pick('scrolladept', 'Fireball 3, Haste 3').code).to eq :scroll_adept_same_rank
            expect(pick('scrolladept', 'Fireball 6').code).to eq :scroll_adept_bad_rank
            expect(pick('scrolladept', 'Heal 3').code).to eq :scroll_adept_not_offered
            expect(pick('scrolladept', 'Fireball').code).to eq :scroll_adept_say_rank
          end

          it "should keep the pick through a rest" do
            wizard
            pick('scrolladept', 'Fear 1, Fireball 5')
            DailyChoices.rested!(char)

            expect(DailyChoices.pick(char, 'scrolladept')).to eq 'Fear 1, Fireball 5'
          end
        end
      end
    end
  end
end
