require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # A spell a Staff Nexus wizard's makeshift staff holds stays in their spellbook, and a rollback is
    # one of the ways out: it is refused while the makeshift staff holds a spell the rolled-back levels
    # gave them.
    describe "the makeshift staff and rollback", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Nexus#{rand(1000000)}")

        AutoBuilder.new(@char).build_level_one('Wizard', :option => 'Staff Nexus')
        Roles.add_role(@char, 'approved')
        Ledger.commit_chargen!(Character[@char.id])
      end

      after(:each) do
        @char.delete if @char
      end

      def char
        Character[@char.id]
      end

      def book(slot)
        Staves.spellbook_at(char, slot)
      end

      # A 1st-rank spell the spellbook doesn't hold yet, learned at level 2.
      def learned_at_two
        spell = [ 'Fear', 'Grease', 'Sure Strike', 'Mystic Armor', 'Gust of Wind' ]
                  .find { |name| Global.read_config('pf2e_spells', name) && !book('1').include?(name) }
        magic = char.magic

        magic.update(:spellbook => magic.spellbook.merge('Wizard' => magic.spellbook['Wizard'].merge('1' => book('1') + [ spell ])))
        char.update(:pf2_level => 2)
        Ledger.commit_level_up!(char, 2, :cost => 0)

        spell
      end

      it "should have picked the makeshift staff's two spells in chargen" do
        picks = Staves.makeshift_picks(char)

        expect(picks.keys).to eq [ 'cantrip', '1' ]
        expect(book('cantrip')).to include picks['cantrip']
        expect(book('1')).to include picks['1']
        expect(Pf2e.open_magic_choices?(char)).to be false
      end

      it "should refuse a rollback that would take the makeshift staff's spell out of the spellbook" do
        spell = learned_at_two
        Staves.write_makeshift!(char, '1', spell)

        refused = Pf2e.rollback_to_level(char, 2)

        expect(refused).to eq t('pf2e.rollback_makeshift', :char => char.name, :spell => spell, :slot => '1st-rank spell', :level => 2)
        expect(char.pf2_level).to eq 2
        expect(book('1')).to include spell
      end

      it "should allow it once staff set the makeshift staff a spell the rollback keeps" do
        kept = Staves.makeshift_picks(char)['1']
        spell = learned_at_two
        Staves.write_makeshift!(char, '1', spell)
        Staves.write_makeshift!(char, '1', kept)

        expect(Pf2e.rollback_to_level(char, 2)).to be_nil
        expect(char.pf2_level).to eq 1
        expect(book('1')).not_to include spell
      end
    end
  end
end
