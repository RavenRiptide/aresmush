require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Master abilities that add to their master's spellcasting for the day - Cantrip Connection and Spell
    # Battery - and Spellcasting's spell. A sorcerer keeps a repertoire and a wizard prepares; each took the
    # Familiar class feat and has an approved familiar.
    describe "a familiar's spell abilities", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @made = []
      end

      after(:each) do
        @made.reverse.each(&:delete)
      end

      # Ohm's `update` saves every attribute, so each write goes through a fresh copy.
      def fresh
        Character[@char.id]
      end

      def caster(charclass, level, slots, known)
        @char = Character.create(:name => "Morwen#{rand(1000000)}", :pf2_conditions => {}, :pf2_traits => [],
                                 :pf2_derived => {}, :pf2_daily_choices => {}, :pf2_lang => [ 'Kamin' ])
        combat = Pf2eCombat.create(:character => @char, :key_abil => 'Charisma')
        abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 16) }
        list = charclass == 'Sorcerer' ? :repertoire : :spellbook
        magic = PF2Magic.create(:character => @char, :tradition => { charclass => [ 'arcane', 'trained' ] },
                                :spell_abil => { charclass => 'Charisma' }, :spells_per_day => { charclass => slots },
                                list => { charclass => known }, :spells_prepared => {}, :spells_today => {})
        @made += abilities + [ combat, magic, @char ]

        fresh.update(:combat => combat, :magic => magic)
        fresh.update(:pf2_base_info => { 'charclass' => charclass }, :pf2_level => level,
                     :pf2_feats => { 'charclass' => [ 'Familiar' ] }, :pf2_features => { 'charclass_features' => [] })
        Paths.apply_all!(fresh)
        fresh.update(:pf2_familiar => { 'approved' => { 'name' => 'Smudge', 'species' => 'black cat', 'form' => 'land', 'source' => 'Familiar' } })
      end

      def sorcerer(level = 8)
        top = (level + 1) / 2
        slots = { 'cantrip' => 5 }.merge((1..top).to_h { |rank| [ rank.to_s, 3 ] })
        caster('Sorcerer', level, slots, 'cantrip' => [ 'Detect Magic' ], '1' => [ 'Fear' ], '3' => [ 'Fireball' ])
      end

      def wizard(level = 8)
        top = (level + 1) / 2
        slots = { 'cantrip' => 5 }.merge((1..top).to_h { |rank| [ rank.to_s, 2 ] })
        caster('Wizard', level, slots, 'cantrip' => [ 'Detect Magic', 'Shield' ], '1' => [ 'Fear' ])
      end

      # The day's picks as prepare/familiar stores them.
      def today(*abilities)
        text = Familiar.abilities_text(abilities)
        fresh.update(:pf2_daily_choices => { 'familiar' => { 'pick' => text, 'abilities' => abilities, 'source' => 'Familiar', 'locked' => true } })
        allow(Familiar::Daily).to receive(:today).and_return(abilities)
      end

      def answers(typed)
        Familiar::Daily.answers(fresh, nil, typed)
      end

      def slots(charclass)
        Pf2emagic::Entries.slots(fresh.magic, charclass)
      end

      describe "Spell Battery" do
        it "should add a slot 3 ranks below the highest" do
          wizard
          today({ 'name' => 'Spell Battery' })

          expect(slots('Wizard')['1']).to eq 3
          expect(slots('Wizard')['4']).to eq 2
          expect(Pf2emagic.max_spells_per_day(fresh, 'Wizard', '1')).to eq 3
        end

        it "should go no lower than 1st rank's arithmetic allows" do
          expect(Familiar::MasterSpells.battery_rank('cantrip' => 5, '1' => 3, '2' => 3, '3' => 3)).to be_nil
          expect(Familiar::MasterSpells.battery_rank('cantrip' => 5, '9' => 1, '8' => 2)).to eq 6
        end

        it "should give a spontaneous caster the slot at a rest" do
          sorcerer
          today({ 'name' => 'Spell Battery' })

          Pf2emagic.generate_spells_today(fresh)

          expect(fresh.magic.spells_today['Sorcerer']['1']).to eq 4
        end

        it "should write nothing to their slots" do
          wizard
          today({ 'name' => 'Spell Battery' })
          slots('Wizard')

          expect(fresh.magic.spells_per_day['Wizard']['1']).to eq 2
        end
      end

      describe "Cantrip Connection for a prepared caster" do
        it "should add a cantrip slot for each pick" do
          wizard
          today({ 'name' => 'Cantrip Connection' }, { 'name' => 'Cantrip Connection' })

          expect(slots('Wizard')['cantrip']).to eq 7
          expect(Pf2emagic.max_spells_per_day(fresh, 'Wizard', 'cantrip')).to eq 7
        end

        it "should take no choice, and may be picked twice" do
          wizard

          expect(answers('Cantrip Connection (Light)').code).to eq :familiar_daily_no_choice
          expect(answers('Cantrip Connection, Cantrip Connection').ok?).to be true
        end
      end

      describe "Cantrip Connection for a repertoire caster" do
        before(:each) { sorcerer }

        it "should add the named cantrip to the repertoire, but not to what they learned" do
          today({ 'name' => 'Cantrip Connection', 'choice' => 'Shield' })

          expect(Pf2emagic::Entries.known(fresh.magic, 'Sorcerer')['cantrip']).to include 'Shield'
          expect(Pf2emagic::Entries.learned(fresh.magic, 'Sorcerer')['cantrip']).not_to include 'Shield'
          expect(Pf2emagic::Entries.known_lists(fresh)['Sorcerer']['cantrip']).not_to include 'Shield'
          expect(fresh.magic.repertoire['Sorcerer']['cantrip']).to eq [ 'Detect Magic' ]
        end

        it "should need a cantrip the first time" do
          found = answers('Cantrip Connection')

          expect(found.code).to eq :familiar_cantrip_needed
          expect(found.args['list']).to include 'Shield'
          expect(found.args['list']).not_to include 'Detect Magic'
        end

        it "should take a cantrip of their tradition they don't know" do
          found = answers('Cantrip Connection (shield)')

          expect(found.ok?).to be true
          expect(found.state['abilities'].first['choice']).to eq 'Shield'
          expect(answers('Cantrip Connection (Detect Magic)').code).to eq :familiar_cantrip_known
          expect(answers('Cantrip Connection (Fear)').code).to eq :familiar_cantrip_bad
        end

        it "should remember the cantrip and reuse it" do
          Familiar::MasterSpells.remember!(fresh, answers('Cantrip Connection (Shield)').state)

          expect(Familiar.record(fresh)['cantrips']).to eq [ 'Shield' ]
          expect(answers('Cantrip Connection').state['abilities'].first['choice']).to eq 'Shield'
          expect(answers('Cantrip Connection (Shield)').ok?).to be true
          expect(answers('Cantrip Connection (Light)').code).to eq :familiar_cantrip_kept
        end

        it "should remember a second cantrip for a second pick" do
          Familiar::MasterSpells.remember!(fresh, answers('Cantrip Connection (Shield)').state)
          found = answers('Cantrip Connection, Cantrip Connection (Light)')
          Familiar::MasterSpells.remember!(fresh, found.state)

          expect(found.state['abilities'].map { |one| one['choice'] }).to eq [ 'Shield', 'Light' ]
          expect(Familiar.record(fresh)['cantrips']).to eq [ 'Shield', 'Light' ]
        end

        it "should be kept at a rest" do
          Familiar::MasterSpells.remember!(fresh, answers('Cantrip Connection (Shield)').state)

          expect(Familiar::Daily.kept?(fresh, nil, 'abilities' => [ { 'name' => 'Cantrip Connection', 'choice' => 'Shield' } ])).to be true
        end

        describe "familiar/cantrip" do
          before(:each) do
            Familiar::MasterSpells.remember!(fresh, answers('Cantrip Connection (Shield)').state)
            today({ 'name' => 'Cantrip Connection', 'choice' => 'Shield' })
          end

          def staff(text)
            said = []
            client = double
            %i{emit_failure emit_success}.each { |name| allow(client).to receive(name) { |message| said << message.to_s } }
            enactor = double(:has_permission? => true)
            allow(Pf2e).to receive(:get_character).and_return(fresh)

            cmd = PF2FamiliarCantripCmd.new(client, Command.new(text), enactor)
            cmd.parse_args
            cmd.handle
            said.join
          end

          it "should change the remembered cantrip, and today's pick with it" do
            said = staff('familiar/cantrip Morwen=Shield/Light')

            expect(said).to include t('pf2e.familiar_cantrip_changed', :name => fresh.name, :old => 'Shield', :new => 'Light')
            expect(Familiar.record(fresh)['cantrips']).to eq [ 'Light' ]
            expect(fresh.pf2_daily_choices['familiar']['abilities'].first['choice']).to eq 'Light'
            expect(fresh.pf2_daily_choices['familiar']['pick']).to include 'Light'
          end

          it "should refuse a cantrip it doesn't add" do
            said = staff('familiar/cantrip Morwen=Light/Daze')

            expect(said).to include t('pf2e.familiar_cantrip_none', :cantrip => 'Light')
            expect(Familiar.record(fresh)['cantrips']).to eq [ 'Shield' ]
          end
        end
      end

      describe "Spellcasting's spell" do
        before(:each) { sorcerer(12) }

        it "should take a spell at least 5 ranks below their highest slot" do
          expect(Familiar::MasterSpells.spellcasting_options(fresh)).to eq [ 'Fear' ]

          found = answers('Spellcasting (fear)')

          expect(found.ok?).to be true
          expect(found.state['abilities'].first['choice']).to eq 'Fear'
          expect(answers('Spellcasting (Fireball)').code).to eq :familiar_daily_choice
        end

        it "should keep the other abilities at a rest when the spell is no longer theirs" do
          expect(Familiar::Daily.kept?(fresh, nil, 'abilities' => [ { 'name' => 'Spellcasting', 'choice' => 'Fireball' } ])).to be true
        end

        it "should name its prerequisite to a caster without 6th-rank slots" do
          sorcerer(8)

          expect(answers('Spellcasting (Fear)').code).to eq :familiar_daily_prereq
        end
      end
    end
  end
end
