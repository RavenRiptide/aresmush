require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Feats read as a spell is cast (CastFeats): casting after a rank's slots run out, a battle form cast
    # as a signature spell, and a divine font spell traded for another.
    describe "feats read as a spell is cast", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Feat#{rand(1000000)}")
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

      # A caster with 2 slots at each rank to `top`, at the level that casts it.
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

      def empty_rank(charclass, rank)
        today = char.magic.spells_today
        today[charclass][rank.to_s] = 0
        char.magic.update(:spells_today => today)
      end

      def cast(charclass, spell, rank)
        Pf2emagic.cast_spell(char, charclass, spell, [], rank)
      end

      describe "Studious Capacity" do
        before(:each) do
          caster('Bard', 'occult', [ 'Studious Capacity' ], 8,
                 :repertoire => { 'Bard' => { '3' => [ 'Haste' ], '8' => [ 'Fear' ] } })
        end

        it "should cast once after the rank's slots run out" do
          empty_rank('Bard', 3)

          cast = cast('Bard', 'Haste', 3)

          expect(cast['spell type']).to eq 'Studious Capacity'
          expect(char.magic.spells_today['Bard']['3']).to eq 0
          expect(cast('Bard', 'Haste', 3)).to eq t('pf2emagic.no_available_slots')
        end

        it "should spend a slot while there is one" do
          expect(cast('Bard', 'Haste', 3)['spell type']).to be_nil
          expect(char.magic.spells_today['Bard']['3']).to eq 1
        end

        it "should not cast at the highest rank" do
          empty_rank('Bard', 8)

          expect(cast('Bard', 'Fear', 8)).to eq t('pf2emagic.no_available_slots')
        end

        it "should say on the magic display that it is not for the highest rank" do
          template = PF2MagicDisplayTemplate.new(char, char.magic, double)

          expect(template.format_cast_feats(char, 'Bard')).to include(
            "Studious Capacity:%xn 1 (#{t('pf2emagic.cast_feat_overflow')}; #{t('pf2emagic.cast_feat_not_top')})")
        end

        it "should show nothing for a class without such a feat" do
          template = PF2MagicDisplayTemplate.new(char, char.magic, double)

          expect(template.format_cast_feats(char, 'Sorcerer')).to eq ''
        end

        it "should be unused again after a rest" do
          empty_rank('Bard', 3)
          cast('Bard', 'Haste', 3)
          Pf2emagic.generate_spells_today(char)
          empty_rank('Bard', 3)

          expect(cast('Bard', 'Haste', 3)).to be_a Hash
        end
      end

      describe "Divine Effusion" do
        before(:each) do
          caster('Oracle', 'divine', [ 'Divine Effusion' ], 9,
                 :repertoire => { 'Oracle' => { '2' => [ 'Fear' ], '3' => [ 'Heal' ] } })
          empty_rank('Oracle', 2)
          empty_rank('Oracle', 3)
        end

        it "should cast twice, at different ranks" do
          expect(cast('Oracle', 'Fear', 2)['spell type']).to eq 'Divine Effusion'
          expect(cast('Oracle', 'Heal', 3)['spell type']).to eq 'Divine Effusion'
        end

        it "should not cast twice at one rank" do
          cast('Oracle', 'Fear', 2)

          expect(cast('Oracle', 'Fear', 2)).to eq t('pf2emagic.no_available_slots')
        end

        it "should show the uses left and the ranks used on the magic display" do
          template = PF2MagicDisplayTemplate.new(char, char.magic, double)

          expect(template.format_cast_feats(char, 'Oracle')).to include(
            t('pf2emagic.cast_feats_title'), "Divine Effusion:%xn 2 (#{t('pf2emagic.cast_feat_overflow')})")

          cast('Oracle', 'Fear', 2)

          expect(template.format_cast_feats(char, 'Oracle')).to include(
            "Divine Effusion:%xn 1 (#{t('pf2emagic.cast_feat_overflow')}; #{t('pf2emagic.cast_feat_used_at', :ranks => '2')})")
        end
      end

      describe "Greater Physical Evolution" do
        before(:each) do
          caster('Sorcerer', 'primal', [ 'Greater Physical Evolution' ], 6,
                 :repertoire => { 'Sorcerer' => { '1' => [ 'Fear' ] } })
        end

        it "should cast a battle form outside the repertoire from a slot of its rank, once a day" do
          cast = cast('Sorcerer', 'Animal Form', 4)

          expect(cast['spell type']).to eq 'Greater Physical Evolution'
          expect(cast['spell level']).to eq '4'
          expect(char.magic.spells_today['Sorcerer']['4']).to eq 1
          expect(cast('Sorcerer', 'Animal Form', 4)).to eq t('pf2emagic.not_in_list')
        end

        it "should not cast a spell that grants no battle form" do
          expect(cast('Sorcerer', 'Haste', 4)).to eq t('pf2emagic.not_in_list')
        end

        it "should show the use left on the magic display" do
          cast('Sorcerer', 'Animal Form', 4)

          template = PF2MagicDisplayTemplate.new(char, char.magic, double)

          expect(template.format_cast_feats(char, 'Sorcerer')).to include(
            "Greater Physical Evolution:%xn 0 (#{t('pf2emagic.cast_feat_battle_form')})")
        end

        it "should know the battle form spells by their text" do
          expect(CastFeats.battle_form?('Animal Form')).to eq true
          expect(CastFeats.battle_form?('Dragon Form')).to eq true
          expect(CastFeats.battle_form?('Haste')).to eq false
        end
      end

      describe "Restorative Channel" do
        before(:each) do
          caster('Cleric', 'divine', [ 'Restorative Channel' ], 5, :divine_font => 'heal')
          today = char.magic.spells_today
          today['Cleric'] = { 'cantrip' => [], '4' => [ 'Fear' ], '5' => [ 'Heal', 'Heal', 'Fear' ] }
          char.magic.update(:spells_today => today)
        end

        def fives
          char.magic.spells_today['Cleric']['5']
        end

        it "should trade a heal at the font's rank for one of its spells, heightened to that rank" do
          cast = cast('Cleric', 'Sound Body', nil)

          expect(cast['spell level']).to eq '5'
          expect(cast['spell type']).to eq 'Restorative Channel (Heal)'
          expect(fives).to eq [ 'Heal', 'Fear' ]
        end

        it "should refuse a rank other than the font's" do
          expect(cast('Cleric', 'Sound Body', '4')).to be_a String
          expect(fives).to eq [ 'Heal', 'Heal', 'Fear' ]
        end

        it "should refuse once no heal is left" do
          2.times { cast('Cleric', 'Sound Body', nil) }

          expect(cast('Cleric', 'Sound Body', nil)).to be_a String
          expect(fives).to eq [ 'Fear' ]
        end

        it "should not trade for a spell the feat does not name" do
          expect(cast('Cleric', 'Haste', nil)).to be_a String
          expect(fives).to eq [ 'Heal', 'Heal', 'Fear' ]
        end
      end
    end
  end
end
