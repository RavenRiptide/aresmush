require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Grown of Oak's at-will innate spell and Ultimate Polymath's signature spells, cast through the
    # same calls `encounter/cast` makes.
    describe "at-will innate spells and every spell a signature spell, cast", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Cast#{rand(1000000)}")
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 16) }
      end

      after(:each) do
        live = Character[@char.id]

        live.spellcasting_entries.each(&:delete) if live.respond_to?(:spellcasting_entries)
        live.magic.delete if live.magic
        @abilities.each(&:delete)
        live.delete
      end

      def char
        Character[@char.id]
      end

      def caster(charclass, tradition, feats, top, extra = {})
        per_day = (1..top).each_with_object({ 'cantrip' => 5 }) { |rank, out| out[rank.to_s] = 2 }
        magic = PF2Magic.create({ :character => @char,
                                  :tradition => { charclass => [ tradition, 'trained' ] },
                                  :spell_abil => { charclass => 'Charisma' },
                                  :spells_per_day => { charclass => per_day } }.merge(extra))

        @char.update(:magic => magic, :pf2_level => top * 2, :pf2_feats => { 'charclass' => feats },
                     :pf2_base_info => { 'charclass' => charclass })

        Pf2emagic.generate_spells_today(char)
      end

      describe "Grown of Oak" do
        before(:each) do
          grant = { 'name' => 'Oaken Resilience', 'level' => 'at will', 'below_top' => 1,
                    'tradition' => 'primal', 'cast_stat' => 'Charisma' }

          caster('Druid', 'primal', [ 'Grown of Oak' ], 4,
                 :innate_spells => [ grant ], :tradition => { 'Druid' => [ 'primal', 'trained' ], 'innate' => [ 'innate', 'trained' ] })
        end

        def cast
          Pf2emagic.cast_spell(char, 'Innate', 'Oaken Resilience', [], nil, 'innate')
        end

        it "should cast at one rank below the highest the druid casts" do
          expect(cast['spell level']).to eq 3
        end

        it "should cast again and again" do
          3.times { cast }

          expect(cast).to be_a Hash
        end

        it "should rise with the druid's highest rank" do
          per_day = char.magic.spells_per_day
          char.magic.update(:spells_per_day => per_day.merge('Druid' => per_day['Druid'].merge('5' => 1)))

          expect(cast['spell level']).to eq 4
        end
      end

      describe "Ultimate Polymath" do
        def bard(feats)
          caster('Bard', 'occult', feats, 5, :repertoire => { 'Bard' => { '1' => [ 'Fear' ] } })
        end

        it "should heighten a repertoire spell that was never made a signature spell" do
          bard([ 'Ultimate Polymath' ])

          cast = Pf2emagic.cast_spell(char, 'Bard', 'Fear', [], 4)

          expect(cast).to be_a Hash
          expect(cast['spell level']).to eq '4'
          expect(char.magic.spells_today['Bard']['4']).to eq 1
        end

        it "should not heighten it without the feat" do
          bard([])

          expect(Pf2emagic.cast_spell(char, 'Bard', 'Fear', [], 4)).to eq t('pf2emagic.not_in_list')
        end
      end
    end
  end
end
