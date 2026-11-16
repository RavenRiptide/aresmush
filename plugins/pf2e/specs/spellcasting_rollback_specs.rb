require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Spellcasting on the level ladder: a rollback takes back the casting source, innate spell or slots
    # a level gave, all of a source at once, and a redo gives them back. What the ledger never recorded
    # is left alone.
    describe "spellcasting and rollback", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = AutoBuilder::CaptureClient.new
        @made = []
      end

      after(:each) do
        @made.each { |c| Character[c.id]&.delete }
      end

      def approved(charclass)
        char = Character.create(:name => "Cast#{rand(1000000)}")
        @made << char

        AutoBuilder.new(char).build_level_one(charclass)
        Roles.add_role(char, 'approved')
        Ledger.commit_chargen!(Character[char.id])

        Character[char.id]
      end

      def magic(char)
        Character[char.id].magic
      end

      def cells(char)
        Ledger.slot_cells(magic(char).spells_per_day, magic(char).restricted_slots)
      end

      # What a level's choices do to the magic object, then the commit that ends the level.
      def level_up(char, level, stats_by_source)
        stats_by_source.each_pair do |source, stats|
          PF2Magic.update_magic(Character[char.id], source, stats, @client)
        end

        Character[char.id].update(:pf2_level => level)
        Ledger.commit_level_up!(Character[char.id], level, :cost => 0)
      end

      def casts_from?(char, source)
        Pf2emagic::Entries.casting(magic(char)).any? { |e| e['name'].to_s.casecmp?(source) }
      end

      def class_rows(char, source)
        Character[char.id].spellcasting_entries.to_a.select do |row|
          row.name.to_s.casecmp?(source) && ![ 'focus', 'innate' ].include?(row.category.to_s)
        end
      end

      it "should record chargen's casting and slots" do
        char = approved('Cleric')
        kinds = Character[char.id].grants.to_a.map(&:kind)

        expect(kinds).to include('casting', 'spell_slots')
        expect(Ledger.explain_for(char, :kind => 'casting', :key => 'Cleric').size).to eq 1
      end

      it "should materialise a freshly approved caster without changing anything" do
        char = approved('Wizard')
        before = [ magic(char).tradition, magic(char).spell_abil, cells(char) ]

        Ledger.invalidate!(char)
        Ledger.materialize!(Character[char.id])

        expect([ magic(char).tradition, magic(char).spell_abil, cells(char) ]).to eq before
      end

      # Qi Spells: the tradition and attribute Qi Tradition gives, and the qi spell.
      it "should leave a monk rolled back past Qi Spells no caster at all, and a redo restore it" do
        char = approved('Monk')

        level_up(char, 2, 'Monk' => { 'tradition' => { 'occult' => 'trained' }, 'spell_abil' => 'Wisdom',
                                      'focus_spell' => { 'qi' => [ 'Inner Upheaval' ] } })
        expect(casts_from?(char, 'Monk')).to be true

        expect(Pf2e.rollback_to_level(Character[char.id], 2)).to be_nil

        expect(magic(char).tradition.keys).not_to include('Monk')
        expect(magic(char).spell_abil.keys).not_to include('Monk')
        expect(casts_from?(char, 'Monk')).to be false
        expect(Pf2emagic::Entries.focus_spells(magic(char), 'qi')).to eq []

        expect(Pf2e.redo_rollback(Character[char.id])).to be_nil

        expect(magic(char).tradition['Monk']).to eq [ 'occult', 'trained' ]
        expect(magic(char).spell_abil['Monk']).to eq 'Wisdom'
        expect(casts_from?(char, 'Monk')).to be true
      end

      it "should take a dedication's casting, slots and entry row back together" do
        char = approved('Cleric')

        level_up(char, 2, 'Wizard Archetype' => { 'tradition' => { 'arcane' => 'trained' }, 'spell_abil' => 'Intelligence',
                                                  'spells_per_day' => { 'cantrip' => 2 } })
        expect(class_rows(char, 'Wizard Archetype').size).to eq 1

        Pf2e.rollback_to_level(Character[char.id], 2)

        expect(casts_from?(char, 'Wizard Archetype')).to be false
        expect(magic(char).spells_per_day.keys).not_to include('Wizard Archetype')
        expect(class_rows(char, 'Wizard Archetype')).to eq []
        expect(casts_from?(char, 'Cleric')).to be true

        Pf2e.redo_rollback(Character[char.id])

        expect(casts_from?(char, 'Wizard Archetype')).to be true
        expect(cells(char)[ [ 'Wizard Archetype', '', 'cantrip' ] ]).to eq 2
        expect(class_rows(char, 'Wizard Archetype').size).to eq 1
      end

      it "should take back an innate spell a later level gave" do
        char = approved('Cleric')
        held = Pf2emagic::Entries.innate_grants(magic(char)).size

        level_up(char, 2, 'Cleric' => { 'innate_spell' => { 'name' => [ 'Charm' ], 'level' => 1, 'tradition' => 'divine', 'cast_stat' => 'Charisma' } })
        expect(Pf2emagic::Entries.knows_innate?(magic(char), 'Charm')).to be true

        Pf2e.rollback_to_level(Character[char.id], 2)

        expect(Pf2emagic::Entries.knows_innate?(magic(char), 'Charm')).to be false
        expect(Pf2emagic::Entries.innate_grants(magic(char)).size).to eq held

        Pf2e.redo_rollback(Character[char.id])

        expect(Pf2emagic::Entries.knows_innate?(magic(char), 'Charm')).to be true
      end

      it "should give a slot feat's bonus once when it is rolled back and taken again" do
        char = approved('Cleric')
        base = cells(char)[ [ 'Cleric', '', '1' ] ]

        level_up(char, 2, 'Cleric' => { 'spells_per_day' => { '1' => '+1' } })
        expect(cells(char)[ [ 'Cleric', '', '1' ] ]).to eq base + 1

        Pf2e.rollback_to_level(Character[char.id], 2)
        expect(cells(char)[ [ 'Cleric', '', '1' ] ]).to eq base

        level_up(char, 2, 'Cleric' => { 'spells_per_day' => { '1' => '+1' } })
        expect(cells(char)[ [ 'Cleric', '', '1' ] ]).to eq base + 1
      end

      it "should bring back the earlier spell proficiency below a raise" do
        char = approved('Cleric')

        level_up(char, 2, 'Cleric' => { 'tradition' => { 'divine' => 'expert' } })
        expect(Pf2emagic::Entries.proficiency_of(magic(char), 'Cleric')).to eq 'expert'

        Pf2e.rollback_to_level(Character[char.id], 2)

        expect(magic(char).tradition['Cleric']).to eq [ 'divine', 'trained' ]
        expect(Pf2emagic::Entries.proficiency_of(magic(char), 'Cleric')).to eq 'trained'
      end

      # A character whose spellcasting predates the change: nothing records it, so nothing takes it.
      it "should leave spellcasting the ledger never recorded where it is" do
        char = approved('Cleric')
        Character[char.id].grants.to_a.each { |g| g.delete if %w{casting spell_slots innate_spell}.include?(g.kind) }
        PF2Magic.update_magic(Character[char.id], 'Cleric', { 'spells_per_day' => { '2' => 1 } }, @client)
        before = [ magic(char).tradition, magic(char).spell_abil, cells(char) ]

        Ledger.invalidate!(char)
        Ledger.materialize!(Character[char.id])

        expect([ magic(char).tradition, magic(char).spell_abil, cells(char) ]).to eq before
      end

      # The real commands, end to end: a Wizard climbed to 3 and rolled back has their level 2 slots.
      it "should put a Wizard rolled back from 3 to 2 on their level 2 slots, and a redo on their level 3 ones" do
        char = Character.create(:name => "Wiz#{rand(1000000)}")
        @made << char
        builder = AutoBuilder.new(char)

        builder.build('Wizard', 2)
        at_two = cells(char)

        builder.advance_to(3)
        expect(builder.failures).to eq []
        at_three = cells(char)
        expect(at_three).not_to eq at_two

        expect(Pf2e.rollback_to_level(Character[char.id], 3)).to be_nil
        expect(cells(char)).to eq at_two

        expect(Pf2e.redo_rollback(Character[char.id])).to be_nil
        expect(cells(char)).to eq at_three
      end
    end
  end
end
